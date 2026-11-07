#!/usr/bin/env bats
# R197 (T167; docs/proof.md): the file vbw mutate breaks in the proof copy gets a
# modification time strictly newer than every file in the copy, build output
# included, and so does the file when it is restored to its committed bytes. A
# build that decides by file times (make, cargo) then rebuilds the broken file
# and, after the restore, the clean one; a break is never reported as surviving
# because the old build was tested, and the next unbroken run never judges the
# broken build. The time is set later than the newest file in the copy, never
# taken from the clock, so it holds on a file system with one-second time stamps
# and when build output is stamped ahead of the clock. A break that deletes a
# file is judged on its absence: nothing is stamped and no file is created. The
# build stand-in (tests/build.sh) rebuilds build/out from src/x.sh only when the
# source is newer than the output, as make and cargo decide. L1: the kernel on a
# fixture project.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Tool\n\n## Requirements\n\n- R1 [auto] The tool answers ok\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'build/\n' > .gitignore
  printf 'echo ok\n' > src/x.sh
  printf 'extra\n' > src/extra.txt
  # The build: build/out is remade only when src/x.sh is newer than it.
  cat > tests/build.sh << 'SH'
mkdir -p build
if [ ! -e build/out ] || [ src/x.sh -nt build/out ]; then
  cp src/x.sh build/out
  [ -z "${FUTURE_STAMP:-}" ] || touch -t "$FUTURE_STAMP" build/out
