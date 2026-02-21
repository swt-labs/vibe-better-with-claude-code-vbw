#!/usr/bin/env bats

# Structural consistency tests for the flag system.
# These catch "forgot to add flag to X" mistakes at CI time by verifying
# that rollout-stages.json, defaults.json, rollout-stage.sh legacy_flag_name(),
# migrate-config.sh, and test_helper.bash create_test_config() all stay in sync.

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# rollout-stages.json ↔ defaults.json
# ---------------------------------------------------------------------------

@test "every rollout-stages flag exists in defaults.json" {
  # Extract all flags from rollout-stages.json across all stages
  local flags
  flags=$(jq -r '.stages[].flags[]' "$CONFIG_DIR/rollout-stages.json" | sort -u)
  for flag in $flags; do
    jq -e --arg f "$flag" 'has($f)' "$CONFIG_DIR/defaults.json" >/dev/null 2>&1 || {
      echo "FAIL: flag '$flag' in rollout-stages.json but missing from defaults.json"
      return 1
    }
  done
}

@test "every boolean flag in defaults.json is in rollout-stages.json or explicitly unmanaged" {
  # Extract boolean flags from defaults.json
  local boolean_flags
  boolean_flags=$(jq -r 'to_entries[] | select(.value == true or .value == false) | .key' "$CONFIG_DIR/defaults.json" | sort)
  # Extract rollout-managed flags
  local managed_flags
  managed_flags=$(jq -r '.stages[].flags[]' "$CONFIG_DIR/rollout-stages.json" | sort -u)
  # Flags that are boolean but intentionally NOT rollout-managed
  # (they have no phased rollout — they're always user-configurable)
  local unmanaged_allowlist="auto_commit auto_install_skills branch_per_milestone context_compiler discovery_questions plain_summary require_phase_discussion skill_suggestions worktree_isolation"
  for flag in $boolean_flags; do
    echo "$managed_flags" | grep -qx "$flag" && continue
    echo "$unmanaged_allowlist" | tr ' ' '\n' | grep -qx "$flag" && continue
    echo "FAIL: boolean flag '$flag' in defaults.json is not in rollout-stages.json and not in unmanaged allowlist"
    return 1
  done
}

# ---------------------------------------------------------------------------
# rollout-stages.json ↔ rollout-stage.sh legacy_flag_name()
# ---------------------------------------------------------------------------

@test "every rollout-stages flag has a legacy_flag_name mapping" {
  local flags
  flags=$(jq -r '.stages[].flags[]' "$CONFIG_DIR/rollout-stages.json" | sort -u)
  for flag in $flags; do
    # legacy_flag_name() should have a case for this flag
    grep -q "^[[:space:]]*${flag})" "$SCRIPTS_DIR/rollout-stage.sh" || {
      echo "FAIL: flag '$flag' has no legacy_flag_name() case in rollout-stage.sh"
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# rollout-stages.json ↔ migrate-config.sh
# ---------------------------------------------------------------------------

@test "every rollout-stages flag has a migration path in migrate-config.sh" {
  local flags
  flags=$(jq -r '.stages[].flags[]' "$CONFIG_DIR/rollout-stages.json" | sort -u)
  for flag in $flags; do
    # migrate-config.sh should reference this flag (either as rename target or strip)
    grep -q "$flag" "$SCRIPTS_DIR/migrate-config.sh" || {
      echo "FAIL: flag '$flag' not referenced in migrate-config.sh"
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# defaults.json ↔ test_helper.bash create_test_config()
# ---------------------------------------------------------------------------

@test "create_test_config includes all boolean flags from defaults.json" {
  # Extract boolean flag names from defaults.json
  local expected_flags
  expected_flags=$(jq -r 'to_entries[] | select(.value == true or .value == false) | .key' "$CONFIG_DIR/defaults.json" | sort)
  # Check that create_test_config's JSON block references each one
  local helper_file="$BATS_TEST_DIRNAME/test_helper.bash"
  for flag in $expected_flags; do
    grep -q "\"${flag}\"" "$helper_file" || {
      echo "FAIL: boolean flag '$flag' from defaults.json not in create_test_config()"
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# rollout-stages.json ↔ feature-flags.bats
# ---------------------------------------------------------------------------

@test "feature-flags.bats checks all rollout-managed flags" {
  local flags
  flags=$(jq -r '.stages[].flags[]' "$CONFIG_DIR/rollout-stages.json" | sort -u)
  local feature_flags_file="$BATS_TEST_DIRNAME/feature-flags.bats"
  for flag in $flags; do
    grep -q "\"${flag}\"" "$feature_flags_file" || {
      echo "FAIL: flag '$flag' from rollout-stages.json not checked in feature-flags.bats"
      return 1
    }
  done
}

# ---------------------------------------------------------------------------
# rollout-stage.bats idempotent test uses dynamic count
# ---------------------------------------------------------------------------

@test "rollout-stage.bats idempotent count matches actual stage-1 flag count" {
  # Read how many flags stage 1 actually has
  local actual_count
  actual_count=$(jq '.stages[] | select(.stage == 1) | .flags | length' "$CONFIG_DIR/rollout-stages.json")
  # Check that rollout-stage.bats test uses a dynamic count (preferred),
  # or a matching literal count.
  local rollout_test="$BATS_TEST_DIRNAME/rollout-stage.bats"
  if grep -q 'flags_already_enabled | length == \${stage1_count}' "$rollout_test"; then
    return 0
  fi

  grep -q "flags_already_enabled | length == ${actual_count}" "$rollout_test" || {
    echo "FAIL: rollout-stage.bats idempotent test has neither dynamic count nor matching literal count. Stage 1 has $actual_count flags."
    return 1
  }
}

# ---------------------------------------------------------------------------
# No stale legacy keys in defaults.json
# ---------------------------------------------------------------------------

@test "defaults.json has no v2_ or v3_ prefixed keys" {
  local stale
  stale=$(jq -r 'keys[] | select(startswith("v2_") or startswith("v3_"))' "$CONFIG_DIR/defaults.json" 2>/dev/null)
  [ -z "$stale" ] || {
    echo "FAIL: defaults.json contains stale prefixed keys: $stale"
    return 1
  }
}
