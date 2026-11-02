#!/usr/bin/env bats
# R103 (docs/proof.md, D260): when nothing a check or command read in its last
# passing run changed (only VBW's own record or spec changed, or a file no run
# read), vbw prove reuses that result for every check and command whose
# approved definition is unchanged, says so, and runs only the rest. A
# committed change runs only the checks and commands that read the changed
# file; uncommitted changes change nothing, because checks and commands run on
# the committed code. A proof that reused results is current: vbw qa record
# accepts it without vbw prove --full. Every check and command logs its own
# name to $RANLOG when it really runs, so a reused result shows as a missing
# line. Pinned once elsewhere: a reused line names its proof
# (proof-selective.bats), a changed check or command definition
# (reads-reuse.bats, proof-causes.bats), uncommitted changes
# (proof-selective.bats). L1.

load helper
load fixture-helper

setup_file() { fixture_build shop reuse_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# reuse_project: the project every test starts from, built once per file.
reuse_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer can refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  # Each script logs "<name><argument>" when it runs. C2 fails when FAIL is set;
  # C1 sleeps when the file named by SLOW exists (the interrupted-proof test).
  cat > tests/c1.sh << 'SH'
echo "C1$1" >> "$RANLOG"
[ ! -e "${SLOW:-/nonexistent}" ] || sleep 4
grep -qx paid src/pay.txt
SH
  cat > tests/c2.sh << 'SH'
echo "C2$1" >> "$RANLOG"
[ -z "${FAIL:-}" ]
SH
  cat > tests/cmd.sh << 'SH'
echo "cmd-$1" >> "$RANLOG"
SH
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R2", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]},
      {id:"C4", req:"R2", run:["sh","tests/c2.sh","b"], files:["tests/c2.sh"]}]
    | .commands = {lint: ["sh","tests/cmd.sh","lint"], test: ["sh","tests/cmd.sh","test"]}
    | .phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1","R2"], files:["src/pay.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  FIRST=$(jq -r '.evidence.at' .vbw/record.json)
  : > "$RANLOG"
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# ran: what really ran since the log was last emptied, sorted, one line.
ran() { sort "$RANLOG" | tr '\n' ' '; }
ALL='C1 C2 C2b cmd-lint cmd-test '

