#!/usr/bin/env bats
# R194 (T124, T165; docs/proof.md, docs/workflows.md): vbw commit --fix FIX
# MESSAGE FILE... for an open requirement fix of any source (QA-opened, or
# opened by vbw prove for a failing check) commits the named changed check files
# of the fix's requirement with both trailers, VBW-Fix and VBW-Req. The message
# is validated as today; the commit touches only the named changed files and
# leaves the user's staged work staged. Refused, committing nothing: a check file
# of another requirement (named), a code file (commit it through its plan), a
# path under .vbw/ or outside the project, an unknown or non-open fix, a file
# that did not change, and a fix of a [human] requirement, which has no check
# files. A project-command fix keeps today's behaviour. After such a commit the
# file waits for one approval: vbw fix done names it, vbw next asks once naming
# it, vbw prove refuses until then and runs it after; the commit shows under its
# requirement and the proof's scope check blames no plan. The Dev's instructions
# say so. L1: the kernel on a fixture project.

load helper
load fix-helper
load fixture-helper

# R1 (pay) and R2 (refund) [auto], R3 [human]; P1.1 writes src/pay.txt and
# src/refund.txt, P1.2 src/ui.txt; C1 (R1) runs tests/c1.sh, C2 (R2) tests/c2.sh.
# Built and proved, then the user breaks the payment: the proof opens F_PROVE for R1
# (fix_project shop, built once per file).
setup_file() { fixture_build shop fix_project shop; }
setup() { fixture_copy shop; }

teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
stricter_c1() { printf 'grep -qx paid src/pay.txt && test -s src/pay.txt\n' > tests/c1.sh; }
trailer() { git log -1 --format="%(trailers:key=$1,valueonly)" | tr -d '\n'; }
# refused ARGS...: vbw commit --fix ARGS fails and HEAD does not move.
refused() {
  local before
  before=$(git rev-parse HEAD)
  run "$VBW" commit --fix "$@" < /dev/null
  [ "$status" -ne 0 ] || { echo "committed: $output"; return 1; }
  [ "$(git rev-parse HEAD)" = "$before" ] || { echo "HEAD moved: $output"; return 1; }
}

@test "R194: a proof-opened requirement fix commits its requirement's changed check file with VBW-Fix and VBW-Req, touching only it; staged work stays staged" {
  stricter_c1
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  printf 'mine\n' >> src/staged.txt
  git add src/staged.txt
  run "$VBW" commit --fix "$F_PROVE" "test(pay): stricter" tests/c1.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *committed*"$F_PROVE"* ]] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = tests/c1.sh ]
  [ "$(trailer VBW-Fix)" = "$F_PROVE" ]
  [ "$(trailer VBW-Req)" = R1 ]
  git log -1 --format=%s | grep -q '^test(pay): stricter$'
  [ "$(git diff --cached --name-only)" = src/staged.txt ]
  [ -n "$(git status --porcelain -- tests/c2.sh)" ]
}

@test "R194: the message is validated as today" {
  stricter_c1
  refused "$F_PROVE" "stricter" tests/c1.sh
}

@test "R194: a check file of another requirement is refused, naming that requirement; a code file is refused, pointing to the plan" {
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  refused "$F_PROVE" "test(refund): stricter" tests/c2.sh
  [[ "$output" == *R2* ]] || { echo "$output"; false; }
  printf 'paid\n' > src/pay.txt
  refused "$F_PROVE" "fix(pay): pay" src/pay.txt
  [[ "$output" == *"vbw commit PLAN"* ]] || { echo "$output"; false; }
}

@test "R194: a path under .vbw/ or outside the project, an unknown fix, a non-open fix and an unchanged file are refused" {
  stricter_c1
  refused "$F_PROVE" "test(pay): record" .vbw/record.json
  printf 'x\n' > "$TEST_ROOT/outside.txt"
  refused "$F_PROVE" "test(pay): outside" "../outside.txt"
  refused F99 "test(pay): unknown" tests/c1.sh
  [[ "$output" == *F99* ]] || { echo "$output"; false; }
  edit_record '.fixes += [{id: "F90", req: "R1", attempts: 0, status: "fixed", note: "x"}]'
  refused F90 "test(pay): closed" tests/c1.sh
  [[ "$output" == *F90* ]] || { echo "$output"; false; }
  git checkout -q -- tests/c1.sh
  refused "$F_PROVE" "test(pay): unchanged" tests/c1.sh
  [[ "$output" == *"nothing to commit"* ]] || { echo "$output"; false; }
}

