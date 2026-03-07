#!/usr/bin/env bash
set -u

# migrate-config.sh — Backfill/rename VBW config keys for brownfield installs.
#
# Usage:
#   bash scripts/migrate-config.sh [path/to/config.json]
#
# Exit codes:
#   0 = success (including no-op when config file missing)
#   1 = malformed config or migration failure

PRINT_ADDED=false
if [ "${1:-}" = "--print-added" ]; then
  PRINT_ADDED=true
  shift
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not found; cannot migrate config." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_FILE="$SCRIPT_DIR/../config/defaults.json"
CONFIG_FILE="${1:-.vbw-planning/config.json}"

if [ ! -f "$DEFAULTS_FILE" ]; then
  echo "ERROR: defaults.json not found: $DEFAULTS_FILE" >&2
  exit 1
fi

if ! jq empty "$DEFAULTS_FILE" >/dev/null 2>&1; then
  echo "ERROR: defaults.json is malformed: $DEFAULTS_FILE" >&2
  exit 1
fi

# No project initialized yet — nothing to migrate.
if [ ! -f "$CONFIG_FILE" ]; then
  if [ "$PRINT_ADDED" = true ]; then
    echo "0"
  fi
  exit 0
fi

# Fail-fast on malformed JSON.
if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "ERROR: Config migration failed (malformed JSON): $CONFIG_FILE" >&2
  exit 1
fi

missing_defaults_count() {
  jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$DEFAULTS_FILE" "$CONFIG_FILE" 2>/dev/null
}

MISSING_BEFORE=$(missing_defaults_count)

apply_update() {
  local filter="$1"
  local tmp
  tmp=$(mktemp)
  if jq "$filter" "$CONFIG_FILE" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$CONFIG_FILE"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Rename legacy key: agent_teams -> prefer_teams
# Mapping:
#   true  -> "always"
#   false -> "auto"
if jq -e 'has("agent_teams") and (has("prefer_teams") | not)' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {prefer_teams: (if .agent_teams == true then "always" else "auto" end)} | del(.agent_teams)'; then
    echo "ERROR: Config migration failed while renaming agent_teams." >&2
    exit 1
  fi
elif jq -e 'has("agent_teams")' "$CONFIG_FILE" >/dev/null 2>&1; then
  # prefer_teams already exists — drop stale key only.
  if ! apply_update 'del(.agent_teams)'; then
    echo "ERROR: Config migration failed while removing stale agent_teams." >&2
    exit 1
  fi
fi

# Ensure required top-level keys exist.
if ! jq -e 'has("model_profile")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {model_profile: "quality"}'; then
    echo "ERROR: Config migration failed while adding model_profile." >&2
    exit 1
  fi
fi

if ! jq -e 'has("model_overrides")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {model_overrides: {}}'; then
    echo "ERROR: Config migration failed while adding model_overrides." >&2
    exit 1
  fi
fi

if ! jq -e 'has("prefer_teams")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {prefer_teams: "always"}'; then
    echo "ERROR: Config migration failed while adding prefer_teams." >&2
    exit 1
  fi
fi


# Strip graduated feature flags — core infrastructure flags are always-on.
# These keys have no runtime effect but accumulate in brownfield configs.
GRADUATED_KEYS='del(
  .v2_hard_contracts, .v2_hard_gates, .v2_typed_protocol, .v2_role_isolation,
  .v3_event_log, .v3_delta_context, .v3_context_cache,
  .v3_plan_research_persist, .v3_schema_validation,
  .v3_contract_lite, .v3_lock_lite
)'
if ! apply_update "$GRADUATED_KEYS"; then
  echo "ERROR: Config migration failed while removing graduated flags." >&2
  exit 1
fi

# Rename optional flags from v2_/v3_ prefix to unprefixed config settings.
# Must happen BEFORE brownfield merge so user values (e.g., v3_metrics=false)
# are preserved under the new name before defaults backfill.
rename_flag() {
  local old_name="$1" new_name="$2"
  if jq -e "has(\"$old_name\")" "$CONFIG_FILE" >/dev/null 2>&1; then
    if ! jq -e "has(\"$new_name\")" "$CONFIG_FILE" >/dev/null 2>&1; then
      # Copy old value to new name
      if ! apply_update ". + {\"$new_name\": .$old_name} | del(.$old_name)"; then
        echo "ERROR: Config migration failed while renaming $old_name to $new_name." >&2
        exit 1
      fi
    else
      # New name already exists — keep it as source of truth and drop legacy key
      if ! apply_update "del(.$old_name)"; then
        echo "ERROR: Config migration failed while removing stale $old_name." >&2
        exit 1
      fi
    fi
  fi
}

rename_flag v2_token_budgets token_budgets
rename_flag v2_two_phase_completion two_phase_completion
rename_flag v3_metrics metrics
rename_flag v3_smart_routing smart_routing
rename_flag v3_validation_gates validation_gates
rename_flag v3_snapshot_resume snapshot_resume
rename_flag v3_lease_locks lease_locks
rename_flag v3_event_recovery event_recovery
rename_flag v3_monorepo_routing monorepo_routing

# Generic brownfield merge: add any keys missing from defaults.json.
# Existing project values always win (defaults are the base layer).
TMP=$(mktemp)
if jq --slurpfile defaults "$DEFAULTS_FILE" '$defaults[0] + .' "$CONFIG_FILE" > "$TMP" 2>/dev/null; then
  mv "$TMP" "$CONFIG_FILE"
else
  rm -f "$TMP"
  echo "ERROR: Config migration failed while merging defaults.json." >&2
  exit 1
fi

MISSING_AFTER=$(missing_defaults_count)
ADDED_COUNT=$((MISSING_BEFORE - MISSING_AFTER))
if [ "$ADDED_COUNT" -lt 0 ]; then
  ADDED_COUNT=0
fi

if [ "$PRINT_ADDED" = true ]; then
  echo "$ADDED_COUNT"
fi

exit 0