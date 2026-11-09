#!/usr/bin/env bats
# R198 (docs/statusline.md, hooks): in a VBW project the SessionStart hook runs
# vbw next once and never vbw status, and takes its project line from the glance
# that vbw next refreshes. vbw status works out the milestone's road from vbw
# next (R191), so a hook that ran both paid for vbw next twice (0.91 s in the
# 2.0.40 release run against R185's 0.8 s). The kernel calls are counted, never
# timed (R152). L1: the hook on a fixture project, with a counting copy of the
# kernel.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  # A copy of the plugin whose bin/vbw logs each call, then runs the real kernel.
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plug"
  cat > "$TEST_ROOT/plug/bin/vbw" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/calls"
exec "$PLUGIN_ROOT/bin/vbw" "\$@"
EOF
  chmod +x "$TEST_ROOT/plug/bin/vbw"
  : > "$TEST_ROOT/calls"
}

teardown() { vbw_teardown; }

session_start() {
  printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"s1"}\n' \
    | CLAUDE_PLUGIN_ROOT="$TEST_ROOT/plug" CLAUDE_PROJECT_DIR="$PROJECT" bash "$TEST_ROOT/plug/hooks/session-start.sh"
}

context() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

@test "R198: the hook runs vbw next once and never vbw status" {
  run session_start
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -c '^next' "$TEST_ROOT/calls" | grep -qx 1 || { cat "$TEST_ROOT/calls"; false; }
  ! grep -qE '^status( |$)' "$TEST_ROOT/calls" || { cat "$TEST_ROOT/calls"; false; }
}

@test "R198: the context names the project with the words of vbw status's first line" {
  local head
  head=$("$VBW" status < /dev/null | head -n 1)
  run session_start
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(context "$output")" == "VBW project ($head). Next: "* ]] || { context "$output"; echo "want: VBW project ($head)"; false; }
}

@test "R198: a glance older than the record gives the record's milestone, not the glance's" {
  "$VBW" status > /dev/null
  "$VBW" milestone rename "Checkout" > /dev/null
  # The glance now lags the record (a write that did not refresh it).
  jq '.milestone.title = "stale title"' .vbw/runtime/glance.json > "$TEST_ROOT/g" && cat "$TEST_ROOT/g" > .vbw/runtime/glance.json
  touch -t 200001010000 .vbw/runtime/glance.json
  run session_start
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(context "$output")" == *"Checkout"* ]] || { context "$output"; false; }
  [[ "$(context "$output")" != *"stale title"* ]] || { context "$output"; false; }
}

@test "R198: a record written by a newer VBW still gives the update notice, without vbw status" {
  jq '.schema = 99' .vbw/record.json > "$TEST_ROOT/r" && cat "$TEST_ROOT/r" > .vbw/record.json
  run session_start
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(context "$output")" == "this project needs a newer VBW"* ]] || { context "$output"; false; }
  printf '%s' "$output" | jq -e '.systemMessage | contains("/vbw:update")' > /dev/null || { echo "$output"; false; }
  ! grep -qE '^status( |$)' "$TEST_ROOT/calls" || { cat "$TEST_ROOT/calls"; false; }
}

@test "R198: docs/guards.md says the hook runs vbw next once and reads the project line from the glance" {
  local s
  s=$(awk '/^## SessionStart/ { on = 1; next } /^## / { on = 0 } on' "$REPO_ROOT/docs/guards.md" | tr '\n' ' ')
  [[ "$s" == *"runs \`vbw next\` once"* ]] || { echo "$s"; false; }
  [[ "$s" == *"glance"* ]] || { echo "$s"; false; }
  [[ "$s" == *"never \`vbw status\`"* ]] || { echo "$s"; false; }
}
