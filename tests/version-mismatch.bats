#!/usr/bin/env bats
# R272: a project opened with an older VBW than the one that wrote its record is
# told so in plain words, both versions named. Every kernel write of the record
# also writes .vbw/runtime/writer.json ({version, schema}: the writing VBW's
# version and the record's schema). An older VBW refuses with exit 4 and one
# line naming the version that wrote the record and the version this session
# loaded, saying how to update and what --plugin-dir means ('Claude Code loads
# VBW from that folder instead of the installed copy'); without a writer file
# it names the schema numbers and the loaded version. The session-start hook
# puts that same line in its context and its notice; the router (SKILL.md)
# says the line and stops at every step that asks the kernel, never a typed
# approve command. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
teardown() { vbw_teardown; }

WRITER='.vbw/runtime/writer.json'
PLUGIN_DIR_WORDS='--plugin-dir: Claude Code loads VBW from that folder instead of the installed copy'

# version: the version of this plugin, as plugin.json states it.
version() { jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json"; }

# older: a copy of this VBW at version 2.0.30 that reads up to schema 3.
older() {
  rm -rf "$TEST_ROOT/older"
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/older"
  sed 's/^VBW_SCHEMA_MAX=.*/VBW_SCHEMA_MAX=3/' "$PLUGIN_ROOT/lib/record.sh" > "$TEST_ROOT/older/lib/record.sh"
  grep -qx 'VBW_SCHEMA_MAX=3' "$TEST_ROOT/older/lib/record.sh"
  jq '.version = "2.0.30"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" > "$TEST_ROOT/older/.claude-plugin/plugin.json"
  OLDER="$TEST_ROOT/older/bin/vbw"
}

# session_start PLUGIN: the SessionStart hook of the plugin copy at PLUGIN, in the project.
session_start() {
  jq -nc --arg d "$PROJECT" '{hook_event_name: "SessionStart", source: "startup", cwd: $d}' | PLUGIN_ROOT="$1" HOOK_PROJECT_DIR="$PROJECT" vbw_hook SessionStart
}

@test "R272 kernel: every kernel write of the record writes the writer file beside it: this VBW's version and the record's schema" {
  jq -e --arg v "$(version)" '.version == $v and .schema == (input | .schema)' "$WRITER" .vbw/record.json || { cat "$WRITER" 2> /dev/null; false; }
  rm -f "$WRITER"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -e --arg v "$(version)" '.version == $v and .schema == (input | .schema)' "$WRITER" .vbw/record.json || { cat "$WRITER" 2> /dev/null; false; }
  rm -f "$WRITER"
  "$VBW" decide "a decision" > /dev/null
  jq -e --arg v "$(version)" '.version == $v and .schema == (input | .schema)' "$WRITER" .vbw/record.json || { cat "$WRITER" 2> /dev/null; false; }
}

@test "R272 kernel: an older VBW refuses (exit 4) naming the version that wrote the record and the version it loaded, how to update, and what --plugin-dir means" {
  older
  local want cmd
  want="vbw: this project needs a newer VBW: its record was written by VBW $(version), and this session loaded VBW 2.0.30. Update VBW (/vbw:update), then restart Claude Code; for a development checkout start Claude Code with --plugin-dir <checkout>/plugin ($PLUGIN_DIR_WORDS)"
  for cmd in "status" "next" "show roadmap" "decide x" "prove"; do
    # shellcheck disable=SC2086 # the command words split on purpose
    run "$OLDER" $cmd < /dev/null
    [ "$status" -eq 4 ] || { echo "older vbw $cmd exited $status: $output"; false; }
    [ "$output" = "$want" ] || { printf 'older vbw %s said:\n  %s\nwanted:\n  %s\n' "$cmd" "$output" "$want"; false; }
  done
  [ ! -f "$TEST_ROOT/older/.vbw/record.json" ]
}

@test "R272 kernel: without a writer file (a record written before it existed) the refusal names the schema numbers and the loaded version, in the same shape" {
  older
  rm -f "$WRITER"
  local want schema
  schema=$(jq -r '.schema' .vbw/record.json)
  want="vbw: this project needs a newer VBW: its record was written with schema $schema, and this session loaded VBW 2.0.30, which reads up to schema 3. Update VBW (/vbw:update), then restart Claude Code; for a development checkout start Claude Code with --plugin-dir <checkout>/plugin ($PLUGIN_DIR_WORDS)"
  run "$OLDER" status < /dev/null
  [ "$status" -eq 4 ] || { echo "older vbw status exited $status: $output"; false; }
  [ "$output" = "$want" ] || { printf 'older vbw status said:\n  %s\nwanted:\n  %s\n' "$output" "$want"; false; }
}

@test "R272 hooks: the session-start hook of the older VBW gives the kernel's line, both versions named, in its context and in its notice to the user" {
  older
  run session_start "$TEST_ROOT/older"
  [ "$status" -eq 0 ]
  local ctx msg line
  line="this project needs a newer VBW: its record was written by VBW $(version), and this session loaded VBW 2.0.30"
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  msg=$(printf '%s' "$output" | jq -r '.systemMessage')
  [[ "$ctx" == *"$line"* && "$ctx" == *"$PLUGIN_DIR_WORDS"* ]] || { echo "context: $ctx"; false; }
  [[ "$ctx" != *"Continue with /vbw:vibe"* ]] || { echo "context: $ctx"; false; }
  [[ "$msg" == *"$line"* && "$msg" == *"/vbw:update"* ]] || { echo "notice: $msg"; false; }
}

@test "R272 router: the router says the kernel's line and stops at every step that asks the kernel, and never asks the user to type an approve command" {
  local skill="$PLUGIN_ROOT/skills/vibe/SKILL.md"
  grep -q 'needs a newer VBW' "$skill" || { echo "SKILL.md does not name the newer-VBW refusal"; false; }
  grep -qE 'exit (code )?4' "$skill" || { echo "SKILL.md does not name exit 4"; false; }
  grep -q 'say its line and stop\|say that line and stop\|say the line and stop' "$skill" || { echo "SKILL.md does not tell the session to say the line and stop"; false; }
  grep -q 'never ask the user to type /vbw:approve' "$skill" || { echo "SKILL.md no longer forbids the typed approve command"; false; }
  ! grep -qE 'tell the user to (type|run) (/vbw:approve|vbw approve)' "$skill" || { echo "SKILL.md tells the user to type an approve command"; false; }
}
