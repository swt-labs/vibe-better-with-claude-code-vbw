#!/usr/bin/env bats
# R289 (field report 2026-11-09, D685; docs/guards.md): the guard protects the record of
# the project the session works in by its resolved path. A write target (a redirect, the
# destination of cp, mv, tee and the like, a Write or Edit tool path) is resolved against
# the command's working folder (project_path, common.jq), and only the session project's
# own .vbw/record.json is refused as a record write. A .vbw/record.json in another folder
# (a throwaway repository in the session's scratchpad, a VBW project or not, or one under
# the project's own scratch folder) is not refused with '.vbw/record.json is written only
# by vbw'. L1: the hooks.json commands of the main session, as Claude Code runs them.

load helper
load fixture-helper

built() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src
  git add -A && git commit -q -m "chore(vbw): init"
}
setup_file() { fixture_build built built; }
setup() {
  fixture_copy built
  # A throwaway VBW project in the session's scratchpad, and a plain folder holding a record file.
  SCRATCH="$TEST_ROOT/scratchpad"
  mkdir -p "$SCRATCH/repo" "$SCRATCH/plain/.vbw"
  (cd "$SCRATCH/repo" && git init -q && "$VBW" init > /dev/null)
  printf '{}\n' > "$SCRATCH/plain/.vbw/record.json"
  mkdir -p .vbw/runtime/scratch/repo/.vbw
  printf '{}\n' > "$TEST_ROOT/in.json"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

RECORD_REASON='.vbw/record.json is written only by vbw'

# bash_at DIR COMMAND / file_at DIR TOOL PATH: the main session's call from working folder DIR.
bash_at() {
  jq -nc --arg d "$1" --arg c "$2" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash
}
file_at() {
  jq -nc --arg d "$1" --arg t "$2" --arg p "$3" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, cwd: $d, tool_input: {file_path: $p, content: "{}", old_string: "a", new_string: "b"}}' \
    | vbw_hook PreToolUse "$2"
}
reason_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2> /dev/null; }
# not_record OUT WHAT / record_refused OUT WHAT
not_record() { [[ "$(reason_of "$1")" != *"$RECORD_REASON"* ]] || { echo "$2 was refused as a record write: $1"; return 1; }; }
record_refused() {
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null 2>&1 && [[ "$(reason_of "$1")" == *"$RECORD_REASON"* ]] \
    || { echo "$2 was not refused as a record write: $1"; return 1; }
}

@test "R289 elsewhere: a write to the record file of a throwaway repository in the scratchpad, a VBW project or not, is not refused as a record write, by any writer" {
  local t c out
  for t in "$SCRATCH/repo/.vbw/record.json" "$SCRATCH/plain/.vbw/record.json"; do
    for c in "echo x > '$t'" "cp '$TEST_ROOT/in.json' '$t'" "mv '$TEST_ROOT/in.json' '$t'" "tee '$t' < '$TEST_ROOT/in.json'" "jq . '$TEST_ROOT/in.json' > '$t'"; do
      out=$(bash_at "$PROJECT" "$c")
      not_record "$out" "$c"
    done
    out=$(bash_at "$SCRATCH/repo" "cd '$(dirname "$(dirname "$t")")' && echo x > .vbw/record.json")
    not_record "$out" "a cd into $(dirname "$(dirname "$t")")"
    for c in Write Edit; do
      out=$(file_at "$PROJECT" "$c" "$t")
      not_record "$out" "$c $t"
    done
  done
}

@test "R289 elsewhere: a record file in a repository under the project's own scratch folder is not the project's record" {
  local out
  out=$(bash_at "$PROJECT" "echo x > .vbw/runtime/scratch/repo/.vbw/record.json")
  not_record "$out" "the scratch folder's repository"
  out=$(file_at "$PROJECT" Write "$PROJECT/.vbw/runtime/scratch/repo/.vbw/record.json")
  not_record "$out" "Write into the scratch folder's repository"
}

@test "R289 own: the project's record is still refused however it is named: relative, ./, absolute, through sub/.., after a cd into the project and from a subfolder" {
  local c out
  for c in "echo x > .vbw/record.json" "echo x > ./.vbw/record.json" "echo x > '$PROJECT/.vbw/record.json'" "echo x > src/../.vbw/record.json" \
    "cp '$TEST_ROOT/in.json' .vbw/record.json" "tee .vbw/record.json < '$TEST_ROOT/in.json'"; do
    out=$(bash_at "$PROJECT" "$c")
    record_refused "$out" "$c"
  done
  out=$(bash_at "$SCRATCH/plain" "cd '$PROJECT' && echo x > .vbw/record.json")
  record_refused "$out" "a cd into the project"
  out=$(bash_at "$PROJECT/src" "echo x > ../.vbw/record.json")
  record_refused "$out" "../.vbw/record.json from src"
  for c in Write Edit; do
    out=$(file_at "$PROJECT" "$c" "$PROJECT/.vbw/record.json")
    record_refused "$out" "$c of the absolute path"
    out=$(file_at "$PROJECT/src" "$c" "../.vbw/record.json")
    record_refused "$out" "$c of ../.vbw/record.json from src"
  done
}
