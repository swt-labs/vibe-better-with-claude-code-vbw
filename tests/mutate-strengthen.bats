#!/usr/bin/env bats
# R188 (P140; docs/proof.md, docs/guards.md), R210 (T192) and R217: a test that
# cannot fail is strengthened in place during the build, and waits for one approval.
# Once vbw mutate records a survivor in a build run, the check files a plan may
# strengthen open for the run's agents: the files of the checks named by the
# plan's own rules, a file shared with another requirement's check included; every
# other check file stays protected. The kernel holds one definition of those files
# (strengthen_files, in the shared jq defs of plugin/lib/record.sh, beside
# own_rules); its cases below pin each reader:
#   - the file guard: before a survivor a build agent cannot write a check file,
#     after it the plan's files open and another requirement's own file stays denied;
#   - vbw commit PLAN: commits such a file with the plan's trailers, and refuses
#     one with no survivor or outside the plan's own rules, by name, with a next step;
#   - the lease's editable list: lease.editable holds exactly those files;
#   - the proof's scope check: does not count that commit as outside the plan;
#   - vbw mutate's pending and strengthened lists: drawn from strengthen_files
#     only (a shared file inside it is pending and strengthened; a check file
#     outside it, or any file before the plan's first survivor, is neither).
# The changed check file lets the build finish, then vbw next asks for one
# approval naming it before the proof, and vbw prove refuses until it is given;
# vbw show contract --changes prints the whole diff under the changed test file
# line. L1: the kernel and the hooks on a fixture project.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo receipt\n' > src/receipt.sh
  # tests/shared.sh serves C1 and C2; it is long enough for a two-hunk edit.
  printf '# shared helper: both checks call it\ntrue\n# a\n# b\n# c\n# d\n# e\n# f\n# g\ntrue\n' > tests/shared.sh
  # C1 cannot fail on what is printed.
  printf 'sh src/pay.sh > /dev/null && sh tests/shared.sh\n' > tests/pay.sh
  printf '[ "$(sh src/receipt.sh)" = receipt ] && sh tests/shared.sh\n' > tests/receipt.sh
  # C3 checks R1 too, is named by no rule (so strengthen_files never lists it) and cannot fail on what is printed.
  printf 'sh src/pay.sh > /dev/null\n' > tests/pay-extra.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"},
                    {id: "P2", title: "Receipt", reqs: ["R2"], goal: "g", criteria: ["c"]}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh", "tests/shared.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh", "tests/shared.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/pay-extra.sh"], files: ["tests/pay-extra.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R2", text: "a receipt is printed", check: "C2"}]}' | "$VBW" apply > /dev/null
  # P2 asks for no mutation check (express), so only P1's break is in play.
  jq '(.phases[] | select(.id == "P2")).tier = "express"' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P2.1 > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# file_in TOOL PATH: a build agent's file tool call in session s1.
file_in() {
  jq -nc --arg t "$1" --arg p "$2" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, cwd: env.PROJECT,
    tool_input: {file_path: $p, content: "x", old_string: "a", new_string: "b"}, agent_id: "x1", agent_type: "workflow-subagent"}'
}
# answer TOOL PATH: the file guard's answer to that call, in ANSWER.
answer() { ANSWER=$(file_in "$1" "$2" | vbw_hook PreToolUse "$1"); }
denied() { [[ "$ANSWER" == *'"deny"'* ]] || { echo "not denied: $ANSWER"; return 1; }; }
allowed() { [ -z "$ANSWER" ] || { echo "not allowed: $ANSWER"; return 1; }; }

# survivor: a break of src/pay.sh C1 cannot notice, recorded as a survivor of R1.1.
survivor() {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "no survivor: $output"; return 1; }
}
# strengthen_own: C1's own file checks what is printed.
strengthen_own() { printf '[ "$(sh src/pay.sh)" = paid ] && sh tests/shared.sh\n' > tests/pay.sh; }
# strengthen_shared: the shared file (C1's and C2's) checks what pay.sh prints, on line 2;
# the file has no set -e and ends with true, so the line exits the script itself.
strengthen_shared() { sed -i.bak '2s/^true$/[ "$(sh src\/pay.sh)" = paid ] || exit 1/' tests/shared.sh && rm -f tests/shared.sh.bak; }
# last_break: the last break recorded under P1.1.
last_break() { jq -c '[.plans[] | select(.id == "P1.1") | .mutations // [] | .[]] | last' .vbw/record.json; }

