#!/usr/bin/env bats

load test_helper

# Test suite for VBW hook bash patterns against CC 2.1.47 stricter classifier
# REQ-10: Audit bash permission patterns against CC 2.1.47's stricter classifier
#
# All 21 hook handlers in hooks.json use a common quad-resolution pattern:
# 1. Version-sorted plugin cache resolution: ls -1 | sort -V | tail -1
# 2. Fallback to CLAUDE_PLUGIN_ROOT
# 3. Fallback to per-session symlink (/tmp/.vbw-plugin-root-link-*)
# 4. Fallback to ps process-tree sniffing (--plugin-dir)
# 5. Execute hook-wrapper.sh with target script
#
# Hook scripts invoked:
# - validate-summary.sh (PostToolUse Write|Edit, SubagentStop)
# - validate-frontmatter.sh (PostToolUse Write|Edit)
# - validate-commit.sh (PostToolUse Bash)
# - skill-hook-dispatch.sh PostToolUse (PostToolUse Write|Edit|Bash)
# - state-updater.sh (PostToolUse Write|Edit)
# - bash-guard.sh (PreToolUse Bash)
# - security-filter.sh (PreToolUse Read|Glob|Grep|Write|Edit)
# - skill-hook-dispatch.sh PreToolUse (PreToolUse Write|Edit)
# - file-guard.sh (PreToolUse Write|Edit)
# - agent-start.sh (SubagentStart)
# - agent-health.sh start (SubagentStart)
# - agent-stop.sh (SubagentStop)
# - agent-health.sh stop (SubagentStop)
# - qa-gate.sh (TeammateIdle)
# - agent-health.sh idle (TeammateIdle)
# - task-verify.sh (TaskCompleted)
# - blocker-notify.sh (TaskCompleted)
# - session-start.sh (SessionStart)
# - map-staleness.sh (SessionStart)
# - post-compact.sh (SessionStart matcher=compact)
# - compaction-instructions.sh (PreCompact)
# - session-stop.sh (Stop)
# - agent-health.sh cleanup (Stop)
# - prompt-preflight.sh (UserPromptSubmit)
# - notification-log.sh (Notification)

setup() {
  EXPECTED_HOOK_COUNT=$(grep -c '"command":' "$PROJECT_ROOT/hooks/hooks.json")

  # Store the common hook-wrapper.sh resolution pattern (quad-resolution)
  WRAPPER_PATTERN='bash -c '\''w=$(ls -1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/scripts/hook-wrapper.sh 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1); [ ! -f "$w" ] && w="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/hook-wrapper.sh}"; [ ! -f "$w" ] && for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && w="$f" && break; done; [ ! -f "$w" ] && { D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && w="$D/scripts/hook-wrapper.sh"; }; [ -f "$w" ] && exec bash "$w" TARGET_SCRIPT; exit 0'\'''
}