# decide: record a decision (only VBW's own record changes).
decide() { "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null; }

@test "R103: after a passing proof, a recorded decision changes only the record: prove runs nothing" {
  decide
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  [[ "$output" == *proved* ]]
}

@test "R103: a change to spec.md alone (a new human requirement, approved again) reuses every result" {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer can refund\n- R3 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: a check added since the proof runs, and only it; the others are reused" {
  decide
  edit_record '.checks += [{id:"C3", req:"R1", run:["sh","tests/c1.sh","n"], files:["tests/c1.sh"]}]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1n " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.checks | keys == ["C1","C2","C3","C4"]' .vbw/record.json
}

@test "R103: a check removed from the contract does not appear in the new proof, and the others are reused" {
  edit_record '.checks |= map(select(.id != "C4"))'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.checks | keys == ["C1","C2"]' .vbw/record.json
  [[ "$output" != *C4* ]]
}

@test "R103: a committed change to a file no check or command read runs nothing; one to a file a check read runs only that check" {
  printf 'more\n' >> README.md
  git add README.md && git commit -q -m "docs: more"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  printf 'paid\n' >> src/pay.txt
  git add src/pay.txt && git commit -q -m "feat: pay"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "a check reading a submodule runs on the submodule's committed code, its ignored files included; an uncommitted change there runs nothing, a commit there runs it again; the submodule holds no copy but the kept one (#738)" {
  git init -q "$TEST_ROOT/subsrc"
  printf 'paid\n' > "$TEST_ROOT/subsrc/pay.txt"
  printf 'deps/\n' > "$TEST_ROOT/subsrc/.gitignore"
  git -C "$TEST_ROOT/subsrc" add pay.txt .gitignore
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
  mkdir -p sub/deps
  printf 'lib\n' > sub/deps/lib
  cat > tests/c5.sh << 'SH'
echo "C5$1" >> "$RANLOG"
grep -qx paid sub/pay.txt && [ -f sub/deps/lib ]
SH
  edit_record '.checks += [{id:"C5", req:"R1", run:["sh","tests/c5.sh"], files:["tests/c5.sh"]}]'
  git add -A && git commit -q -m "chore: sub"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(ran)" == *"C5 "* ]] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  printf 'unpaid\n' > sub/pay.txt
  decide
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  git -C sub commit -q -am "feat: unpaid"
  decide
  vbw_run prove
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$(ran)" == *"C5 "* ]] || { echo "ran: $(ran)"; false; }
  # Beside the submodule itself, one worktree per kept copy, none elsewhere.
  [ "$(git -C sub worktree list --porcelain | grep -c '^worktree ')" -eq $((1 + $(ls -d .vbw/runtime/proof.keep.* | wc -l))) ] || { git -C sub worktree list; false; }
  [ -z "$(git -C sub worktree list --porcelain | grep '^worktree ' | sed 1d | grep -v '/\.vbw/runtime/proof\.keep\.[0-9]*/tree/sub$')" ] || { git -C sub worktree list; false; }
}

# sub_with_gitmodules: a submodule "sub" whose own tree holds a .gitmodules, committed.
sub_with_gitmodules() {
  git init -q "$TEST_ROOT/subsrc"
  printf 'paid\n' > "$TEST_ROOT/subsrc/pay.txt"
  printf '[submodule "x"]\n\tpath = x\n\turl = ./x\n' > "$TEST_ROOT/subsrc/.gitmodules"
  git -C "$TEST_ROOT/subsrc" add pay.txt .gitmodules
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
}

# #737: a copy is the plain checkout: a check that reads .gitmodules as a file
# passes in the proof as it does in the working folder.
@test "a project with a submodule gets a plain copy: a check that reads .gitmodules, its own or the submodule's, passes there" {
  sub_with_gitmodules
  cat > tests/c5.sh << 'SH'
echo "C5$1" >> "$RANLOG"
[ "$(git config -f .gitmodules --get-regexp path)" = "submodule.sub.path sub" ] || exit 1
grep -q 'path = x' sub/.gitmodules || exit 1
[ -z "$(git status --porcelain)" ] || { git status --porcelain; exit 1; }
[ -z "$(git -C sub status --porcelain)" ] || { git -C sub status --porcelain; exit 1; }
[ -z "$(git ls-files -v | grep -v '^H ')" ] || { git ls-files -v; exit 1; }
grep -qx paid sub/pay.txt
SH
  edit_record '.checks += [{id:"C5", req:"R1", run:["sh","tests/c5.sh"], files:["tests/c5.sh"]}]'
  git add -A && git commit -q -m "chore: sub"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(ran)" == *"C5 "* ]] || { echo "ran: $(ran)"; false; }
}

# #737: Claude Code's sandbox refuses to create any file named .gitmodules
# ("unable to create file .gitmodules: Operation not permitted"). A fake git
# stands in for it: a worktree add that writes a .gitmodules fails with git's
# message, its half-made worktree left behind. Only then is the copy made again
# with every .gitmodules unwritten (git reads it from the index), git status
# clean, and VBW's own lookup in the copy still finds the submodule.
@test "when the sandbox refuses .gitmodules, the copy is made again without it, git status stays clean, and VBW finds the submodule in the copy" {
  sub_with_gitmodules
  git add -A && git commit -q -m "chore: sub"
  mkdir -p "$TEST_ROOT/fakebin"
  cat > "$TEST_ROOT/fakebin/git" << 'SH'
#!/bin/sh
case " $* " in
  *" worktree add "*" --no-checkout "*) exec "$REAL_GIT" "$@" ;;
  *" worktree add "*)
    "$REAL_GIT" "$@" || exit
    for a; do dest=$prev; prev=$a; done
    [ -e "$dest/.gitmodules" ] || exit 0
    rm -f "$dest/.gitmodules"
    echo "error: unable to create file .gitmodules: Operation not permitted" >&2
    echo "fatal: Could not reset index file to revision 'HEAD'." >&2
    exit 128 ;;
esac
exec "$REAL_GIT" "$@"
SH
  chmod +x "$TEST_ROOT/fakebin/git"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  REAL_GIT=$(command -v git) PATH="$TEST_ROOT/fakebin:$PATH" vbw_kernel '. "$VBW_LIB/proofcopy.sh"; PROOF_SLOTS=("$VBW_RUNTIME/proof.keep.1"); mkdir -p "${PROOF_SLOTS[0]}"
    proofcopy_make "${PROOF_SLOTS[0]}"
    PROOF_COPY=${PROOF_SLOTS[0]}/tree
    for f in .gitmodules sub/.gitmodules; do [ ! -e "$PROOF_COPY/$f" ] || { echo "the copy wrote $f"; exit 1; }; done
    [ -z "$(git -C "$PROOF_COPY" status --porcelain)" ] || { git -C "$PROOF_COPY" status --porcelain; exit 1; }
    [ -z "$(git -C "$PROOF_COPY/sub" status --porcelain)" ] || exit 1
    grep -qx paid "$PROOF_COPY/sub/pay.txt" || exit 1
    [ "$(VBW_ROOT=$PROOF_COPY vbw_subs | tr "\0" "\n")" = sub ] || { echo "vbw_subs in the copy: $(VBW_ROOT=$PROOF_COPY vbw_subs | tr "\0" " ")"; exit 1; }
    [ "$(git -C "$VBW_ROOT" worktree list --porcelain | grep -c "^worktree ")" -eq 2 ] || { git -C "$VBW_ROOT" worktree list; exit 1; }
    proofcopy_remove'
}