@test "R194: a fix of a [human] requirement has no check files to commit and is refused the same way" {
  edit_record '.fixes += [{id: "F91", req: "R3", attempts: 0, status: "open", note: "feels unsafe"}]'
  stricter_c1
  refused F91 "test(pay): stricter" tests/c1.sh
  [[ "$output" == *"check file"* ]] || { echo "$output"; false; }
}

@test "R194: a project-command fix keeps today's behaviour, and a QA fix's check file commits as today, with both trailers" {
  edit_record '.commands = {test: ["true"]} | .fixes += [{id: "F92", command: "test", attempts: 0, status: "open", note: "t"}]'
  printf 'tool\n' > src/tool.txt
  run "$VBW" commit --fix F92 "fix(test): tool" src/tool.txt < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = src/tool.txt ]
  [ "$(trailer VBW-Fix)" = F92 ]
  "$VBW" qa finding R2 "a refund of zero is written" > /dev/null
  local qa
  qa=$(jq -r '[.fixes[] | select(.source == "qa")][-1].id' .vbw/record.json)
  printf 'test -s src/refund.txt\n' > tests/c2.sh
  run "$VBW" commit --fix "$qa" "test(refund): stricter" tests/c2.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = tests/c2.sh ]
  [ "$(trailer VBW-Fix)" = "$qa" ]
  [ "$(trailer VBW-Req)" = R2 ]
}

@test "R194: after the commit, fix done names the file as waiting, next asks the approval naming it, prove refuses until then and runs it after; the commit shows under its requirement, scope ok" {
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "fix(pay): pay again" > /dev/null
  stricter_c1
  "$VBW" commit --fix "$F_PROVE" "test(pay): stricter" tests/c1.sh > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  run "$VBW" fix done "$F_PROVE" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"waiting for approval"*"tests/c1.sh"* ]] || { echo "$output"; false; }
  [[ "$output" == *"$F_PROVE fixed"* ]] || { echo "$output"; false; }
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "approve" and .gate == true and .detail.files == ["tests/c1.sh"]' || { echo "$output"; false; }
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"tests/c1.sh"* ]] || { echo "$output"; false; }
  "$VBW" approve > /dev/null
  run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass" and (.evidence.checks.C1.reused | not) and .evidence.scope == []' .vbw/record.json
  run "$VBW" show req R1 < /dev/null
  [[ "$output" == *"test(pay): stricter"* ]] || { echo "$output"; false; }
}

@test "R194: the Dev's instructions and the fixing workflow say a requirement fix commits its own requirement's check files with vbw commit --fix, code through the plan, waiting for one approval" {
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/agents/dev.md" | grep -qi 'check file' || { echo "dev.md: no line with vbw commit --fix and check file"; false; }
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/agents/dev.md" | grep -qi 'approval' || { echo "dev.md: no line with vbw commit --fix and approval"; false; }
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/workflows/fixing.js" | grep -qi 'check file' || { echo "fixing.js: no line with vbw commit --fix and check file"; false; }
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/workflows/fixing.js" | grep -qi 'approval' || { echo "fixing.js: no line with vbw commit --fix and approval"; false; }
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/workflows/fixing.js" | grep -qF 'vbw commit PLAN' || { echo "fixing.js: code does not go through vbw commit PLAN"; false; }
  grep -F 'vbw commit --fix' "$PLUGIN_ROOT/agents/dev.md" | grep -qF 'vbw commit PLAN' || { echo "dev.md: code does not go through vbw commit PLAN"; false; }
}

@test "R194: a project-command fix still refuses a path under .vbw/ or reaching outside its folder, committing nothing" {
  edit_record '.commands = {test: ["true"]} | .fixes += [{id: "F93", command: "test", attempts: 0, status: "open", note: "t"}]'
  printf 'tool\n' > src/tool.txt
  printf 'more\n' >> .vbw/spec.md
  git add -f .vbw/spec.md
  refused F93 "fix(test): spec" .vbw/spec.md
  [[ "$output" == *".vbw/"* ]] || { echo "$output"; false; }
  refused F93 "fix(test): detour" src/../src/tool.txt
  [[ "$output" == *"outside the project"* ]] || { echo "$output"; false; }
}
