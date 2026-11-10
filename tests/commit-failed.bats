#!/usr/bin/env bats
# R287 (field report 2026-11-09, D685, D687): a record commit that fails is a step of
# its own, never only a warning. When VBW cannot commit its files (here the project's
# pre-commit hook refuses them), record_commit keeps the failure in
# .vbw/runtime/commit-failed.json (the hook's reason, the files, the time; the full text
# in .vbw/runtime/output/commit-failed.log), and while it stands vbw next's step is that
# failure, before any other step: the hook's own message, shortened when long, and the
# three ways on. No approval is asked meanwhile: vbw approve refuses with the same
# reason. Once VBW's files are committed (by the user, or by vbw next's retry once the
# hook lets them pass) the step is gone. VBW never passes --no-verify and never offers
# to skip the hook. vbw doctor names a failed record commit while it stands. L1: a
# project whose pre-commit hook exits 1 with a message.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(vbw): plan"
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
  HOOK="$(git rev-parse --git-path hooks)/pre-commit"
  mkdir -p "$(dirname "$HOOK")"
  export HOOK_LOG="$TEST_ROOT/hook.log"
  : > "$HOOK_LOG"
  hook_refuses 'secrets: 5 problem(s) in the staged changes'
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# hook_refuses MESSAGE [LINES]: the project's pre-commit hook prints MESSAGE (and LINES more
# numbered lines) on its error output and exits 1; each run is logged with its arguments.
hook_refuses() {
  printf '#!/bin/sh\necho "ran $*" >> "$HOOK_LOG"\necho "%s" >&2\ni=0; while [ "$i" -lt %d ]; do i=$((i + 1)); echo "finding line $i" >&2; done\nexit 1\n' "$1" "${2:-0}" > "$HOOK"
  chmod +x "$HOOK"
}
hook_passes() { printf '#!/bin/sh\necho "ran $*" >> "$HOOK_LOG"\nexit 0\n' > "$HOOK"; chmod +x "$HOOK"; }

# run_close: a planning run of session s1 opens and closes; its close commits the record.
run_close() {
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  VBW_SESSION_ID=s1 run "$VBW" run end < /dev/null
}

next_json() { VBW_SESSION_ID=s1 "$VBW" next --json < /dev/null; }
approvals() { jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' .vbw/record.json; }

@test "R287 step: after a run close the hook refused, the failure is kept in the runtime folder with the hook's reason, the files and the time" {
  run_close
  [ -s "$HOOK_LOG" ] || { echo "the hook never ran"; false; }
  [ -f .vbw/runtime/commit-failed.json ] || { echo "no .vbw/runtime/commit-failed.json: $output"; ls .vbw/runtime; false; }
  jq -e '(.reason | contains("secrets: 5 problem(s) in the staged changes"))
    and (.files | index(".vbw/record.json") != null)
    and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' .vbw/runtime/commit-failed.json \
    || { cat .vbw/runtime/commit-failed.json; false; }
}

@test "R287 step: while the failure stands vbw next's step is it, before the approval: the hook's own message and the three ways on" {
  run_close
  local n
  n=$(next_json)
  printf '%s' "$n" | jq -e '.action == "commit" and .gate == true' > /dev/null || { echo "$n"; false; }
  printf '%s' "$n" | jq -e '.instruction
    | contains("could not be committed") and contains("secrets: 5 problem(s) in the staged changes")
    and contains("fix what the hook flagged") and contains("allow it in the checker") and contains("commit the VBW files yourself")
    and contains("run vbw next again")' > /dev/null || { printf '%s' "$n" | jq -r .instruction; false; }
  printf '%s' "$n" | jq -e '.instruction | (contains("--no-verify") or test("skip"; "i")) | not' > /dev/null || { printf '%s' "$n" | jq -r .instruction; false; }
}

@test "R287 step: a long hook message is shortened in the step, which names where the full text is kept" {
  hook_refuses 'secrets: 200 problem(s) in the staged changes' 200
  run_close
  local n
  n=$(next_json)
  printf '%s' "$n" | jq -e '.action == "commit" and (.instruction | contains("secrets: 200 problem(s)") and contains(".vbw/runtime/output/commit-failed.log") and (contains("finding line 150") | not))' > /dev/null \
    || { printf '%s' "$n" | jq -r .instruction; false; }
  grep -qx 'finding line 150' .vbw/runtime/output/commit-failed.log || { echo "the full text is not kept"; false; }
}

@test "R287 approve: while the failure stands no approval is asked and vbw approve refuses with the same reason, recording nothing" {
  run_close
  local before
  before=$(approvals)
  next_json | jq -e '.action != "approve"' > /dev/null
  VBW_SESSION_ID=s1 run "$VBW" approve < /dev/null
  [ "$status" -ne 0 ] || { echo "approve went through: $output"; false; }
  [[ "$output" == *"could not be committed"* && "$output" == *"secrets: 5 problem(s) in the staged changes"* ]] || { echo "$output"; false; }
  [ "$(approvals)" = "$before" ]
}

@test "R287 clears: once the user commits VBW's files themselves, the step is gone and vbw next continues from where it stopped" {
  run_close
  next_json | jq -e '.action == "commit"' > /dev/null
  hook_passes
  git add .vbw && git commit -q -m "chore: commit VBW files by hand"
  next_json | jq -e '.action == "approve"' > /dev/null || { next_json; false; }
  [ ! -f .vbw/runtime/commit-failed.json ] || { echo "the failure is still kept"; false; }
}

@test "R287 clears: once the hook lets the files pass, the next vbw next commits them through the hook and continues" {
  run_close
  hook_passes
  : > "$HOOK_LOG"
  next_json | jq -e '.action == "approve"' > /dev/null || { next_json; false; }
  [ -s "$HOOK_LOG" ] || { echo "the retry did not run the project's hook"; false; }
  [ -z "$(git status --porcelain -- .vbw/record.json)" ] || { echo "the record is still uncommitted"; git status --short; false; }
  [ ! -f .vbw/runtime/commit-failed.json ]
}

@test "R287 hooks: VBW never passes --no-verify or skips the project's hooks" {
  ! grep -rnE -- '--no-verify|git[^|;]* commit[^|;]* -n( |$)' "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/bin" || false
}

@test "R287 doctor: vbw doctor names a standing failed record commit with its time and the hook's reason, and says nothing of it when none stands" {
  vbw_run doctor
  [[ "$output" != *"could not be committed"* ]] || { echo "$output"; false; }
  run_close
  vbw_run doctor
  printf '%s\n' "$output" | grep -E "could not be committed" | grep -E '[0-9]{2}:[0-9]{2}' | grep -qF 'secrets: 5 problem(s) in the staged changes' \
    || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'could not be committed')" = 1 ] || { echo "$output"; false; }
}

@test "R287 router: the router's commit step shows the kernel's instruction and never the approval menu" {
  local s="$PLUGIN_ROOT/skills/vibe/SKILL.md" step
  step=$(grep -E '^\*\*commit\*\* \(needs user\)' "$s") || { echo "no **commit** (needs user) step in $s"; false; }
  [[ "$step" == *"instruction"* && "$step" == *"never the approval menu"* ]] || { echo "$step"; false; }
}