fi
SH
  # C1 cannot fail on what the build prints; C2 wants ok; C3 wants the extra file.
  printf 'sh tests/build.sh && sh build/out > /dev/null\n' > tests/weak.sh
  printf 'sh tests/build.sh && [ "$(sh build/out)" = ok ]\n' > tests/strong.sh
  printf '[ -e src/extra.txt ]\n' > tests/extra.sh
  jq -nc '{phases: [{id: "P1", title: "Tool", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Tool", reqs: ["R1"], files: ["src/x.sh", "src/extra.txt"], after: [], role: "dev", tasks: ["answer", "extra"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/weak.sh"], files: ["tests/weak.sh"]},
             {id: "C2", req: "R1", run: ["sh", "tests/strong.sh"], files: ["tests/strong.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/extra.sh"], files: ["tests/extra.sh"]}],
    rules: [{req: "R1", text: "the build runs", check: "C1", plan: "P1.1"},
            {req: "R1", text: "the tool answers ok", check: "C2", plan: "P1.1"},
            {req: "R1", text: "the extra file is shipped", check: "C3", plan: "P1.1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(tool): start"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

breaks() { jq -c '[.plans[] | select(.id == "P1.1") | .mutations // [] | .[]]' .vbw/record.json; }
# still_broken WORDS: the working file still holds the break (R265: the kernel never puts it back).
still_broken() { [ "$(cat src/x.sh)" = "echo $1" ] || { echo "src/x.sh was changed by the kernel: $(cat src/x.sh)"; return 1; }; }
# break_x [WORDS]: src/x.sh answers ko (or WORDS), edited before any build output the
# check will make (a Dev's edit always predates the proof copy's build).
break_x() {
  printf 'echo %s\n' "${1:-ko}" > src/x.sh
  touch -t 200001010000 src/x.sh
}
# future_stamp: a touch -t stamp one hour ahead of the clock, in local time.
future_stamp() {
  perl -e '@t = localtime(time + 3600); printf "%04d%02d%02d%02d%02d.%02d\n", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]'
}

@test "R197: a break the stale build would hide is red: the broken file is newer than the build output, so the build remakes it" {
  break_x
  run "$VBW" mutate P1.1 R1.2 "answers ko" src/x.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.2 red"* ]] || { echo "$output"; false; }
  breaks | jq -e 'length == 1 and .[0].checks == {C2: "red"} and .[0].result == "red"' || { breaks; false; }
  still_broken ko
}

@test "R197: the proof copy's restored file is newer than the build output too, so the next unbroken run rebuilds the clean code instead of judging the broken build" {
  # C1 runs first and cannot notice the break; its broken run builds ko. C2's unbroken run
  # must then rebuild from the copy's restored source, or it is refused as red on the unbroken code.
  break_x
  run "$VBW" mutate P1.1 task1 "answers ko" src/x.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks | jq -e 'length == 1 and .[0].checks == {C1: "green", C2: "red"} and .[0].result == "red"' || { breaks; false; }
  still_broken ko
}

@test "R197: the time is later than the newest file in the copy, even one stamped ahead of the clock: the kernel never relies on now" {
  export FUTURE_STAMP
  FUTURE_STAMP=$(future_stamp)
  break_x
  run "$VBW" mutate P1.1 R1.2 "answers ko" src/x.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks | jq -e 'length == 1 and .[0].checks == {C2: "red"} and .[0].result == "red"' || { breaks; false; }
  # The copy's restore after a build stamped ahead of the clock is newer still: the task
  # break's C2 run rebuilds clean. Other bytes: the same break twice is refused (R265).
  break_x "ko again"
  run "$VBW" mutate P1.1 task1 "answers ko again" src/x.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks | jq -e 'length == 2 and .[1].checks == {C1: "green", C2: "red"} and .[1].result == "red"' || { breaks; false; }
  still_broken "ko again"
}

@test "R197: a break that deletes a file is judged on its absence: nothing is stamped, no file is created, and the file stays deleted" {
  rm src/extra.txt
  run "$VBW" mutate P1.1 R1.3 "drops the extra file" src/extra.txt < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks | jq -e 'length == 1 and .[0].checks == {C3: "red"} and .[0].result == "red"' || { breaks; false; }
  [ ! -e src/extra.txt ] || { echo "src/extra.txt came back"; false; }
  # #738: the copy is kept for the next command, held by none.
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'proof.*' ! -name 'proof.keep.*' -print)" ]
  [ -z "$(find .vbw/runtime -path '*/proof.keep.*/pid' -print)" ]
}

@test "R197: the copy's newest time is read in one pass, not one stat per file, and an unreadable folder does not stop it" {
  # A stat that counts its calls. Today's big trees (node_modules) hold 100,000
  # files: one stat process per file took about 10 minutes per sweep.
  local real
  real=$(command -v stat)
  mkdir -p "$TEST_ROOT/tree/many" "$TEST_ROOT/tree/locked" "$TEST_ROOT/counting"
  for i in $(seq 1 300); do : > "$TEST_ROOT/tree/many/f$i"; done
  touch -t 203001010000 "$TEST_ROOT/tree/many/f7"
  printf '#!/bin/sh\necho call >> "%s/stat.log"\nexec "%s" "$@"\n' "$TEST_ROOT" "$real" > "$TEST_ROOT/counting/stat"
  chmod +x "$TEST_ROOT/counting/stat"
  chmod 000 "$TEST_ROOT/tree/locked"
  PATH="$TEST_ROOT/counting:$PATH" run bash -c 'set -euo pipefail; . "$1/lib/core.sh"; vbw_stamp_newer "$2" many/f1; echo stamped' _ "$PLUGIN_ROOT" "$TEST_ROOT/tree"
  chmod 755 "$TEST_ROOT/tree/locked"
  [ "$status" -eq 0 ] && [ "$output" = stamped ] || { echo "$output"; false; }
  [ "$TEST_ROOT/tree/many/f1" -nt "$TEST_ROOT/tree/many/f7" ]
  [ "$(wc -l < "$TEST_ROOT/stat.log")" -le 4 ] || { echo "stat calls: $(wc -l < "$TEST_ROOT/stat.log")"; false; }
}

@test "R197: the stamp is one second after the newest file, also in the hour a clock change repeats" {
  # 2026-10-25 01:30 UTC is 02:30 in Zurich, as 00:30 UTC was: a local stamp names the earlier one.
  mkdir -p "$TEST_ROOT/dst"
  : > "$TEST_ROOT/dst/new" && : > "$TEST_ROOT/dst/out"
  TZ=UTC0 touch -t 202610250130.00 "$TEST_ROOT/dst/new"
  TZ=UTC0 touch -t 202001010000.00 "$TEST_ROOT/dst/out"
  TZ=Europe/Zurich run bash -c 'set -euo pipefail; . "$1/lib/core.sh"; vbw_stamp_newer "$2" out; stat -c %Y "$2/out" 2> /dev/null || stat -f %m "$2/out"' _ "$PLUGIN_ROOT" "$TEST_ROOT/dst"
  [ "$status" -eq 0 ] && [ "$output" = 1792891801 ] || { echo "$output"; false; }
}

@test "R197: the kernel code is bash 3.2 code that passes JSON only through jq" {
  local f
  for f in "$PLUGIN_ROOT"/lib/cmd-mutate.sh "$PLUGIN_ROOT"/lib/core.sh "$PLUGIN_ROOT"/lib/proofcopy.sh; do
    /bin/bash -n "$f"
    ! grep -nE '^[^#]*(\b(mapfile|readarray|eval)\b|(declare|local|typeset) -[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^|,|\^)\})' "$f" || false
    ! grep -nE '^[^#]*\b(grep|sed|awk|cut)\b[^|;]*(record\.json|\.json\b)' "$f" || false
  done
}