@test "#737: without a submodule, a copy costs one git process, as before submodules" {
  mkdir -p "$TEST_ROOT/logbin"
  printf '#!/bin/sh\necho git >> "$TEST_ROOT/calls"\nexec %s "$@"\n' "$(command -v git)" > "$TEST_ROOT/logbin/git"
  chmod +x "$TEST_ROOT/logbin/git"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  PATH="$TEST_ROOT/logbin:$PATH" vbw_kernel '. "$VBW_LIB/proofcopy.sh"; : > "$TEST_ROOT/calls"
    proofcopy_checkout "$VBW_ROOT" "$TEST_ROOT/c"'
  grep -qx paid "$TEST_ROOT/c/src/pay.txt"
  [ "$(wc -l < "$TEST_ROOT/calls" | tr -d ' ')" -eq 1 ] || { cat "$TEST_ROOT/calls"; false; }
  git worktree remove --force "$TEST_ROOT/c"
}

@test "R103: an untracked project file in the working folder runs nothing" {
  printf 'buy milk\n' > todos.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  rm todos.txt
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: when the last proof did not pass, its failed checks run again and the passed checks and commands are reused; a later passing proof is reused again" {
  FAIL=1 vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.passed == false' .vbw/record.json
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "C2 C2b " ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: when the last proof was interrupted, nothing is reused" {
  touch "$TEST_ROOT/slow"
  export SLOW="$TEST_ROOT/slow"
  "$VBW" prove > /dev/null 2>&1 < /dev/null &
  local pid=$! i
  for i in $(seq 1 100); do
    grep -q C1 "$RANLOG" && break
    sleep 0.1
  done
  grep -q C1 "$RANLOG"
  kill -TERM "$pid"
  wait "$pid" || true
  # The check that was already running finishes by itself (nothing is killed).
  sleep 5
  rm -f "$TEST_ROOT/slow"
  unset SLOW
  : > "$RANLOG"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "$ALL" ] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  decide
  vbw_run prove
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
}

@test "R103: a proof that reused results is recorded as current: qa record accepts it without vbw prove --full and the requirements are proven" {
  decide
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ]
  [ "$(jq -r '.evidence.contract' .vbw/record.json)" = "$(vbw_contract_hash)" ]
  [ "$(jq -r '.evidence.tree' .vbw/record.json)" = "$(vbw_code_tree)" ]
  jq -e '.requirements | all(.[]; .status == "proven")' .vbw/record.json
  vbw_run status
  [[ "$output" == *"requirements: 2/2 proven"* ]]
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = qa ] || { echo "$output"; false; }
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" != prove ]
}

@test "R103: a changed check that fails still fails the proof, while the unchanged checks are reused and stay passing" {
  edit_record '(.checks[] | select(.id == "C2")).run = ["sh","tests/c2.sh","y"]'
  "$VBW" approve > /dev/null
  FAIL=1 vbw_run prove
  [ "$status" -eq 1 ]
  [ "$(ran)" = "C2y " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.passed == false and .evidence.checks.C2.status == "fail" and .evidence.checks.C1.status == "pass"' .vbw/record.json
}

@test "R103: docs/proof.md shows the reused count of the output" {
  grep -qE 'checks: [0-9N]+ ran, [0-9N]+ reused' "$REPO_ROOT/docs/proof.md"
}
