#!/usr/bin/env bats
# R256 (docs/proof.md, The computer-wide limit): every unit of vbw prove, vbw fix done
# and vbw mutate runs its command at low priority (nice), so the machine stays usable
# while a proof runs. One code path does it (checks_exec in plugin/lib/checks.sh), so
# no unit kind is missed. Low priority changes nothing else about a unit: its exit
# code and its kept output are as before. When the nice program cannot be found on
# PATH, the units run at normal priority, the proof is never refused for it, and
# its summary says so in one line. L1: a check that prints its own priority
# (ps -o nice= -p $$) under each command, compared with the same script run by hand
# from the test (a test that itself runs inside a proof's unit is already niced, so
# only the difference counts).

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  # tests/nice.sh LABEL: appends "LABEL <nice value of this shell>" to $NICELOG and passes.
  cat > tests/nice.sh << 'SH'
n=$(ps -o nice= -p $$ | tr -d ' ')
printf '%s %s\n' "$1" "$n" >> "$NICELOG"
SH
  # tests/fail.sh: a unit that fails with its own exit code and output.
  printf 'echo boom\nexit 3\n' > tests/fail.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/nice.sh", "C1"], files: ["tests/nice.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  export NICELOG="$TEST_ROOT/nice.log"
  : > "$NICELOG"
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
  : > "$NICELOG"
  sh tests/nice.sh hand
  BASE=$(values hand)
  : > "$NICELOG"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
# open_fix: F1 of R1 open, so vbw fix done F1 runs C1.
open_fix() { edit_record '.plans[0].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]'; }
# values LABEL: the nice values the units labelled LABEL recorded, one per line.
values() { awk -v l="$1" '$1 == l { print $2 }' "$NICELOG"; }
# above_base LABEL: at least one value was recorded for LABEL and every one is above the hand-run value.
above_base() {
  local v n=0
  while IFS= read -r v; do
    n=$((n + 1))
    [ "$v" -gt "$BASE" ] || { echo "$1 ran at nice $v, by hand it is $BASE"; cat "$NICELOG"; return 1; }
  done < <(values "$1")
  [ "$n" -gt 0 ] || { echo "no unit labelled $1 ran"; cat "$NICELOG"; return 1; }
}

@test "R256: a check run by vbw prove has a higher nice value than the same command run by hand" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  above_base C1
}

@test "R256: a check run by vbw fix done has a higher nice value than the same command run by hand" {
  open_fix
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  above_base C1
}

@test "R256: the checks vbw mutate runs, directly and from its queue, have a higher nice value than the same command run by hand" {
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  # tests/nice.sh never fails, so the break survives (exit 1): only the priorities matter here.
  run env VBW_SESSION_ID=s1 "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || { echo "$status: $output"; false; }
  above_base C1
  : > "$NICELOG"
  printf 'echo unpaid again\n' > src/pay.sh
  VBW_SESSION_ID=s1 "$VBW" mutate P1.1 R1.1 --queue "prints unpaid again" src/pay.sh < /dev/null > /dev/null
  run env VBW_SESSION_ID=s1 "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || { echo "$status: $output"; false; }
  above_base C1
}

@test "R256: one code path lowers the priority: checks_exec in plugin/lib/checks.sh, and no command file calls nice itself" {
  grep -qE '(^|[^[:alnum:]_])nice( |$)' "$PLUGIN_ROOT/lib/checks.sh" || { echo "plugin/lib/checks.sh does not run units under nice"; false; }
  local f hits
  for f in cmd-prove.sh cmd-fix.sh cmd-mutate.sh mutate-queue.sh cmd-check.sh testfiles.sh; do
    [ -f "$PLUGIN_ROOT/lib/$f" ] || continue
    hits=$(grep -nE '(^|[^[:alnum:]_])nice -n|(^|[^[:alnum:]_])nice "' "$PLUGIN_ROOT/lib/$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
    [ -z "$hits" ] || { echo "$f runs nice itself instead of leaving it to checks_exec:"; echo "$hits"; false; }
  done
}

@test "R256: low priority changes nothing else: a failing unit keeps its exit code and its output in the evidence" {
  edit_record '.checks += [{id: "C2", req: "R1", run: ["sh", "tests/fail.sh"], files: ["tests/fail.sh"]}]
    | .protected = ([.checks[].files[]] | unique)'
  git add -A && git commit -q -m "chore: C2"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C2 | .status == "fail" and .exit == 3 and (.tail | test("boom"))' .vbw/record.json || { jq '.evidence.checks' .vbw/record.json; false; }
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
}

@test "R256: without nice on PATH the units run at normal priority, the proof is not refused, and its summary says so in one line" {
  local d="$TEST_ROOT/nonice" dir f rest=""
  mkdir -p "$d"
  for dir in /usr/bin /bin; do
    for f in "$dir"/*; do
      [ -e "$d/$(basename "$f")" ] || ln -s "$f" "$d/$(basename "$f")"
    done
  done
  rm -f "$d/nice"
  rest=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -vE '^(/usr/bin|/bin)$' | paste -sd: -)
  ! PATH="$d:$rest" command -v nice > /dev/null 2>&1 || { echo "nice is still on the test PATH"; false; }
  PATH="$d:$rest" run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
  [ "$(values C1 | head -n 1)" = "$BASE" ] || { echo "without nice the unit ran at $(values C1 | head -n 1), by hand $BASE"; false; }
  [ "$(printf '%s\n' "$output" | grep -ci 'nice')" -eq 1 ] || { echo "the summary does not say once that nice was not found:"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -i 'nice' | grep -qi 'normal priority' || { echo "$output"; false; }
}
