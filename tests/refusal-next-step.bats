#!/usr/bin/env bats
# R162 (docs/workflows.md, docs/guards.md): every refusal VBW gives while a plan
# changes says what to do instead. Each refusal of vbw apply (full apply, --add,
# --patch), of vbw run start, and each block of the file guard and the Bash
# guard ends with its next step, written "Next: " and then a command to run or a
# change to make. This file lists every refusal path and fails when one has no
# next step; a new refusal path gets its line here. R216: every refusal vbw apply
# builds itself takes an arm of its own in apply_next, never the fallback; R219
# and R220 add the Bash guard's unreadable-target block and vbw apply's
# empty-filter refusal. L1.

load helper
load replan-helper
load fixture-helper

built_project() {
  vbw_setup
  replan_project
  printf 'true\n' > tests/c1.sh
  printf 'true\n' > tests/c2.sh
  printf 'true\n' > tests/c3.sh
  # A bats file with named cases, for a check that filters it by case name (R220).
  printf '@test "R1: paying works" { true; }\n' > tests/x.bats
  # P2.1 may write tests/, so only the protection of a check file stops a write
  # there; P2.2 shares src/c.txt with P2.1.
  replan_accepted full "$(replan_doc '(.plans[] | select(.id == "P2.1")).files = ["src/c.txt", "tests/"]
    | .plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/c.txt"], after: [], tasks: ["mail"]}]
    | .checks = [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
      {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}]
    | .rules = [{req: "R1", text: "paying works", check: "C1"}, {req: "R2", text: "a receipt is shown", check: "C2"}]')"
  FULL=$(jq -c '.milestone.id as $m | {phases: [.phases[] | select(.milestone == $m) | {id, title, reqs, goal, criteria, tier}],
      plans: [.plans[] | {id, phase, title, reqs, files, after, tasks}], checks: .checks,
      rules: [.requirements[] | .id as $q | (.rules // [])[] | {req: $q, text, check}]}' .vbw/record.json)
  ADD='{"phases": [{"id": "P3", "title": "Refund", "reqs": ["R3"], "goal": "Customers get refunds", "criteria": ["a refund is paid"], "tier": "standard"}],
    "plans": [{"id": "P3.1", "phase": "P3", "title": "Refund", "reqs": ["R3"], "files": ["src/r.txt"], "after": []}],
    "checks": [{"id": "C3", "req": "R3", "run": ["sh", "tests/c3.sh"], "files": ["tests/c3.sh"]}],
    "rules": [{"req": "R3", "text": "a refund is paid", "check": "C3"}]}'
  git add -A
  git commit -q -m "chore(test): planned"
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# next_step WHAT MESSAGE: the message's last line holds "Next: " and a step.
next_step() {
  local last
  last=$(printf '%s\n' "$2" | sed '/^[[:space:]]*$/d' | tail -n 1)
  [[ "$last" == *"Next: "?* ]] || { printf '%s: no next step at the end of the refusal:\n%s\n' "$1" "$2"; return 1; }
}

FALLBACK_NEXT='Next: fix what the message names in the document, then run vbw apply again (vbw doctor checks the record)'

# apply_refusal MODE WHAT DOC [fallback]: vbw apply in MODE refuses DOC with a next step that is
# an arm of its own (R216), not the fallback arm's text. A fourth argument "fallback" marks a record
# validation (record_violation) that takes the fallback by design.
apply_refusal() {
  replan_refused "$1" "$3" || { echo "$2"; return 1; }
  next_step "apply ($1): $2" "$output"
  if [ "${4:-}" != fallback ]; then
    [ "$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)" != "$FALLBACK_NEXT" ] \
      || { printf 'apply (%s): %s takes the fallback arm, not an arm of its own:\n%s\n' "$1" "$2" "$output"; return 1; }
  fi
}

full_with() { printf '%s' "$FULL" | jq -c "$1"; }
add_with() { printf '%s' "$ADD" | jq -c "$1"; }
# empty_filter_full: FULL with a check C9 of R2 running tests/x.bats with a case filter no case name matches (R220).
empty_filter_full() {
  full_with '.checks += [{id: "C9", req: "R2", run: ["bats", "--filter", "R220", "tests/x.bats"], files: ["tests/x.bats"]}]
    | .rules += [{req: "R2", text: "a receipt is filed", check: "C9"}]'
}

@test "R162: every refusal written out in cmd-apply.sh and cmd-run.sh carries its next step" {
  # A vbw_die with a message written in the code (not built from a variable that
  # already carries one) must hold "Next: " itself, or go through apply_refuse or
  # apply_internal, which add it. A new direct refusal without a next step fails here.
  local bad
  bad=$(grep -nE 'vbw_die "[^$]' "$PLUGIN_ROOT/lib/cmd-apply.sh" "$PLUGIN_ROOT/lib/cmd-run.sh" | grep -v 'Next: ' || true)
  [ -z "$bad" ] || { printf 'refusals without a next step:\n%s\n' "$bad"; false; }
  grep -q 'Next: ' <(grep -n '^apply_refuse()' "$PLUGIN_ROOT/lib/cmd-apply.sh")
  grep -q 'Next: ' <(grep -n '^apply_internal()' "$PLUGIN_ROOT/lib/cmd-apply.sh")
}

# 6.3: a refusal says what was refused, why, and the next step.
@test "R162: every kernel line that writes 'refused:' carries its next step" {
  local bad
  bad=$(grep -nE 'refused: ' "$PLUGIN_ROOT"/lib/*.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'Next: ' || true)
  [ -z "$bad" ] || { printf "'refused:' without a next step:\n%s\n" "$bad"; false; }
}

@test "R162: a record write the kernel refuses as invalid ends with its next step, and writes nothing" {
  local before
  before=$(cksum < .vbw/record.json)
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel 'record_update ".milestone = 5"'
  [ "$status" -ne 0 ] || { echo "accepted: $output"; false; }
  [[ "$output" == *"vbw: refused: "* ]] || { echo "$output"; false; }
  next_step "an invalid record write" "$output"
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R162: every refusal of vbw run confirm ends with its next step" {
  confirm_refusal() {
    run env VBW_SESSION_ID=s1 "$VBW" run confirm "$@"
    [ "$status" -ne 0 ] || { echo "run confirm $*: accepted: $output"; return 1; }
    next_step "run confirm $*" "$output"
  }
  confirm_refusal P1.1
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  confirm_refusal P9.9
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  confirm_refusal P1.1
}

@test "R162 R216 R220: every refusal of a full apply ends with its next step" {
  replan_start P1.1
  apply_refusal full "not JSON" 'not json {'
  apply_refusal full "not an object" '[]'
  apply_refusal full "an unknown key" "$(full_with '.extra = []')"
  apply_refusal full "phases not an array" "$(full_with '.phases = {}')"
  apply_refusal full "an unknown phase field" "$(full_with '.phases[0].colour = "red"')"
  apply_refusal full "an unknown plan field" "$(full_with '.plans[0].file = "x"')"
  apply_refusal full "an invalid tier" "$(full_with '.phases[0].tier = "fast"')"
  # A record validation (record_violation): it takes the fallback arm by design.
  apply_refusal full "an unknown requirement" "$(full_with '(.plans[] | select(.id == "P2.1")).reqs = ["R9"]')" fallback
  # A record validation (record_violation): it takes the fallback arm by design.
  apply_refusal full "a plan for no phase" "$(full_with '.plans += [{id: "P9.1", phase: "P9", title: "x", reqs: ["R2"], files: ["src/x.txt"], after: []}]')" fallback
  apply_refusal full "a changed started plan" "$(full_with '(.plans[] | select(.id == "P1.1")).files += ["src/extra.txt"]')"
  apply_refusal full "a dropped started plan" "$(full_with '.plans |= map(select(.id != "P1.1")) | (.plans[] | select(.id == "P1.2")).after = []')"
  apply_refusal full "a renamed started phase" "$(full_with '(.phases[] | select(.id == "P1")).title = "Checkout"')"
  apply_refusal full "a started phase's requirements" "$(full_with '(.phases[] | select(.id == "P1")).reqs = ["R1", "R3"]')"
  apply_refusal full "a started phase's goal" "$(full_with '(.phases[] | select(.id == "P1")).goal = "Customers pay twice"')"
  apply_refusal full "a missing rule" "$(full_with '.phases += [{id: "P3", title: "Refund", reqs: ["R3"], goal: "g", criteria: ["c"], tier: "standard"}]
    | .plans += [{id: "P3.1", phase: "P3", title: "Refund", reqs: ["R3"], files: ["src/r.txt"], after: []}]
    | .checks += [{id: "C3", req: "R3", run: ["sh", "tests/c3.sh"], files: ["tests/c3.sh"]}]')"
  apply_refusal full "a rule naming no check of its requirement" "$(full_with '.rules += [{req: "R2", text: "x", check: "C1"}]')"
  apply_refusal full "a tier below its floor" "$(full_with '(.plans[] | select(.id == "P2.2")).files = ["src/payments/charge.js"]')"
  apply_refusal full "an express phase with two plans" "$(full_with '(.phases[] | select(.id == "P2")).tier = "express"')"
  apply_refusal full "a malformed single-file test form" "$(full_with '.test_files = {run: ["bats"], files: ["tests/*.bats"]}')"
  apply_refusal full "a bats case filter matching no case name" "$(empty_filter_full)"
  mv .vbw/spec.md "$TEST_ROOT/spec.md"
  apply_refusal full "a test-file form with no .vbw/spec.md to write it into" "$(full_with '.test_files = {run: ["bats", "{file}"], files: ["tests/*.bats"]}')"
  mv "$TEST_ROOT/spec.md" .vbw/spec.md
  replan_edit '(.requirements[] | select(.id == "R3")).milestone = "M0"'
  apply_refusal full "a requirement of another milestone" "$(full_with '.phases += [{id: "P3", title: "Refund", reqs: ["R3"], goal: "g", criteria: ["c"], tier: "standard"}]
    | .plans += [{id: "P3.1", phase: "P3", title: "Refund", reqs: ["R3"], files: ["src/r.txt"], after: []}]')"
  replan_edit '(.requirements[] | select(.id == "R3")).milestone = "M1"'
  "$VBW" run start build P2.1 > /dev/null
  apply_refusal full "an open run" "$FULL"
}

@test "R162 R216 R220: every refusal of vbw apply --add ends with its next step" {
  apply_refusal add "not JSON" 'not json {'
  apply_refusal add "no phases" '{"plans": []}'
  apply_refusal add "an unknown phase field" "$(add_with '.phases[0].colour = "red"')"
  apply_refusal add "an invalid tier" "$(add_with '.phases[0].tier = "fast"')"
  apply_refusal add "a phase id in use" "$(add_with '.phases[0].id = "P2" | .plans[0].phase = "P2"')"
  apply_refusal add "a plan for a phase it does not bring" "$(add_with '.plans[0].phase = "P2"')"
  apply_refusal add "a plan id in use" "$(add_with '.plans[0].id = "P2.1"')"
  apply_refusal add "a check id in use" "$(add_with '.checks[0].id = "C1" | .rules[0].check = "C1"')"
  apply_refusal add "a check for a requirement it does not bring" "$(add_with '.checks += [{id: "C4", req: "R2", run: ["true"]}]')"
  apply_refusal add "a missing rule" "$(add_with '.rules = []')"
  apply_refusal add "a tier below its floor" "$(add_with '.plans[0].files = ["src/payments/refund.js"]')"
  apply_refusal add "a malformed single-file test form" "$(add_with '.test_files = {run: ["bats"], files: ["tests/*.bats"]}')"
  apply_refusal add "a bats case filter matching no case name" "$(add_with '.checks[0].run = ["bats", "--filter", "R220", "tests/x.bats"] | .checks[0].files = ["tests/x.bats"]')"
  # P2 has not started: a requirement it covers is changed there, not planned again beside it.
  apply_refusal add "a requirement a phase of this milestone covers while that phase has not started" "$(add_with '.phases[0].reqs = ["R2"] | .plans[0].reqs = ["R2"] | .checks[0].req = "R2" | .rules[0].req = "R2"')"
  replan_edit '(.requirements[] | select(.id == "R3")).milestone = "M0"'
  apply_refusal add "a requirement of another milestone" "$ADD"
  replan_edit '(.requirements[] | select(.id == "R3")).milestone = "M1"'
  replan_edit '(.phases[] | select(.id == "P2")).milestone = "M0"'
  apply_refusal add "a requirement a phase of another milestone covers" "$(add_with '.phases[0].reqs = ["R2"] | .plans[0].reqs = ["R2"] | .checks[0].req = "R2" | .rules[0].req = "R2"')"
  apply_refusal add "a phase id that exists in another milestone" "$(add_with '.phases[0].id = "P2" | .plans[0].phase = "P2"')"
  replan_edit '(.phases[] | select(.id == "P2")).milestone = "M1"'
  "$VBW" run start build P2.1 > /dev/null
  apply_refusal add "an open run" "$ADD"
}

@test "R162 R216 R220: every refusal of vbw apply --patch ends with its next step" {
  replan_start P1.1
  apply_refusal patch "not JSON" 'not json {'
  apply_refusal patch "phases" '{"phases": []}'
  apply_refusal patch "an unknown plan field" '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/c.txt"], "after": [], "colour": "red"}]}'
  apply_refusal patch "a changed started plan" '{"plans": [{"id": "P1.1", "phase": "P1", "title": "Pay form", "reqs": ["R1"], "files": ["src/a.txt", "src/z.txt"], "after": []}]}'
  # A record validation (record_violation): it takes the fallback arm by design.
  apply_refusal patch "a plan for no phase" '{"plans": [{"id": "P9.1", "phase": "P9", "title": "x", "reqs": ["R2"], "files": ["src/x.txt"], "after": []}]}' fallback
  apply_refusal patch "a rule naming no check" '{"rules": [{"req": "R1", "text": "a second rule", "check": "C9"}]}'
  apply_refusal patch "a bats case filter matching no case name" '{"checks": [{"id": "C9", "req": "R2", "run": ["bats", "--filter", "R220", "tests/x.bats"], "files": ["tests/x.bats"]}],
    "rules": [{"req": "R2", "text": "a receipt is filed", "check": "C9"}]}'
  "$VBW" run start build P2.1 > /dev/null
  apply_refusal patch "an open run" '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/c.txt"], "after": []}]}'
}

# start_refusal WHAT SESSION ARGS...: vbw run start ARGS is refused with a next step.
start_refusal() {
  local what=$1 me=$2 out code=0
  shift 2
  out=$(VBW_SESSION_ID=$me "$VBW" run start "$@" < /dev/null 2>&1) || code=$?
  [ "$code" -ne 0 ] || { echo "$what: vbw run start $* was accepted: $out"; return 1; }
  next_step "run start: $what" "$out"
}

@test "R162: every refusal of vbw run start ends with its next step" {
  replan_start P1.1
  "$VBW" qa finding R1 "a payment of zero is accepted" > /dev/null
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  "$VBW" fix done F1 > /dev/null 2>&1 || true
  replan_edit '(.fixes[] | select(.id == "F1")).status = "closed"'
  start_refusal "an unknown plan" s1 build P9.9
  start_refusal "a plan already done" s1 build P1.1
  replan_edit '(.plans[] | select(.id == "P1.1")).status = "planned"'
  start_refusal "a plan waiting for another" s1 build P1.2
  start_refusal "two plans sharing a file" s1 build P2.1 P2.2
  start_refusal "an unknown fix" s1 fix F9
  start_refusal "a fix that is not open" s1 fix F1
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  start_refusal "a run already open in this session" s1 build P2.2
  start_refusal "a run open in another session" s2 build P2.2
  start_refusal "a run open in another session" s2 plan
}

# guard_answer TOOL INPUT_JSON [PLUGIN]: the guard's block reason for the call,
# from a deny answer or an exit-2 message; empty when it was not blocked.
guard_answer() {
  local cmd root=${3:-$PLUGIN_ROOT} out code=0
  cmd=$(jq -r --arg t "$1" '[.hooks.PreToolUse[] | select((.matcher // "") as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$root/hooks/hooks.json")
  out=$(printf '%s' "$2" | CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$PROJECT" sh -c "$cmd" 2> "$TEST_ROOT/err") || code=$?
  if [ "$code" -eq 2 ]; then cat "$TEST_ROOT/err"; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2> /dev/null; fi
}
fin() { jq -nc --arg t "$1" --arg p "$2" --arg a "${3:-}" --arg s "${4:-s1}" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: $s, cwd: $d, tool_name: $t,
  tool_input: {file_path: $p, content: "x", old_string: "a", new_string: "b"}} + (if $a == "" then {} else {agent_id: "a1", agent_type: $a} end)'; }
bin() { jq -nc --arg c "$1" --arg a "${2:-}" --arg s "${3:-s1}" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: $s, cwd: $d, tool_name: "Bash",
  tool_input: {command: $c}} + (if $a == "" then {} else {agent_id: "a1", agent_type: $a} end)'; }

# blocks WHAT TOOL INPUT_JSON [PLUGIN]: the guard blocks the call with a next step.
blocks() {
  local why
  why=$(guard_answer "$2" "$3" "${4:-}")
  [ -n "$why" ] || { echo "$1: not blocked"; return 1; }
  next_step "guard: $1" "$why"
}

@test "R162 R219: every block of the file guard and the Bash guard ends with its next step" {
  printf 'SECRET=1\n' > .env
  blocks "a secret file (file tool)" Read "$(fin Read .env)"
  blocks "a secret file (Bash)" Bash "$(bin 'cat .env')"
  blocks "the record (file tool)" Write "$(fin Write .vbw/record.json)"
  blocks "the record (Bash)" Bash "$(bin 'echo x > .vbw/record.json')"
  blocks "the consent file (file tool)" Write "$(fin Write .git/vbw/consent.json)"
  blocks "the consent file (Bash)" Bash "$(bin 'echo x > .git/vbw/consent.json')"
  blocks "vbw approve by an agent (Bash)" Bash "$(bin 'vbw approve' vbw:lead)"
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  blocks "the status file (file tool)" Write "$(fin Write .vbw/runtime/glance.json vbw:dev)"
  blocks "the status file (Bash)" Bash "$(bin 'printf x > .vbw/runtime/glance.json' vbw:dev)"
  blocks "another session's files (file tool)" Write "$(fin Write src/c.txt "" s2)"
  blocks "another session's files (Bash)" Bash "$(bin 'printf x > src/c.txt' "" s2)"
  blocks "a protected check file (file tool)" Edit "$(fin Edit tests/c1.sh vbw:dev)"
  blocks "a protected check file (Bash)" Bash "$(bin 'printf x > tests/c1.sh' vbw:dev)"
  blocks "a folder that holds a protected check file (Bash)" Bash "$(bin 'rm -r tests' vbw:dev)"
  blocks "a glob that matches a protected check file (Bash)" Bash "$(bin 'sed -i s/a/b/ tests/c*.sh' vbw:dev)"
  blocks "a file outside the run's plan (file tool)" Write "$(fin Write README.md vbw:dev)"
  blocks "a file outside the run's plan (Bash)" Bash "$(bin 'printf x > README.md' vbw:dev)"
  blocks "a program writing a file the guard cannot name (Bash)" Bash "$(bin $'python3 - <<\'EOF\'\np = "tests/c1.sh"\nopen(p, "w").write("x")\nEOF' vbw:dev)"
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start plan > /dev/null
  blocks "a product file while planning (file tool)" Write "$(fin Write src/c.txt vbw:lead)"
  blocks "a product file while planning (Bash)" Bash "$(bin 'printf x > src/c.txt' vbw:lead)"
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start qa > /dev/null
  blocks "a write during a run whose agents only read (file tool)" Write "$(fin Write src/c.txt vbw:qa)"
  blocks "a write during a run whose agents only read (Bash)" Bash "$(bin 'printf x > src/c.txt' vbw:qa)"
}

@test "R162: a guard that failed during a run blocks with a next step" {
  local copy="$TEST_ROOT/plugin copy"
  cp -R "$PLUGIN_ROOT" "$copy"
  printf 'error("broken on purpose")\n' > "$copy/hooks/guard-file.jq"
  printf 'error("broken on purpose")\n' > "$copy/hooks/guard-bash.jq"
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  blocks "a failed file guard" Write "$(fin Write src/c.txt vbw:dev)" "$copy"
  blocks "a failed Bash guard" Bash "$(bin 'ls' vbw:dev)" "$copy"
}

# R216, R220: apply_next answers the two-owner, mixed-owner and empty-filter messages with arms of their own.
@test "R216 R220: apply_next answers the two-owner (ordered and beside), mixed-owner and empty-filter messages with their own arms" {
  local two="give each plan's rules a check of their own (a separate test file, or the same file with a case filter as a distinct check), or move the rules to one plan"
  local mixed='name a plan on every rule of the requirement, or on none (vbw apply --patch rewords a rule: {"rule": "Rn.k", "plan": "P1.1"})'
  local empty="write the cases the filter names into tests/x.bats (each @test name matching the pattern), see them fail with the runner, then send the document again; or correct the pattern"
  local ordered="C2 is owned by two plans that build one after the other (P2.2 builds after P2.1): P2.1 and P2.2; the earlier plan's mutation step would find C2 red on unbroken code"
  local beside="C2 is owned by two plans that build beside each other (a shared wave): P2.1 and P2.2; the first Dev's mutation step would run C2 before the other Dev committed, a race that fails only sometimes"
  local m="R1: 1 of 2 rules name a plan: name one on every rule or on none"
  local filt="C9 runs tests/x.bats with a case filter (--filter 'R220') that matches no case name in the file: the Lead writes the failing cases at planning, so a new check is red because its cases fail, never because none exist" got
  got=$(VBW_LIB="$PLUGIN_ROOT/lib" bash -c 'source "$VBW_LIB/cmd-apply.sh"; apply_next "$1"; apply_next "$2"; apply_next "$3"; apply_next "$4"' _ "$ordered" "$beside" "$m" "$filt")
  [ "$got" = "$two"$'\n'"$two"$'\n'"$mixed"$'\n'"$empty" ] || { printf 'apply_next answered:\n%s\n' "$got"; false; }
  [[ "$got" != *"fix what the message names"* ]]
}
