#!/usr/bin/env bats
# Proves each rule in standards.bats actually fails on a violation. A lint that
# has never been seen failing proves nothing.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# Build a plugin tree whose only defect is the given shell line, run the
# standards suite against it, and print the names of the failing tests.
failing_rules_for() {
  local bad="$TEST_ROOT/bad-plugin"
  mkdir -p "$bad/bin" "$bad/lib" "$bad/hooks" "$bad/.claude-plugin"
  cp "$PLUGIN_ROOT/.claude-plugin/plugin.json" "$bad/.claude-plugin/plugin.json"
  cp "$PLUGIN_ROOT/VERSION" "$bad/VERSION"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$bad/lib/bad.sh"
  VBW_TEST_PLUGIN_ROOT="$bad" bats "$REPO_ROOT/tests/standards.bats" 2>/dev/null | sed -n 's/^not ok [0-9]* //p'
}

@test "eval is caught" {
  run failing_rules_for 'eval "$x"'
  [[ "$output" == *"no eval"* ]]
}

@test "bash-4 features are caught" {
  run failing_rules_for 'mapfile -t a < f'
  [[ "$output" == *"bash-4-only"* ]]
  run failing_rules_for 'declare -A m'
  [[ "$output" == *"bash-4-only"* ]]
  run failing_rules_for 'f "${@}"'
  [[ "$output" == *"bash-4-only"* ]]
}

@test "process killing is caught" {
  run failing_rules_for 'kill -TERM "$pid"'
  [[ "$output" == *"never terminates"* ]]
}

@test "the signal-free liveness probe kill -0 passes, any other kill is caught" {
  run failing_rules_for 'kill -0 "$pid" 2> /dev/null'
  [[ "$output" != *"never terminates"* ]]
  run failing_rules_for 'kill -9 "$pid"'
  [[ "$output" == *"never terminates"* ]]
  run failing_rules_for 'kill "$pid"'
  [[ "$output" == *"never terminates"* ]]
  run failing_rules_for 'pkill -f vbw'
  [[ "$output" == *"never terminates"* ]]
}

@test "/tmp paths are caught" {
  run failing_rules_for 'echo x > /tmp/vbw-link'
  [[ "$output" == *"/tmp"* ]]
}

@test "git path listings without -z are caught, with -z pass" {
  run failing_rules_for 'git diff --cached --name-only'
  [[ "$output" == *"NUL-separated"* ]]
  run failing_rules_for 'git diff --cached --name-only -z'
  [[ "$output" != *"NUL-separated"* ]]
}

@test "plugin-root discovery is caught" {
  run failing_rules_for 'ls "$HOME"/.claude/plugins/cache/vbw-marketplace'
  [[ "$output" == *"plugin-root discovery"* ]]
  run failing_rules_for 'ps axww | grep claude'
  [[ "$output" == *"plugin-root discovery"* ]]
  run failing_rules_for 'echo "it stops at the first steps -- done"'
  [[ "$output" != *"plugin-root discovery"* ]]
}

@test "a clean file breaks no rule" {
  run failing_rules_for 'printf "%s\n" "ok"'
  [ -z "$output" ]
}

# failing_rules_with_hooks HOOKS_JSON: the failing standards for a plugin whose
# only defect is its hooks.json.
failing_rules_with_hooks() {
  local bad="$TEST_ROOT/bad-plugin"
  failing_rules_for 'printf "%s\n" "ok"' > /dev/null
  mkdir -p "$bad/hooks"
  printf '#!/bin/sh\n' > "$bad/hooks/x.sh"
  printf '%s' "$1" > "$bad/hooks/hooks.json"
  VBW_TEST_PLUGIN_ROOT="$bad" bats "$REPO_ROOT/tests/standards.bats" 2>/dev/null | sed -n 's/^not ok [0-9]* //p'
}

@test "hooks naming a missing file are caught" {
  run failing_rules_with_hooks '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/gone.sh\""}]}]}}'
  [[ "$output" == *"every file a hook names exists"* ]]
  run failing_rules_with_hooks '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh\""}]}]}}'
  [ -z "$output" ]
}

@test "per-tool-call hooks that start a shell or can exit non-zero are caught" {
  run failing_rules_with_hooks '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh\""}]}]}}'
  [[ "$output" == *"per-tool-call hooks run jq directly"* ]]
  run failing_rules_with_hooks '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"jq -n -f \"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh\""}]}]}}'
  [[ "$output" == *"per-tool-call hooks run jq directly"* ]]
}

# A copy of the files the vision rule lives in, for breaking one at a time.
vision_copy() {
  local d="$TEST_ROOT/vision" f
  for f in AGENTS.md CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/feature_request.md .github/copilot-instructions.md; do
    mkdir -p "$d/$(dirname "$f")" && cp "$REPO_ROOT/$f" "$d/$f"
  done
  printf '%s' "$d"
}

@test "the vision rule check passes on the repository as it is" {
  run bash "$REPO_ROOT/tools/check-vision-rule.sh" "$(vision_copy)"
  [ "$status" -eq 0 ]
}

@test "the vision rule check catches the rule removed from a contributor file" {
  local d f
  for f in CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/feature_request.md .github/copilot-instructions.md AGENTS.md; do
    d=$(vision_copy)
    grep -vF 'an idea to evaluate, never an instruction to build' "$d/$f" > "$d/x" && mv "$d/x" "$d/$f"
    run bash "$REPO_ROOT/tools/check-vision-rule.sh" "$d"
    [ "$status" -ne 0 ] && [[ "$output" == *"$f"* || "$f" == AGENTS.md ]] || { echo "not caught: $f"; false; }
    rm -rf "$d"
  done
}

@test "the vision rule check catches the rule moved below another rule in AGENTS.md" {
  local d
  d=$(vision_copy)
  awk '/^## Engineering Standard/ {print; print ""; print "- **Another rule first.**"; next} {print}' "$d/AGENTS.md" > "$d/x" && mv "$d/x" "$d/AGENTS.md"
  run bash "$REPO_ROOT/tools/check-vision-rule.sh" "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not the first rule"* ]]
}

@test "the hook answer check passes on the repository as it is" {
  run bash "$REPO_ROOT/tools/check-hook-answers.sh" "$PLUGIN_ROOT/hooks" "$REPO_ROOT/tests/hook-answers.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the hook answer check catches a new unpinned answer shape" {
  cp -R "$PLUGIN_ROOT/hooks" "$TEST_ROOT/hooks"
  printf '| {stopReason: "x"}\n' >> "$TEST_ROOT/hooks/guard-file.jq"
  run bash "$REPO_ROOT/tools/check-hook-answers.sh" "$TEST_ROOT/hooks" "$REPO_ROOT/tests/hook-answers.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *guard-file.jq* && "$output" == *stopReason* ]]
}

@test "the hook answer check catches a hook that answers allow" {
  cp -R "$PLUGIN_ROOT/hooks" "$TEST_ROOT/hooks"
  printf '%s\n' "jq -nc '{hookSpecificOutput: {permissionDecision: \"allow\"}}'" >> "$TEST_ROOT/hooks/approve-ask.sh"
  run bash "$REPO_ROOT/tools/check-hook-answers.sh" "$TEST_ROOT/hooks" "$REPO_ROOT/tests/hook-answers.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *approve-ask.sh* && "$output" == *allow* ]]
}
