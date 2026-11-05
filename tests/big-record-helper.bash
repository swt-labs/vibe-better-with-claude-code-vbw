# shellcheck shell=bash
# The large-record fixture (R149). Load after helper:
#   load helper
#   load big-record-helper
#
# Two twin projects, one small and one large, built the same way: a shipped
# milestone M1 of history (50 requirements with two checks and two rules each,
# 50 phases with two done plans each, 121 decisions, 30 done todos) and an
# active milestone M2 whose requirements R51 to R53 come from the spec. They differ
# only in the length of their texts: every history text of the large twin ends
# in a run of filler characters (~), so its record is larger than 2 MB, each
# of its history lists (requirements, phases, plans, decisions) is larger than
# 128 KB, and one decision text alone is larger than 128 KB; its history
# check prints a line of filler, so once proven its proof results are larger
# than 128 KB too. The small twin's record stays under 128 KB.
# twin_norm removes the filler, so the twins' outputs compare equal exactly
# when VBW treats both records the same.

BIG_FILL='~'
BIG_PAD=5000
BIG_ONE=140000

# twin_project DIR small|big: build the twin project at DIR/project with space.
twin_project() {
  local dir="$1/project with space" kind="$2" pad=0 one=0
  [ "$kind" = small ] || { pad=$BIG_PAD; one=$BIG_ONE; }
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    vbw_git_project
    "$VBW" init > /dev/null || exit 1
    mkdir -p src tests
    if [ "$kind" = small ]; then
      printf 'echo ok\n' > tests/old.sh
    else
      printf 'printf %%s%%s\\\\n "$(printf %%2200s "" | tr " " "%s")" ok\n' "$BIG_FILL" > tests/old.sh
    fi
    printf 'grep -qx a src/a.txt\n' > tests/a.sh
    printf 'grep -qx b src/b.txt\n' > tests/b.sh
    jq --argjson pad "$pad" --argjson one "$one" --arg fill "$BIG_FILL" '
      def fill($n): if $n > 0 then $fill * $n else "" end;
      fill($pad) as $f
      | def p: . + $f;
      "2026-01-01T00:00:00Z" as $at
      | [range(1; 51)] as $n
      | .milestone = {id: "M2", title: "New work", status: "active"}
      | .shipped = [{id: "M1", title: "Old work", at: $at}]
      | .requirements = [$n[] | {id: "R\(.)", text: ("Old part \(.) works" | p), proof: "auto", status: "proven", milestone: "M1",
                                  rules: [{text: ("Old rule \(.)" | p), check: "C\(2 * . - 1)"}, {text: "Old second rule \(.)", check: "C\(2 * .)"}]}]
                        + [{id: "R51", text: "Part a works", proof: "auto", status: "open", milestone: "M2"},
                           {id: "R52", text: "Part b works", proof: "auto", status: "open", milestone: "M2"},
                           {id: "R53", text: "The pages feel calm", proof: "human", status: "open", milestone: "M2"}]
      | .checks = [$n[] | {id: "C\(2 * . - 1)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]},
                          {id: "C\(2 * .)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}]
      | .phases = [$n[] | {id: "P\(.)", title: "Old phase \(.)", reqs: ["R\(.)"], milestone: "M1",
                            goal: ("Old goal \(.)" | p), criteria: [("Old criterion \(.)" | p)], tier: "standard",
                            qa: {result: "pass", tier: "standard", tree: "0000000000000000000000000000000000000000", at: $at}}]
      | .plans = [$n[] as $k | (1, 2) | {id: "P\($k).\(.)", phase: "P\($k)", title: "Old plan \($k).\(.)", reqs: ["R\($k)"],
                                          files: ["src/old/\($k)-\(.).txt"], after: [], status: "done", role: "dev",
                                          tasks: [("Old task \($k).\(.)" | p)]}]
      | .decisions = ([range(1; 121) | {id: "D\(.)", text: ("Old decision \(.)" | p), at: $at}]
                      + [{id: "D121", text: ("Old long decision" + fill($one)), at: $at}])
      | .todos = [range(1; 31) | {id: "T\(.)", text: ("Old idea \(.)" | p), status: "done"}]
      | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
      .vbw/record.json > .vbw/runtime/fixture.json || exit 1
    # The fixture is written as a project restored from git would hold it, not through vbw:
    # no glance beside it either (a kernel write refreshes the glance; a restore has none).
    cat .vbw/runtime/fixture.json > .vbw/record.json
    rm -f .vbw/runtime/fixture.json .vbw/runtime/glance.json
    {
      printf '# Twin\n\n## Requirements\n\n'
      jq -r '.requirements[] | "- \(.id) [\(.proof)] \(.text)"' .vbw/record.json
    } > .vbw/spec.md
    git add -A && git commit -q -m "chore(test): twin fixture" || exit 1
  )
}

# twin_doc: the vbw apply document for the active milestone M2.
twin_doc() {
  jq -nc '{
    phases: [{id: "P51", title: "Part a", reqs: ["R51"], goal: "Part a works", criteria: ["src/a.txt says a"], tier: "express"},
             {id: "P52", title: "Part b", reqs: ["R52", "R53"], goal: "Part b works", criteria: ["src/b.txt says b"], tier: "express"}],
    plans: [{id: "P51.1", phase: "P51", title: "Write a", reqs: ["R51"], files: ["src/a.txt"], after: [], role: "dev", tasks: ["write a", "check a", "note a"]},
            {id: "P52.1", phase: "P52", title: "Write b", reqs: ["R52", "R53"], files: ["src/b.txt"], after: [], role: "dev", tasks: ["write b", "check b", "note b"]}],
    checks: [{id: "C101", req: "R51", run: ["sh", "tests/a.sh"], files: ["tests/a.sh"]},
             {id: "C102", req: "R52", run: ["sh", "tests/b.sh"], files: ["tests/b.sh"]}],
    rules: [{req: "R51", text: "src/a.txt holds a", check: "C101"},
            {req: "R52", text: "src/b.txt holds b", check: "C102"}]}'
}

# twins: build both twins under $TEST_ROOT ("twin small" and "twin big"); sets
# SMALL and BIG to their project folders. The large twin's record is checked
# to be the size R149 names.
twins() {
  twin_project "$TEST_ROOT/twin small" small
  twin_project "$TEST_ROOT/twin big" big
  SMALL="$TEST_ROOT/twin small/project with space"
  BIG="$TEST_ROOT/twin big/project with space"
  export SMALL BIG
  [ "$(wc -c < "$SMALL/.vbw/record.json")" -lt 131072 ] || { echo "small twin record is not small"; return 1; }
  [ "$(wc -c < "$BIG/.vbw/record.json")" -gt 2097152 ] || { echo "large twin record is not larger than 2 MB"; return 1; }
  jq -e '[.requirements, .phases, .plans, .decisions] | all(.[]; tojson | length > 131072)' "$BIG/.vbw/record.json" > /dev/null \
    || { echo "a large twin history list is not larger than 128 KB"; return 1; }
  jq -e 'any(.decisions[]; .text | length > 131072)' "$BIG/.vbw/record.json" > /dev/null \
    || { echo "no single large twin field is larger than 128 KB"; return 1; }
}

# twin_norm: stdin with what legitimately differs between the twins removed:
# the filler, the twin folder, hashes and commit ids, times and durations.
twin_norm() {
  jq -Rr --arg s "$TEST_ROOT/twin small" --arg b "$TEST_ROOT/twin big" --arg fill "$BIG_FILL" '
    split($s) | join("<twin>") | split($b) | join("<twin>") | split($fill) | join("")
    | gsub("\\b[0-9a-f]{7,64}\\b"; "<hex>")
    | gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"; "<time>")
    | gsub("[0-9]{8}T[0-9]{6}Z"; "<time>")
    | gsub("own work: .*"; "own work: <dur>")
    | gsub("\\b[0-9]+(\\.[0-9]+)? ?(ms|s|sec|seconds?|min|minutes?)\\b"; "<dur>")
    | gsub("^slowest units: .*"; "slowest units: <units>")
    | gsub("^    [^ |][^ ]* <dur>$"; "    <unit> <dur>")'
}

# twin_step CMD...: run one vbw command in each twin (stdin from $TWIN_IN when
# set, else closed). Fails, naming the command, when it fails on the small
# record (the scenario itself is wrong; TWIN_ANY=1 allows a failure both twins
# must share), when the large twin prints "Argument list too long", or when its
# exit code or normalized output (stdout and stderr) differs from the small
# twin's.
twin_step() {
  local out_s out_b code_s code_b in="${TWIN_IN:-/dev/null}"
  out_s=$(cd "$SMALL" && "$VBW" "$@" < "$in" 2>&1) && code_s=0 || code_s=$?
  out_b=$(cd "$BIG" && "$VBW" "$@" < "$in" 2>&1) && code_b=0 || code_b=$?
  if [ "$code_s" != 0 ] && [ -z "${TWIN_ANY:-}" ]; then
    printf 'vbw %s failed on the small record (exit %s), so the scenario is wrong:\n%s\n' "$*" "$code_s" "$out_s" | cut -c 1-400
    return 1
  fi
  if [[ "$out_b" == *"rgument list too long"* ]]; then
    printf 'vbw %s: the large record reached a command line:\n%s\n' "$*" "$out_b" | cut -c 1-400
    return 1
  fi
  if [ "$code_s" != "$code_b" ]; then
    printf 'vbw %s: exit %s on the small record, %s on the large one\nsmall:\n%s\nlarge:\n%s\n' "$*" "$code_s" "$code_b" "$out_s" "$out_b" | cut -c 1-400
    return 1
  fi
  if [ "$(printf '%s\n' "$out_s" | twin_norm)" != "$(printf '%s\n' "$out_b" | twin_norm)" ]; then
    printf 'vbw %s: the outputs differ\n' "$*"
    diff <(printf '%s\n' "$out_s" | twin_norm) <(printf '%s\n' "$out_b" | twin_norm) | cut -c 1-400 | head -40
    return 1
  fi
}

# in_twins CMD...: run CMD in both twins (fixture work such as writing a
# source file); fails when it fails in either.
in_twins() {
  (cd "$SMALL" && "$@") && (cd "$BIG" && "$@")
}

# leftovers DIR: what a command left in DIR's .vbw/runtime and in its git
# directory's vbw folder beyond VBW's kept state, one entry per line. The kept
# state includes proof-units.json, the proof's unit list vbw next keeps
# (docs/next.md); its temporary file (proof-units.json.PID) is a leftover.
leftovers() {
  local gd
  (cd "$1/.vbw/runtime" && find . -mindepth 1 -path ./output -prune -o -print) | sed 's|^\./||' \
    | grep -vxE 'approved-contract\.json|next\.json|step\.json|glance\.json|holder\.json|validated\.json|run-open|auto\.[A-Za-z0-9_-]+\.json|proof-units\.json|gate|output' || true
  gd=$(git -C "$1" rev-parse --git-common-dir)
  case "$gd" in /*) ;; *) gd="$1/$gd" ;; esac
  [ ! -d "$gd/vbw" ] || (cd "$gd/vbw" && find . -mindepth 1 -print) | sed 's|^\./||' | grep -vE '^[A-Za-z0-9_-]+\.json$' || true
}

# clean_step CMD...: the command behaves the same in both twins (twin_step),
# nothing was written to TMPDIR, and neither twin keeps a leftover file.
clean_step() {
  twin_step "$@"
  [ -z "$(ls -A "$TMPDIR")" ] || { echo "vbw $* wrote to TMPDIR: $(ls -A "$TMPDIR")"; return 1; }
  local s b
  s=$(leftovers "$SMALL")
  b=$(leftovers "$BIG")
  [ -z "$b" ] || { printf 'vbw %s left files behind on the large record:\n%s\n' "$*" "$b"; return 1; }
  [ -z "$s" ] || { printf 'vbw %s left files behind on the small record:\n%s\n' "$*" "$s"; return 1; }
}

# twin_fixture: a test root holding the twins, for fixture_build in setup_file
# (fixture-helper.bash). TMPDIR is set by twin_copy and twin_tmpdir, not here.
twin_fixture() {
  vbw_setup
  twins
}

# twin_tmpdir CMD...: run CMD with TMPDIR an empty folder of the test, as
# clean_step needs (a builder's walk); TMPDIR is left as it was.
twin_tmpdir() {
  mkdir -p "$TEST_ROOT/tmpdir"
  TMPDIR="$TEST_ROOT/tmpdir" "$@"
}

# The TMPDIR the test started with: a copy's own TMPDIR is a folder inside its
# test root, which a second copy in the same test removes before making its own.
TWIN_HOST_TMPDIR=${TMPDIR-}
TWIN_HOST_TMPDIR_SET=${TMPDIR+1}

# twin_copy NAME: a copy of the twin fixture NAME (fixture_copy), with TMPDIR
# set to an empty folder of the test, which clean_step keeps empty.
twin_copy() {
  if [ -n "$TWIN_HOST_TMPDIR_SET" ]; then export TMPDIR="$TWIN_HOST_TMPDIR"; else unset TMPDIR; fi
  fixture_copy "$1" || return 1
  mkdir -p "$TEST_ROOT/tmpdir"
  export TMPDIR="$TEST_ROOT/tmpdir"
}