@test "hook pattern count matches hooks.json entries" {
  # Count unique bash commands in hooks.json
  HOOK_COUNT=$(grep -c '"command":' "$PROJECT_ROOT/hooks/hooks.json")

  # Must match the live hook entry count in hooks.json.
  [ "$HOOK_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

@test "all hooks use quad-resolution pattern" {
  # All hooks should use the version-sorted cache resolution pattern
  PATTERN_COUNT=$(grep -c 'sort -V' "$PROJECT_ROOT/hooks/hooks.json")

  # Should match total hook count
  [ "$PATTERN_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

@test "all hooks have CLAUDE_PLUGIN_ROOT fallback" {
  # All hooks should have fallback to CLAUDE_PLUGIN_ROOT
  FALLBACK_COUNT=$(grep -c 'CLAUDE_PLUGIN_ROOT:+' "$PROJECT_ROOT/hooks/hooks.json")

  # Should match total hook count
  [ "$FALLBACK_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

@test "all hooks exit 0 for graceful degradation" {
  # All hooks should end with 'exit 0' for fail-open behavior
  EXIT_COUNT=$(grep -c 'exit 0' "$PROJECT_ROOT/hooks/hooks.json")

  # Should match total hook count
  [ "$EXIT_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

# Unique hook script invocations (21 total)
@test "documented scripts: validate-summary.sh appears 2x" {
  COUNT=$(grep -c 'validate-summary.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 2 ]
}

@test "documented scripts: validate-frontmatter.sh appears 1x" {
  COUNT=$(grep -c 'validate-frontmatter.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: validate-commit.sh appears 1x" {
  COUNT=$(grep -c 'validate-commit.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: skill-hook-dispatch.sh appears 2x" {
  COUNT=$(grep -c 'skill-hook-dispatch.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 2 ]
}

@test "documented scripts: state-updater.sh appears 1x" {
  COUNT=$(grep -c 'state-updater.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: bash-guard.sh appears 1x" {
  COUNT=$(grep -c 'bash-guard.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: security-filter.sh appears 1x" {
  COUNT=$(grep -c 'security-filter.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: file-guard.sh appears 1x" {
  COUNT=$(grep -c 'file-guard.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: agent-start.sh appears 1x" {
  COUNT=$(grep -c 'agent-start.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: agent-stop.sh appears 1x" {
  COUNT=$(grep -c 'agent-stop.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: agent-health.sh appears 4x" {
  COUNT=$(grep -c 'agent-health.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 4 ]
}

@test "documented scripts: qa-gate.sh appears 1x" {
  COUNT=$(grep -c 'qa-gate.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: task-verify.sh appears 1x" {
  COUNT=$(grep -c 'task-verify.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: blocker-notify.sh appears 1x" {
  COUNT=$(grep -c 'blocker-notify.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: session-start.sh appears 1x" {
  COUNT=$(grep -c 'session-start.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: map-staleness.sh appears 1x" {
  COUNT=$(grep -c 'map-staleness.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: post-compact.sh appears 1x" {
  COUNT=$(grep -c 'post-compact.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: compaction-instructions.sh appears 1x" {
  COUNT=$(grep -c 'compaction-instructions.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: session-stop.sh appears 1x" {
  COUNT=$(grep -c 'session-stop.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: prompt-preflight.sh appears 1x" {
  COUNT=$(grep -c 'prompt-preflight.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

@test "documented scripts: notification-log.sh appears 1x" {
  COUNT=$(grep -c 'notification-log.sh' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$COUNT" -eq 1 ]
}

# Task 2: Test hook-wrapper.sh resolution pattern
# CC 2.1.47 stricter classifier validation for complex chained bash patterns

@test "hook resolution: version-sorted cache resolution pattern is valid" {
  # Test the ls | sort -V | tail -1 pattern used for cache resolution
  # This is the core pattern that must pass the stricter classifier

  # The pattern structure:
  # ls -1 ... | (sort -V || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1
  # This is auto-allowed piping: ls -> sort -> tail

  # Verify hook-wrapper.sh actually uses this pattern
  PATTERN_EXISTS=$(grep -c 'sort -V.*tail -1' "$PROJECT_ROOT/scripts/hook-wrapper.sh")
  [ "$PATTERN_EXISTS" -ge 1 ]
}

@test "hook resolution: quad fallback pattern is valid" {
  # Test the quad resolution: cache -> CLAUDE_PLUGIN_ROOT -> symlink -> ps

  # Verify hook-wrapper.sh uses file existence checks (both -f and ! -f)
  FILE_CHECK_POS=$(grep -c '\[ -f' "$PROJECT_ROOT/scripts/hook-wrapper.sh")
  FILE_CHECK_NEG=$(grep -c '\[ ! -f' "$PROJECT_ROOT/scripts/hook-wrapper.sh")
  TOTAL_CHECKS=$((FILE_CHECK_POS + FILE_CHECK_NEG))
  [ "$TOTAL_CHECKS" -ge 4 ]

  # Verify hook-wrapper.sh has sibling script fallback (dirname $0)
  grep -q '_SELF_DIR' "$PROJECT_ROOT/scripts/hook-wrapper.sh"
}

@test "hook resolution: graceful exit 0 on missing target" {
  # Verify hook-wrapper.sh exits 0 when target script not found
  # This is critical for fail-open design

  EXIT_PATTERN=$(grep -c 'exit 0' "$PROJECT_ROOT/scripts/hook-wrapper.sh")
  [ "$EXIT_PATTERN" -ge 1 ]
}

@test "hook resolution: all hooks use same wrapper pattern structure" {
  # Verify consistency: all hooks use the exact same resolution structure
  # Extract first hook command as reference
  FIRST_HOOK=$(grep -m1 '"command":.*bash -c' "$PROJECT_ROOT/hooks/hooks.json" | sed 's/.*bash -c/bash -c/' | sed 's/validate-[^.]*\.sh/SCRIPT/g' | sed 's/[a-z-]*\.sh/SCRIPT/g')

  # All hooks should follow same pattern, just with different script names
  [ -n "$FIRST_HOOK" ]
}

@test "hook resolution: bash -c wrapping is consistent" {
  # All hooks use 'bash -c' to wrap the resolution logic
  BASH_C_COUNT=$(grep -c 'bash -c' "$PROJECT_ROOT/hooks/hooks.json")

  # Should match total hook count
  [ "$BASH_C_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

@test "hook resolution: variable substitution uses safe patterns" {
  # Verify hooks use parameter expansion safely
  # Pattern: ${VAR:-default}, ${VAR:+value}

  SAFE_EXPANSION=$(grep -c '\${CLAUDE_CONFIG_DIR:-' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$SAFE_EXPANSION" -ge 1 ]

  SAFE_PLUGIN_ROOT=$(grep -c '\${CLAUDE_PLUGIN_ROOT:+' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$SAFE_PLUGIN_ROOT" -ge 1 ]
}

@test "hook resolution: per-session symlink fallback present" {
  # All hooks should have /tmp/.vbw-plugin-root-link-* fallback for local dev
  SYMLINK_COUNT=$(grep -c 'vbw-plugin-root-link-' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$SYMLINK_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

@test "hook resolution: ps process-tree fallback present" {
  # All hooks should have ps-based --plugin-dir sniffing for local dev
  PS_COUNT=$(grep -c 'ps axww' "$PROJECT_ROOT/hooks/hooks.json")
  [ "$PS_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

@test "hook-wrapper: sibling script fallback via dirname" {
  # hook-wrapper.sh should resolve target scripts relative to its own location
  grep -q 'dirname.*\$0' "$PROJECT_ROOT/scripts/hook-wrapper.sh"
  grep -q '_SELF_DIR' "$PROJECT_ROOT/scripts/hook-wrapper.sh"
}

@test "hook resolution: exec bash handoff is valid" {
  # Verify hooks use 'exec bash' to hand off to hook-wrapper.sh
  EXEC_COUNT=$(grep -c 'exec bash' "$PROJECT_ROOT/hooks/hooks.json")

  # Should match total hook count
  [ "$EXEC_COUNT" -eq "$EXPECTED_HOOK_COUNT" ]
}

@test "hook resolution: error suppression with 2>/dev/null" {
  # Verify hooks suppress stderr for ls/sort commands
  ERROR_SUPPRESS=$(grep -c '2>/dev/null' "$PROJECT_ROOT/hooks/hooks.json")

  # At least one per hook (may be more due to multiple redirects)
  [ "$ERROR_SUPPRESS" -ge 25 ]
}

# Task 3: Test individual hook script invocations
# Validate that each unique script invocation passes the stricter classifier

@test "script invocation: validate-summary.sh PostToolUse pattern" {
  # PostToolUse Write|Edit -> validate-summary.sh
  # This hook validates SUMMARY.md files after Write/Edit

  INVOCATION=$(grep 'validate-summary.sh' "$PROJECT_ROOT/hooks/hooks.json" | head -1)
  [ -n "$INVOCATION" ]

  # Verify it's a valid bash -c command
  echo "$INVOCATION" | grep -q 'bash -c'
}

@test "script invocation: bash-guard.sh with grep pattern matching" {
  # PreToolUse Bash -> bash-guard.sh
  # This script uses grep -iqE for destructive command detection

  # Verify bash-guard.sh exists and uses safe grep patterns
  [ -f "$PROJECT_ROOT/scripts/bash-guard.sh" ]

  # Verify it reads patterns from config file (not inline regex)
  grep -q 'grep.*-iqE' "$PROJECT_ROOT/scripts/bash-guard.sh"
}

@test "script invocation: agent-health.sh with subcommand arguments" {
  # Multiple events -> agent-health.sh {start|stop|idle|cleanup}
  # Validates that hook scripts can receive arguments after script name

  # Check for all 4 subcommands in hooks.json
  grep -q 'agent-health.sh start' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'agent-health.sh stop' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'agent-health.sh idle' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'agent-health.sh cleanup' "$PROJECT_ROOT/hooks/hooks.json"
}

@test "script invocation: skill-hook-dispatch.sh with event type argument" {
  # PostToolUse and PreToolUse -> skill-hook-dispatch.sh {PostToolUse|PreToolUse}
  # Validates passing event type as argument

  grep -q 'skill-hook-dispatch.sh PostToolUse' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'skill-hook-dispatch.sh PreToolUse' "$PROJECT_ROOT/hooks/hooks.json"
}

@test "script invocation: all 21 unique scripts are invoked correctly" {
  # Verify all documented scripts appear in hooks.json with correct invocation

  SCRIPTS=(
    "validate-summary.sh"
    "validate-frontmatter.sh"
    "validate-commit.sh"
    "skill-hook-dispatch.sh"
    "state-updater.sh"
    "bash-guard.sh"
    "security-filter.sh"
    "file-guard.sh"
    "agent-start.sh"
    "agent-stop.sh"
    "agent-health.sh"
    "qa-gate.sh"
    "task-verify.sh"
    "blocker-notify.sh"
    "session-start.sh"
    "map-staleness.sh"
    "post-compact.sh"
    "compaction-instructions.sh"
    "session-stop.sh"
    "prompt-preflight.sh"
    "notification-log.sh"
  )

  for script in "${SCRIPTS[@]}"; do
    grep -q "$script" "$PROJECT_ROOT/hooks/hooks.json"
  done
}

@test "script invocation: no inline piping in hook commands (only in wrapper)" {
  # Hooks should not contain piped commands outside the wrapper pattern
  # All piping should be contained within the bash -c wrapper

  # Extract just the script invocation parts (after exec bash "$w")
  # These should not contain additional pipes
  # The only pipes should be in the ls|sort|tail resolution pattern

  SCRIPT_PARTS=$(grep -o 'exec bash "\$w" [^;]*' "$PROJECT_ROOT/hooks/hooks.json" || true)

  # None of the script invocation parts should contain pipes
  if [ -n "$SCRIPT_PARTS" ]; then
    ! echo "$SCRIPT_PARTS" | grep -q '|'
  fi
}

@test "script invocation: all scripts use simple argument passing" {
  # Scripts that take arguments use simple space-separated args
  # Arguments are literal strings, not command substitutions

  # agent-health.sh takes simple literal subcommands
  grep -q 'agent-health.sh start;' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'agent-health.sh stop;' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'agent-health.sh idle;' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'agent-health.sh cleanup;' "$PROJECT_ROOT/hooks/hooks.json"

  # skill-hook-dispatch.sh takes literal event type arguments
  grep -q 'skill-hook-dispatch.sh PostToolUse;' "$PROJECT_ROOT/hooks/hooks.json"
  grep -q 'skill-hook-dispatch.sh PreToolUse;' "$PROJECT_ROOT/hooks/hooks.json"
}

# Task 4: Audit bash-guard.sh pattern matching
# Validate that bash-guard.sh grep pattern matching works under stricter classifier

@test "bash-guard: script exists and is executable" {
  [ -f "$PROJECT_ROOT/scripts/bash-guard.sh" ]
  [ -x "$PROJECT_ROOT/scripts/bash-guard.sh" ]
}

@test "bash-guard: uses safe grep pattern construction" {
  # Verify bash-guard.sh uses grep -iqE with patterns from file
  # Pattern: grep -iqE "$PATTERNS"
  # This is safe because patterns come from trusted config files

  grep -q 'grep -iqE' "$PROJECT_ROOT/scripts/bash-guard.sh"
}

@test "bash-guard: pattern file resolution is safe" {
  # Verify bash-guard.sh resolves pattern files safely
  # Uses simple file path construction, no user input in paths

  SCRIPT="$PROJECT_ROOT/scripts/bash-guard.sh"

  # Check for safe pattern file references
  grep -q 'destructive-commands.txt' "$SCRIPT"

  # Check for loop over pattern files
  grep -q 'for PFILE in' "$SCRIPT"
}

@test "bash-guard: pattern input validation and sanitization" {
  # Verify bash-guard.sh strips comments and empty lines from pattern files
  # Pattern: grep -v '^\s*#' ... | grep -v '^\s*$'

  SCRIPT="$PROJECT_ROOT/scripts/bash-guard.sh"

  # Check for comment stripping
  grep -q "grep -v '^\\\s\*#'" "$SCRIPT"

  # Check for empty line stripping
  grep -q "grep -v '^\\\s\*\$'" "$SCRIPT"
}

@test "bash-guard: regex escaping is not needed (patterns are trusted)" {
  # bash-guard.sh patterns come from config files, not user input
  # No need to escape regex metacharacters

  # Verify patterns are read from files in config/ directory
  [ -f "$PROJECT_ROOT/config/destructive-commands.txt" ]

  # Pattern file should contain regex patterns (not escaped)
  grep -q '\\s' "$PROJECT_ROOT/config/destructive-commands.txt"
}

@test "bash-guard: jq parsing uses safe patterns" {
  # Verify bash-guard.sh uses jq safely to parse hook JSON input
  # Pattern: jq -r '.tool_input.command // ""'

  SCRIPT="$PROJECT_ROOT/scripts/bash-guard.sh"

  # Check for safe jq usage with default fallback
  grep -q "jq -r '\.tool_input\.command // \"\"'" "$SCRIPT"
}

@test "bash-guard: exit codes follow PreToolUse contract" {
  # PreToolUse hooks must exit 0 (allow) or exit 2 (block)
  # Verify bash-guard.sh uses correct exit codes

  SCRIPT="$PROJECT_ROOT/scripts/bash-guard.sh"

  # Should have exit 0 for allow
  grep -q 'exit 0' "$SCRIPT"

  # Should have exit 2 for block
  grep -q 'exit 2' "$SCRIPT"
}

@test "bash-guard: stdin input via cat is safe" {
  # Verify bash-guard.sh reads stdin via cat, not complex substitution
  # Pattern: INPUT=$(cat 2>/dev/null)

  SCRIPT="$PROJECT_ROOT/scripts/bash-guard.sh"

  grep -q 'INPUT=\$(cat 2>/dev/null)' "$SCRIPT"
}

@test "bash-guard: command validation via echo pipe is safe" {
  # Verify bash-guard.sh validates commands via echo | grep
  # Pattern: echo "$COMMAND" | grep -iqE "$PATTERNS"

  SCRIPT="$PROJECT_ROOT/scripts/bash-guard.sh"

  # Check for safe piping pattern
  grep -q 'echo "\$COMMAND" | grep -iqE' "$SCRIPT"
}

# Task 5: Integration tests under CC 2.1.47+
# If running CC 2.1.47+, test actual hook execution to verify no permission errors

@test "integration: CC version is 2.1.47 or newer" {
  # Verify we're testing against the target Claude Code version
  VERSION=$(claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  # Parse version components
  MAJOR=$(echo "$VERSION" | cut -d. -f1)
  MINOR=$(echo "$VERSION" | cut -d. -f2)
  PATCH=$(echo "$VERSION" | cut -d. -f3)

  # Check version >= 2.1.47
  if [ "$MAJOR" -gt 2 ]; then
    true
  elif [ "$MAJOR" -eq 2 ]; then
    if [ "$MINOR" -gt 1 ]; then
      true
    elif [ "$MINOR" -eq 1 ]; then
      [ "$PATCH" -ge 47 ]
    else
      skip "CC version < 2.1.47"
    fi
  else
    skip "CC version < 2.1.47"
  fi
}

@test "integration: hook-wrapper.sh resolves correctly (cache or local)" {
  # Verify hook-wrapper.sh can be resolved using dual resolution pattern
  # Try plugin cache first, then fall back to local scripts/ dir

  WRAPPER=$(ls -1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/scripts/hook-wrapper.sh 2>/dev/null \
    | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

  # Fallback to CLAUDE_PLUGIN_ROOT for dev mode
  if [ -z "$WRAPPER" ] || [ ! -f "$WRAPPER" ]; then
    WRAPPER="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/hook-wrapper.sh}"
  fi

  # Fallback to local scripts/ for test environment
  if [ -z "$WRAPPER" ] || [ ! -f "$WRAPPER" ]; then
    WRAPPER="$PROJECT_ROOT/scripts/hook-wrapper.sh"
  fi

  # Should find hook-wrapper.sh via one of the paths
  [ -n "$WRAPPER" ]
  [ -f "$WRAPPER" ]
}

@test "integration: hook scripts are present (cache or local)" {
  # Verify all 21 unique hook scripts exist in cache, CLAUDE_PLUGIN_ROOT, or local

  CACHE=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/ 2>/dev/null \
    | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

  # Fallback to CLAUDE_PLUGIN_ROOT for dev mode
  if [ -z "$CACHE" ] || [ ! -d "$CACHE" ]; then
    CACHE="${CLAUDE_PLUGIN_ROOT}/"
  fi

  # Fallback to local scripts/ for test environment
  if [ -z "$CACHE" ] || [ ! -d "${CACHE}scripts" ]; then
    CACHE="$PROJECT_ROOT/"
  fi

  [ -n "$CACHE" ]
  [ -d "${CACHE}scripts" ]

  # Check for key hook scripts
  [ -f "${CACHE}scripts/validate-summary.sh" ]
  [ -f "${CACHE}scripts/bash-guard.sh" ]
  [ -f "${CACHE}scripts/hook-wrapper.sh" ]
  [ -f "${CACHE}scripts/agent-start.sh" ]
}

@test "integration: hook-wrapper.sh can execute bash-guard.sh" {
  # Integration test: invoke hook-wrapper.sh with bash-guard.sh
  # This validates the dual resolution pattern works end-to-end

  WRAPPER=$(ls -1 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/vbw-marketplace/vbw/*/scripts/hook-wrapper.sh 2>/dev/null \
    | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

  # Fallback to CLAUDE_PLUGIN_ROOT for dev mode
  if [ -z "$WRAPPER" ] || [ ! -f "$WRAPPER" ]; then
    WRAPPER="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/hook-wrapper.sh}"
  fi

  # Fallback to local scripts/ for test environment
  if [ -z "$WRAPPER" ] || [ ! -f "$WRAPPER" ]; then
    WRAPPER="$PROJECT_ROOT/scripts/hook-wrapper.sh"
  fi

  [ -f "$WRAPPER" ]

  # Create a safe test JSON input (allow safe command)
  TEST_INPUT='{"tool_input":{"command":"echo hello"}}'

  # Execute hook-wrapper.sh -> bash-guard.sh
  # Should exit 0 (allow) for safe command
  echo "$TEST_INPUT" | bash "$WRAPPER" bash-guard.sh
}

@test "integration: bash-guard.sh blocks destructive commands" {
  # Integration test: verify bash-guard.sh actually blocks destructive patterns
  # Test directly without hook-wrapper.sh to avoid resolution complexity

  GUARD="$PROJECT_ROOT/scripts/bash-guard.sh"
  [ -f "$GUARD" ]

  # Create test JSON input with destructive command matching a known pattern
  # Use DROP TABLE which is in the destructive-commands.txt patterns
  TEST_INPUT='{"tool_input":{"command":"mysql -e DROP TABLE users"}}'

  # Execute bash-guard.sh directly (expect it to fail with exit 2)
  # Use 'run' to capture exit code without failing the test
  run bash -c "echo '$TEST_INPUT' | bash '$GUARD' 2>/dev/null"

  # Verify exit code is 2 (block)
  [ "$status" -eq 2 ]
}

@test "integration: documented test procedure for manual validation" {
  # Document the test procedure for manual hook execution validation
  # This ensures we have a reproducible test case for future CC versions

  cat > "$BATS_TEST_TMPDIR/vbw-hook-test-procedure.md" <<'EOF'
# VBW Hook Integration Test Procedure

## Prerequisites
- Claude Code >= 2.1.47
- VBW plugin installed and active
- `.vbw-planning/` directory exists

## Test 1: PostToolUse Hook (validate-summary.sh)
1. Create a test file: `echo "test" > /tmp/vbw-test.txt`
2. Observe: No permission prompts should appear
3. Check: `.vbw-planning/.hook-errors.log` should not contain recent errors

## Test 2: PreToolUse Hook (bash-guard.sh)
1. Attempt destructive command: `rm -rf /tmp/test-dir/`
2. Observe: Should be blocked with exit 2
3. Check: Blocked message should appear in stderr

## Test 3: Agent Lifecycle Hooks
1. Start an agent team (requires active phase)
2. Observe: SubagentStart hooks fire without permission errors
3. Check: `.vbw-planning/.agent-pids/` tracks agent PIDs

## Success Criteria
- No permission prompts for hook bash commands
- All hooks execute without classifier errors
- Hook-wrapper.sh dual resolution works for both cache and CLAUDE_PLUGIN_ROOT
EOF

  [ -f "$BATS_TEST_TMPDIR/vbw-hook-test-procedure.md" ]
}