@test "R210: one definition of the files a plan may strengthen lives in record.sh's shared jq defs, beside own_rules; cmd-commit.sh holds no second one" {
  local defs
  defs=$(grep -l -E 'def (survivor_files|strengthen_files)\(' "$PLUGIN_ROOT"/lib/*.sh "$PLUGIN_ROOT"/lib/*.jq "$PLUGIN_ROOT"/hooks/*.jq 2> /dev/null || true)
  [ "$defs" = "$PLUGIN_ROOT/lib/record.sh" ] || { echo "the definition is in: ${defs:-nowhere}"; false; }
  ! grep -q 'COMMIT_SURVIVOR_DEFS' "$PLUGIN_ROOT/lib/cmd-commit.sh" || { echo "cmd-commit.sh still holds COMMIT_SURVIVOR_DEFS"; false; }
  grep -q 'own_rules' <(sed -n -E '/def (survivor_files|strengthen_files)\(/,/;$/p' "$PLUGIN_ROOT/lib/record.sh") \
    || { echo "the definition does not read own_rules"; false; }
}

@test "R188 R210: before a survivor a build agent cannot write a check file; after it, the files of the plan's own rules' checks open, the file shared with another requirement included; another requirement's own file stays protected" {
  answer Write tests/pay.sh
  denied
  answer Write tests/shared.sh
  denied
  survivor
  answer Write tests/pay.sh
  allowed
  answer Edit tests/pay.sh
  allowed
  # Shared with R2's check: C1 names it, so it opens.
  answer Write tests/shared.sh
  allowed
  # R2's own: still protected.
  answer Edit tests/receipt.sh
  denied
  jq -e '.lease.editable | sort == ["tests/pay.sh", "tests/shared.sh"]' .vbw/record.json || { jq '.lease' .vbw/record.json; false; }
}

@test "R188 R210: vbw commit PLAN commits a check file of the plan's own rules' checks after a survivor, shared or not, with the plan's trailers; a file only other requirements' checks name is refused by name, with the rule and a next step" {
  strengthen_shared
  run "$VBW" commit P1.1 "test(pay): check what is printed" tests/shared.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "committed with no survivor: $output"; false; }
  git checkout -q -- tests/shared.sh
  survivor
  strengthen_shared
  run "$VBW" commit P1.1 "test(pay): check what is printed" tests/shared.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git show --name-only --format= HEAD)" = tests/shared.sh ]
  git log -1 --format='%(trailers:key=VBW-Plan,valueonly)' | grep -qx P1.1
  git log -1 --format='%(trailers:key=VBW-Req,valueonly)' | grep -qx R1
  strengthen_own
  run "$VBW" commit P1.1 "test(pay): own file too" tests/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '[ "$(sh src/receipt.sh)" = receipt ]\n' > tests/receipt.sh
  run "$VBW" commit P1.1 "test(pay): not mine" tests/receipt.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"tests/receipt.sh"* && "$output" == *"own rules"* ]] || { echo "$output"; false; }
  [[ "$output" != *"no other requirement's check file is the plan's to commit"* ]] || { echo "the old rule is still worded: $output"; false; }
  [[ "$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)" == "Next: "?* ]] || { echo "no next step: $output"; false; }
}

@test "R188 R210 R217: a strengthened shared check file lets the build finish; the same break is caught by the pending file; one approval is asked before the proof, which refuses until then; the scope check counts the commit as the plan's" {
  survivor
  strengthen_shared
  "$VBW" commit P1.1 "test(pay): check what is printed" tests/shared.sh > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 survives the approved check; caught by the pending one: tests/shared.sh"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the pending file still needs the one approval before the proof"* ]] || { echo "$output"; false; }
  last_break | jq -e '.result == "red" and .pending == ["tests/shared.sh"] and .strengthened == ["tests/shared.sh"]' || { last_break; false; }
  git checkout -q -- src/pay.sh
  "$VBW" plan done P1.1 > /dev/null
  printf 'echo receipt\n# thanks\n' > src/receipt.sh
  "$VBW" commit P2.1 "feat(receipt): thanks" > /dev/null
  "$VBW" plan done P2.1 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "approve" and .gate == true and .detail.files == ["tests/shared.sh"]' || { echo "$output"; false; }
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *tests/shared.sh* ]] || { echo "$output"; false; }
  "$VBW" approve > /dev/null
  run "$VBW" prove < /dev/null
  jq -e '.evidence.scope == []' .vbw/record.json || { echo "$output"; jq '.evidence.scope' .vbw/record.json; false; }
}

@test "R188: in a build run a check file changed and not committed refuses the break, naming it, nothing written (commit it first)" {
  survivor
  strengthen_own
  local sum
  sum=$(cksum < .vbw/record.json)
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *tests/pay.sh* && "$output" == *"commit them first"* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$sum" ]
}

@test "R217: before any survivor of the plan nothing is pending: a strengthened check file committed with git waits for approval, the break prints the plain red line and records no pending" {
  strengthen_own
  run "$VBW" commit P1.1 "test(pay): check what is printed" tests/pay.sh < /dev/null
  [ "$status" -ne 0 ] || { echo "vbw commit took it with no survivor: $output"; false; }
  git add tests/pay.sh && git commit -q -m "test(pay): check what is printed"
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^R1\.1 red: prints unpaid instead of paid$' || { echo "$output"; false; }
  [[ "$output" != *"caught by"* && "$output" != *survives* && "$output" != *strengthened:* ]] || { echo "$output"; false; }
  last_break | jq -e '.result == "red" and (has("pending") | not) and (has("strengthened") | not)' || { last_break; false; }
}

@test "R217: a check file outside strengthen_files that the break ran, edited and waiting for approval, is neither pending nor strengthened: the plain red line" {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --check C3 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "no survivor: $output"; false; }
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay-extra.sh
  git add tests/pay-extra.sh && git commit -q -m "test(pay): extra check"
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --check C3 "prints unpaid instead of paid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^task1 red: prints unpaid instead of paid$' || { echo "$output"; false; }
  [[ "$output" != *"caught by"* && "$output" != *survives* && "$output" != *strengthened:* ]] || { echo "$output"; false; }
  last_break | jq -e '.result == "red" and (has("pending") | not) and (has("strengthened") | not)' || { last_break; false; }
}

@test "R217: this file's header names each reader of strengthen_files, and a case in the file covers each" {
  local head
  head=$(sed -n '1,/^load /p' "$BATS_TEST_FILENAME")
  local reader pat
  for reader in "vbw commit:vbw commit PLAN" "the lease's editable list:lease.editable" "the file guard:answer Write" "the proof's scope check:evidence.scope" "vbw mutate's pending and strengthened lists:pending == "; do
    [[ "$head" == *"${reader%%:*}"* ]] || { echo "the header does not name: ${reader%%:*}"; false; }
    pat=${reader#*:}
    grep '^@test\|^  ' "$BATS_TEST_FILENAME" | grep -v '^[[:space:]]*local \|reader=' | grep -qF -- "$pat" || { echo "no case covers: ${reader%%:*}"; false; }
  done
}

# after_line TEXT LINE: the part of TEXT after its first line holding LINE.
after_line() { printf '%s\n' "$1" | awk -v l="$2" 'p { print } index($0, l) { p = 1 }'; }

@test "R210 changes: vbw show contract --changes prints the whole diff under each changed test file line, every hunk included, committed or not; approved content missing from the git history is said in one line" {
  survivor
  strengthen_shared
  sed -i.bak '10s/^true$/[ -n "$(sh src\/pay.sh)" ]/' tests/shared.sh && rm -f tests/shared.sh.bak
  local rest
  # Not committed yet: the diff is against the working file.
  run "$VBW" show contract --changes < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"changed test file tests/shared.sh"* ]] || { echo "$output"; false; }
  rest=$(after_line "$output" "changed test file tests/shared.sh")
  [ "$(printf '%s\n' "$rest" | grep -c '^[[:space:]]*@@ ')" -eq 2 ] || { echo "not two hunks:"; echo "$output"; false; }
  printf '%s\n' "$rest" | grep -q '^[[:space:]]*-true$' || { echo "no removed line:"; echo "$output"; false; }
  printf '%s\n' "$rest" | grep -qF -- '+[ "$(sh src/pay.sh)" = paid ]' || { echo "no added line 2:"; echo "$output"; false; }
  printf '%s\n' "$rest" | grep -qF -- '+[ -n "$(sh src/pay.sh)" ]' || { echo "no added line 10:"; echo "$output"; false; }
  # Committed: the same diff.
  "$VBW" commit P1.1 "test(pay): check what is printed" tests/shared.sh > /dev/null
  run "$VBW" show contract --changes < /dev/null
  rest=$(after_line "$output" "changed test file tests/shared.sh")
  [ "$(printf '%s\n' "$rest" | grep -c '^[[:space:]]*@@ ')" -eq 2 ] || { echo "not two hunks after the commit:"; echo "$output"; false; }
  printf '%s\n' "$rest" | grep -qF -- '+[ -n "$(sh src/pay.sh)" ]' || { echo "$output"; false; }
  # The approval covered content no commit holds: one line says so, no diff.
  jq '.files["tests/shared.sh"] = "0000000000000000000000000000000000000000000000000000000000000000"' .vbw/runtime/approved-contract.json > "$TEST_ROOT/ac.json" \
    && cp "$TEST_ROOT/ac.json" .vbw/runtime/approved-contract.json
  run "$VBW" show contract --changes < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  rest=$(after_line "$output" "changed test file tests/shared.sh")
  [ "$(printf '%s\n' "$rest" | grep -c '^[[:space:]]*@@ ')" -eq 0 ] || { echo "a diff was printed for content not in the history:"; echo "$output"; false; }
  printf '%s\n' "$rest" | head -n 1 | grep -qi 'tests/shared.sh.*not in .*git history\|not in .*git history.*tests/shared.sh' || { echo "no one-line notice:"; echo "$output"; false; }
}
