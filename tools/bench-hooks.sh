#!/usr/bin/env bash
# Hook cost budget (build plan M3, K20): the PreToolUse guard runs before
# every tool call. Runs the hooks.json command the way Claude Code does (sh -c,
# JSON on stdin, CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR set) and measures the
# CPU time (user + system) of the whole process tree per call, averaged over
# RUNS calls. VBW's own cost is the hook's CPU time minus that of the same
# `sh -c jq` with an empty program: shell and jq startup are the platform's
# (about 8 ms of CPU on an idle Mac), paid by any hook, and not ours to remove.
# The budget (R151): VBW's own CPU per call is at most VBW_HOOK_BUDGET_MS (default 20),
# judged for each guard alone, however it compares with the startup.
# - CPU time, not wall-clock time: waiting for a busy machine is not the hook's
#   work.
# - A machine too busy to measure: when that startup alone (measured first) is above
#   the hook limit, the bench prints one line saying so, judges nothing and exits 0.
# - A case over its budget is measured once more before it is judged, and a line
#   says so with the first measure (D517): a machine busy for one measure is not a
#   slow hook, and a slow hook is slow twice.
# A real regression still shows: an added subprocess costs several ms, and the 20 KB
# heredoc case catches work that grows faster than the input.
# Every input is measured on the small record, on a record of more than 2 MB
# (R149: a long-lived project's record) and on the records of N checks below,
# all with the same build lease.
# The status line is measured on both records too: its CPU per call is at most
# VBW_STATUSLINE_BUDGET_MS (default 60), startup included.
# Three more projects (R150) hold records of 51, 500 and 2,000 checks (the last over
# 2 MB), each written once by the kernel, so each is schema 4 with the protected
# field. The small record is format 4 too. Every guard input takes the path a real
# project takes, and the lines 'guard (NAME, N checks)' share one budget: a guard's
# cost does not climb with the number of checks.
# The hand-back (R184) is measured on a line of its own, 'status line (VBW off)':
# the statusLine setting `vbw statusline on` writes, run as Claude Code runs it
# (sh -c, in a project whose .claude/settings.json turns the plugin off, the status
# line JSON on stdin), with the bench's plugin in a Claude config folder of the
# bench's own and a small earlier status line saved first. VBW's own cost is the
# whole call minus the same earlier status line run on its own by the same shells
# (what the user would pay without VBW), judged against VBW_HANDBACK_BUDGET_MS
# (default 10); the bench fails if the earlier status line's marker did not show.
# Outside a VBW project (R224) the same hand-back is measured as 'status line (no project)':
# a git folder with no .vbw at or above it (its own folder, apart from the bench's
# project), the same setting and earlier status line, the same cost rule and budget,
# and the bench fails when the earlier status line did not show.
# A session that loaded the plugin (R185) is measured on 'status line (loaded copy)':
# the bench's plugin's SessionStart hook starts a session the way claude --plugin-dir
# does (the plugin data folder of a vbw@inline copy), a stand-in installed release
# sits in the same config folder, and the setting runs as above. It is judged against
# the same limit, and the bench fails if the loaded copy did not render.
# Reference workload (R222, #716): before any record is built or case judged, the bench
# measures one fixed workload (a jq call of the guard's shape over a program and a document written by the bench, run through sh -c as the
# hooks are, RUNS calls) on this machine in this run, and prints once
# 'reference: <X> ms CPU per call; nominal <N> ms (...); ratio <R>', R = measured / nominal.
# NOMINAL_MS is the workload's cost on the two nominal machines (an M1 Max Mac and
# GitHub's macOS runner), the larger of the two so both sit at a ratio of 1 or less. It is
# a debt: measure it again whenever the workload or the nominal machines change.
# At a ratio of 1 or less every case is judged against its absolute budget, as above (the
# budgets are the documented meaning on a nominal machine). Above 1, a case over its
# budget but within budget x ratio prints its line on stdout marked ': slow (ratio R,
# scaled budget S ms)' and the status is unchanged; over budget x ratio it is ': OVER' on
# stderr and status 1, so a uniformly slow runner reports slow and a real regression of
# one case still fails. The measure-again rule judges the second measure the same way.
# VBW_BENCH_REFERENCE_MS stands in for the measured reference (tests), as
# VBW_HOOK_BUDGET_MS does for a limit. CI sets neither: tools/test.sh --shard runs the
# bench in shard 1 of each matrix entry, so the reference line shows there.
# The reference's program and document (R231) are written by the bench itself at the start
# of the run, from its own fixed text: VBW_BENCH_REFERENCE_FILES=DIR (tests) writes the
# two files (reference.jq, reference.json) into DIR and exits 0 without measuring.
# VBW_BENCH_RUNS and VBW_BENCH_PLUGIN_ROOT override the runs and the plugin (tests).
# VBW_BENCH_ONLY (tests) runs only the cases asked for, and builds only the records
# they need, so a test that asserts on one line does not pay for the whole bench.
# A selector is the start of a printed label, matched against the label and its
# colon: 'guard (git' names every git case, 'status line:' only the plain status
# line. Several selectors are joined with '|' (the labels hold commas). Unset or
# empty, every case runs: the release run is the full bench. A selector that names
# no case exits 2 and lists the cases, so a typo never passes as an empty run. Each
# case that runs is judged exactly as in the full bench.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET_MS="${VBW_HOOK_BUDGET_MS:-20}"
STATUS_MS="${VBW_STATUSLINE_BUDGET_MS:-60}"
HANDBACK_MS="${VBW_HANDBACK_BUDGET_MS:-10}"
RUNS="${VBW_BENCH_RUNS:-100}"
PLUGIN="${VBW_BENCH_PLUGIN_ROOT:-$ROOT/plugin}"
GUARD_INPUTS="git npm big interp read answer"
SIZES="51 500 2000"
# The reference workload's nominal cost (R222): CPU ms per call of the workload in the
# reference block below, on the two nominal machines, measured NOMINAL_WHEN. This is a
# debt: measure it again whenever the workload or the nominal machines change.
# October 2026. The workload is one jq call of the guard's shape (--rawfile glance, --arg root,
# --arg dir, --arg open, -f PROGRAM - DOCUMENT END) over a program of 24760 bytes and a
# document of 86107 bytes, both written by this script. M1 Max Mac: 14.7 to 15.8 ms over
# five runs of this script on 2026-10-31. GitHub's macOS runner: 16.7 ms in the bench
# shard 1 log of pull request #740 (2026-10-31). The larger of the two is pinned, so both
# machines sit at a ratio of 1 or less.
NOMINAL_MS=16.7
NOMINAL_WHEN="October 2026"

# case_labels: the label of every case, in the order the bench runs them.
case_labels() {
  local input n
  for input in $GUARD_INPUTS; do printf 'guard (%s)\n' "$input"; done
  for input in $GUARD_INPUTS; do printf 'guard (%s, large record)\n' "$input"; done
  printf '%s\n' 'guard (loop)' 'guard (loop, large record)'
  for n in $SIZES; do
    for input in $GUARD_INPUTS; do printf 'guard (%s, %s checks)\n' "$input" "$n"; done
  done
  printf '%s\n' 'status line' 'status line (large record)' 'status line (step running)' 'status line (VBW off)' 'status line (no project)' 'status line (loaded copy)'
}

# ONLY is the selector; SELECTED is "|" and every asked-for label followed by "|".
ONLY="${VBW_BENCH_ONLY:-}"
SELECTED="|"
if [ -n "$ONLY" ]; then
  refused=0 chosen=0 rest="$ONLY|"
  while [ -n "$rest" ]; do
    sel="${rest%%|*}"
    rest="${rest#*|}"
    hit=0
    if [ -n "$sel" ]; then
      while IFS= read -r label; do
        if [[ "$label:" == "$sel"* ]]; then
          hit=1
          case "$SELECTED" in
            *"|$label|"*) ;;
            *)
              SELECTED="$SELECTED$label|"
              chosen=$((chosen + 1)) ;;
          esac
        fi
      done < <(case_labels)
    fi
    if [ "$hit" -eq 0 ]; then
      printf "bench-hooks: VBW_BENCH_ONLY names no case: '%s'\n" "$sel" >&2
      refused=1
    fi
  done
  if [ "$refused" -eq 1 ]; then
    printf "the cases (a selector is the start of one of these labels; end it with ':' to name only that case; join several with '|'):\n" >&2
    case_labels | sed -e 's/^/  /' -e 's/$/:/' >&2
    exit 2
  fi
  printf 'bench-hooks: VBW_BENCH_ONLY runs %s of %s cases\n' "$chosen" "$(case_labels | wc -l | tr -d ' ')"
fi

# selected LABEL: whether the case was asked for (every case, without a selector).
selected() {
  if [ -z "$ONLY" ]; then return 0; fi
  case "$SELECTED" in *"|$1|"*) return 0 ;; esac
  return 1
}

# wanted TEXT: whether an asked-for label holds TEXT (every case, without a
# selector); the records a case needs are built only when one is asked for.
wanted() {
  if [ -z "$ONLY" ]; then return 0; fi
  case "$SELECTED" in *"$1"*) return 0 ;; esac
  return 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# A step that fails under set -e says where, instead of ending the bench silently.
trap 'echo "bench-hooks: stopped at line $LINENO (status $?)" >&2' ERR
hooks_json="$PLUGIN/hooks/hooks.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$work"

# reference_files DIR (R231): the reference program and document, written from the bench's
# own text into DIR: reference.jq (about 25 KB, the size of the shipped Bash guard, built
# of fixed helper definitions and a body that reads $glance, $root, $dir, $open and its
# inputs the way a guard does) and reference.json (a fixed object of about 60 KB). The
# content is deterministic and read from no shipped file and no project file.
reference_files() {
  mkdir -p "$1"
  awk 'BEGIN {
    for (i = 1; i <= 101; i++)
      printf "def h%d($v; $w): if ($v | type) == \"object\" then ($v | keys | map(select(startswith(\"k%d\"))) | length) + $w elif ($v | type) == \"array\" then ($v | map(tostring | length) | add // 0) + %d else ($v | tostring | ascii_downcase | length) end;\n", i, i % 7, i
    print "($glance | fromjson) as $g"
    print "| ([inputs] | .[-2:]) as $in"
    print "| $in[0] as $doc"
    print "| ($in[1] // {}) as $end"
    print "| ($doc.checks // []) as $checks"
    print "| [$checks[] | select((.run | join(\" \") | test(\"^sh \")) and (.files | length) > 0)] as $kept"
    print "| (($root | length) + ($dir | length) + ($open | tonumber)) as $n"
    printf "| [$doc"
    for (i = 1; i <= 101; i += 5) printf ", h%d($doc; $n)", i
    print "] as $parts"
    print "| {schema: ($g.schema // 0), kept: ($kept | length), end: ($end | length), parts: ($parts | map(numbers) | add)}"
  }' > "$1/reference.jq"
  jq -n -c '{schema: 4, protected: ["tests/old.sh"],
    checks: [range(0; 330) | {id: "C\(.)", req: "R\(. % 40)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh", "src/old/\(.).txt"], note: ("check text " * 8)}],
    decisions: [range(0; 60) | {id: "D\(.)", text: ("Old decision \(.) " + ("~" * 300)), at: "2026-01-01T00:00:00Z"}]}' > "$1/reference.json"
}
if [ -n "${VBW_BENCH_REFERENCE_FILES:-}" ]; then
  reference_files "$VBW_BENCH_REFERENCE_FILES"
  exit 0
fi
reference_files "$work/reference"
printf '{"schema": 4}' > "$work/glance.json"
printf '{}' > "$work/end.json"

# cpu_pair INPUT BASELINE HOOK: the mean CPU time in ms of RUNS runs of each
# `sh -c` command, "BASELINE HOOK", alternating call by call so both see the
# same machine. The children's user and system time comes from bash's `times`
# (millisecond resolution), written to a file to stay in this shell.
cpu_pair() {
  local i c log="$work/times.log"
  : > "$log"
  for ((i = 0; i < RUNS; i++)); do
    for c in "$2" "$3"; do
      times >> "$log"
      sh -c "$c" < "$1" > /dev/null 2>&1 || true
      times >> "$log"
    done
  done
  # Each `times` prints the shell's line, then the children's cumulative line.
  awk -v runs="$RUNS" '
    function sec(s) { sub(/s$/, "", s); split(s, p, "m"); return p[1] * 60 + p[2] }
    NR % 2 == 0 { t[++n] = sec($1) + sec($2) }
    END { for (k = 1; k + 1 <= n; k += 2) sum[int((k - 1) / 2) % 2] += t[k + 1] - t[k]
          printf "%.1f %.1f\n", sum[0] * 1000 / runs, sum[1] * 1000 / runs }' "$log"
}

# within COST BUDGET: whether a cost in ms is at or below a budget in ms.
within() { perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$1" "$2"; }

# scaled BUDGET: the budget a case is judged against: the absolute budget at a ratio
# of 1 or less, budget x ratio (one decimal) above it.
scaled() {
  if [ "$SLOW" -eq 1 ]; then perl -e 'printf "%.1f", $ARGV[0] * $ARGV[1]' -- "$1" "$RATIO"; else printf '%s' "$1"; fi
}

# again LABEL FIRST BUDGET: the line printed before a case over its budget is
# measured once more (D517); FIRST is the first measure as the case's line words it.
# The budget it names is the one the case is judged against (scaled above a ratio of 1).
again() { printf '%s: measured again: the first measure gave %s, above the budget of %s ms\n' "$1" "$2" "$(scaled "$3")"; }

# over COST BUDGET: whether a cost is above the budget it is judged against.
over() { ! within "$1" "$(scaled "$2")"; }

# verdict LINE COST BUDGET: print the case's line. Within the absolute budget: the line.
# Above it, at a ratio above 1 and within budget x ratio: the line marked slow, on stdout,
# status unchanged. Otherwise the line with ': OVER' on stderr and status 1.
verdict() {
  if within "$2" "$3"; then
    printf '%s\n' "$1"
  elif [ "$SLOW" -eq 1 ] && within "$2" "$(scaled "$3")"; then
    printf '%s: slow (ratio %s, scaled budget %s ms)\n' "$1" "$RATIO" "$(scaled "$3")"
  else
    printf '%s: OVER\n' "$1" >&2
    status=1
  fi
}

# Measure the platform's sh and jq startup first, before the test records are
# built: above the hook limit, the machine is too busy to judge anything.
read -r startup _ < <(cpu_pair /dev/null "jq -n empty" "jq -n empty")
if perl -e 'exit($ARGV[0] > $ARGV[1] ? 0 : 1)' -- "$startup" "$BUDGET_MS"; then
  printf 'machine too busy to measure: sh and jq startup takes %s ms CPU per call, above the %s ms hook limit; nothing judged\n' "$startup" "$BUDGET_MS"
  exit 0
fi

# The reference (R222): one fixed jq workload, run through sh -c as the hooks are, on
# this machine in this run, before any record is built or case judged: one jq call of the
# guard's shape (R231) over the bench's own program and document.
read -r _ measured < <(cpu_pair /dev/null "jq -n empty" "jq -nc --rawfile glance \"$work/glance.json\" --arg root \"$work\" --arg dir \"$work\" --arg open 0 -f \"$work/reference/reference.jq\" - \"$work/reference/reference.json\" \"$work/end.json\"")
[ -z "${VBW_BENCH_REFERENCE_MS:-}" ] || measured="$VBW_BENCH_REFERENCE_MS"
RATIO=$(perl -e 'printf "%.2f", $ARGV[0] / $ARGV[1]' -- "$measured" "$NOMINAL_MS")
SLOW=0
if perl -e 'exit($ARGV[0] > 1 ? 0 : 1)' -- "$RATIO"; then SLOW=1; fi
printf "reference: %s ms CPU per call; nominal %s ms (an M1 Max Mac and GitHub's macOS runner, %s); ratio %s\n" "$measured" "$NOMINAL_MS" "$NOMINAL_WHEN" "$RATIO"

git -C "$work" init -q
mkdir -p "$work/.vbw"
# A build lease on the record: the interp case is a build agent's command, which
# the guard reads in full. Calls without an agent_type are never held to it.
jq -nc --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema: 4, lease: {run: "build-1", kind: "build", session: "bench", started_at: $t, files: ["src/pay.py"]}, protected: [], checks: []}' > "$work/.vbw/record.json"

# Representative calls: a compound command the guard must read in full (git, a
# heredoc, quotes, a substitution), one it can skip unread, and a file read, and a build agent's program command.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command:
  "git status && npm test -- --watch=false 2>&1 | tail -20; cat <<EOF > notes.md\nhello \"world\" $(date)\nEOF"}}' > "$work/git.json"
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command: "npm test -- --watch=false 2>&1 | tail -20"}}' > "$work/npm.json"
big=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "line %d with \"quotes\" and $(cmd) and git words\n", i }')
jq -nc --arg d "$work" --arg b "$big" '{tool_name: "Bash", cwd: $d, tool_input: {command: ("git add notes.md && cat > notes.md <<'\''EOF'\''\n" + $b + "EOF")}}' > "$work/big.json"
# A build agent running Python from a heredoc on a build lease: the program is read for the files it writes.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, session_id: "bench", agent_id: "x1", agent_type: "workflow-subagent", tool_input: {command:
  "python3 - <<'\''EOF'\''\nimport json\nwith open(\"src/pay.py\", \"w\") as f:\n    json.dump({\"paid\": True}, f)\np = \"src/pay.py\"\nwith open(p, \"w\") as g:\n    g.write(\"x\")\nprint(open(\"src/pay.py\").read())\nEOF"}}' > "$work/interp.json"
jq -nc --arg d "$work" '{tool_name: "Read", cwd: $d, tool_input: {file_path: ($d + "/src/app.js")}}' > "$work/read.json"
# An answered question unrelated to approval: the PostToolUse hook runs after
# every AskUserQuestion and must stay cheap when the answer is not an approval.
jq -nc --arg d "$work" '{hook_event_name: "PostToolUse", tool_name: "AskUserQuestion", cwd: $d,
  tool_input: {questions: [{question: "Which database should the app use?", options: [{label: "SQLite"}, {label: "Postgres"}]}]},
  tool_response: {answers: {"Which database should the app use?": "SQLite"}}}' > "$work/answer.json"

# VBW_BENCH_STEPS=1 (R233): instead of judging cases, print one table of the CPU ms per call
# (cpu_pair's method, RUNS runs) of the steps one Bash guard call is made of, for the git,
# npm, big and interp inputs: sh startup, jq startup, the program compiled alone (the
# hooks.json call's flags over empty inputs), the whole hooks.json call, and the
# reference call. It judges no case and prints no guard line.
if [ "${VBW_BENCH_STEPS:-}" = 1 ]; then
  steps_hook=$(jq -r '[.hooks.PreToolUse[] | select(.matcher as $m | "Bash" | test("^(" + $m + ")$"))][0].hooks[0].command' "$hooks_json")
  steps_compile="jq -nc --rawfile glance /dev/null --arg root \"$work\" --arg dir \"$work\" --arg open 0 -f \"$PLUGIN/hooks/guard-bash.jq\" - /dev/null \"$PLUGIN/hooks/end.json\""
  steps_ref="jq -nc --rawfile glance \"$work/glance.json\" --arg root \"$work\" --arg dir \"$work\" --arg open 0 -f \"$work/reference/reference.jq\" - \"$work/reference/reference.json\" \"$work/end.json\""
  printf 'steps: CPU ms per call over %s runs\n' "$RUNS"
  steps_rows=("sh startup" "jq startup" "program compile" "program run" "reference")
  steps_cells=("" "" "" "" "")
  for input in git npm big interp; do
    read -r _ c0 < <(cpu_pair /dev/null true ":")
    read -r _ c1 < <(cpu_pair /dev/null true "jq -n empty")
    read -r _ c2 < <(cpu_pair /dev/null true "$steps_compile")
    read -r _ c3 < <(cpu_pair "$work/$input.json" true "$steps_hook")
    read -r _ c4 < <(cpu_pair /dev/null true "$steps_ref")
    steps_cells[0]="${steps_cells[0]}	$c0"
    steps_cells[1]="${steps_cells[1]}	$c1"
    steps_cells[2]="${steps_cells[2]}	$c2"
    steps_cells[3]="${steps_cells[3]}	$c3"
    steps_cells[4]="${steps_cells[4]}	$c4"
  done
  {
    printf 'step\tgit\tnpm\tbig\tinterp\n'
    for i in 0 1 2 3 4; do printf '%s%s\n' "${steps_rows[$i]}" "${steps_cells[$i]}"; done
  } | awk -F"\t" '{ printf "%-16s %-6s %-6s %-6s %s\n", $1, $2, $3, $4, $5 }'
  exit 0
fi

# The large project: a record of more than 2 MB in its own folder, the same build
# lease plus a long history (requirements with rules, checks, phases, plans and
# decisions of a shipped milestone, every text padded), keys in the writer's
# order (schema, lease, protected, checks, then the rest). The kernel then rewrites it once
# (vbw decide, a record write), so the file holds the format the kernel writes:
# schema 4 with the protected field, which the guards read without walking the checks.
large="$work/large"
build_large() {
  mkdir -p "$large"
  git -C "$large" init -q
  (cd "$large" && "$PLUGIN/bin/vbw" init > /dev/null)
  jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  ("~" * 5000) as $f
  | "2026-01-01T00:00:00Z" as $at
  | [range(1; 51)] as $n
  | .lease = {run: "build-1", kind: "build", session: "bench", started_at: $t, files: ["src/pay.py"]}
  | .milestone = {id: "M2", title: "New work", status: "active"}
  | .shipped = [{id: "M1", title: "Old work", at: $at}]
  | .requirements = [$n[] | {id: "R\(.)", text: ("Old part \(.) works" + $f), proof: "auto", status: "proven", milestone: "M1",
                              rules: [{text: ("Old rule \(.)" + $f), check: "C\(2 * . - 1)"}, {text: "Old second rule \(.)", check: "C\(2 * .)"}]}]
  | .checks = [$n[] | {id: "C\(2 * . - 1)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]},
                      {id: "C\(2 * .)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}]
  | .phases = [$n[] | {id: "P\(.)", title: "Old phase \(.)", reqs: ["R\(.)"], milestone: "M1",
                        goal: ("Old goal \(.)" + $f), criteria: [("Old criterion \(.)" + $f)], tier: "standard",
                        qa: {result: "pass", tier: "standard", tree: "0000000000000000000000000000000000000000", at: $at}}]
  | .plans = [$n[] as $k | (1, 2) | {id: "P\($k).\(.)", phase: "P\($k)", title: "Old plan \($k).\(.)", reqs: ["R\($k)"],
                                      files: ["src/old/\($k)-\(.).txt"], after: [], status: "done", role: "dev",
                                      tasks: [("Old task \($k).\(.)" + $f)]}]
  | .decisions = [range(1; 121) | {id: "D\(.)", text: ("Old decision \(.)" + $f), at: $at}]
                 + [{id: "D121", text: ("Old long decision" + ("~" * 140000)), at: $at}]
  | .protected = ["tests/old.sh"]
  | {schema, lease, protected, checks} + .' \
    "$large/.vbw/record.json" > "$large/.vbw/edited.json"
  cat "$large/.vbw/edited.json" > "$large/.vbw/record.json"
  rm -f "$large/.vbw/edited.json"
  (cd "$large" && "$PLUGIN/bin/vbw" decide "Benchmark record written by the kernel" > /dev/null)
  printf 'large record: %s bytes\n' "$(wc -c < "$large/.vbw/record.json" | tr -d ' ')"
}
# The large record serves the guards and the status line on it, and the loop case on it.
if wanted ', large record)|' || wanted '|status line (large record)|'; then build_large; fi

# sized N: a project of N checks (one per requirement) in $work/checks-N, its
# history padded in proportion, written once by the kernel (vbw decide).
sized() {
  local n="$1" d="$work/checks-$1"
  mkdir -p "$d"
  git -C "$d" init -q
  (cd "$d" && "$PLUGIN/bin/vbw" init > /dev/null)
  jq --argjson n "$n" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    "2026-01-01T00:00:00Z" as $at
    | [range(1; $n + 1)] as $k
    | .lease = {run: "build-1", kind: "build", session: "bench", started_at: $t, files: ["src/pay.py"]}
    | .milestone = {id: "M2", title: "New work", status: "active"}
    | .shipped = [{id: "M1", title: "Old work", at: $at}]
    | .requirements = [$k[] | {id: "R\(.)", text: "Old part \(.) works", proof: "auto", status: "proven", milestone: "M1",
                                rules: [{text: "Old rule \(.)", check: "C\(.)"}]}]
    | .checks = [$k[] | {id: "C\(.)", req: "R\(.)", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}]
    | .decisions = [{id: "D1", text: ("Old long decision" + ("~" * ($n * 1100))), at: $at}]
    | .protected = ["tests/old.sh"]
    | {schema, lease, protected, checks} + .' "$d/.vbw/record.json" > "$d/.vbw/edited.json"
  cat "$d/.vbw/edited.json" > "$d/.vbw/record.json"
  rm -f "$d/.vbw/edited.json"
  (cd "$d" && "$PLUGIN/bin/vbw" decide "Benchmark record written by the kernel" > /dev/null)
  printf 'record (%s checks): %s bytes, schema %s\n' "$n" "$(wc -c < "$d/.vbw/record.json" | tr -d ' ')" "$(jq -r .schema "$d/.vbw/record.json")"
}
for n in $SIZES; do
  if wanted ", $n checks)|"; then sized "$n"; fi
done

# guards DIR LABEL [INPUTS]: measure every input (default: all but loop) against
# the project at DIR; LABEL is the empty string, or ", large record".
status=0
guards() {
  local dir="$1" label="$2" inputs="${3:-$GUARD_INPUTS}" input tool event hook shell total own line baseline file
  export CLAUDE_PROJECT_DIR="$dir"
  baseline="jq -nc 'input | empty' - \"$dir/.vbw/record.json\" \"$CLAUDE_PLUGIN_ROOT/hooks/end.json\" 2>/dev/null || true"
  for input in $inputs; do
    selected "guard ($input$label)" || continue
    tool=$(jq -r .tool_name "$work/$input.json")
    event=PreToolUse
    [ "$input" != answer ] || event=PostToolUse
    hook=$(jq -r --arg t "$tool" --arg e "$event" '[.hooks[$e][] | select(.matcher as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$hooks_json")
    file="$work/$input.json"
    if [ "$dir" != "$work" ]; then
      file="$work/$input.large.json"
      jq -c --arg o "$work" --arg d "$dir" 'walk(if type == "string" and startswith($o) then $d + .[($o | length):] else . end)' \
        "$work/$input.json" > "$file"
    fi
    read -r shell total < <(cpu_pair "$file" "$baseline" "$hook")
    own=$(perl -e 'printf "%.1f", $ARGV[0] - $ARGV[1]' -- "$total" "$shell")
    if over "$own" "$BUDGET_MS"; then
      again "guard ($input$label)" "$own ms own CPU per call (sh and jq startup $shell ms)" "$BUDGET_MS"
      read -r shell total < <(cpu_pair "$file" "$baseline" "$hook")
      own=$(perl -e 'printf "%.1f", $ARGV[0] - $ARGV[1]' -- "$total" "$shell")
    fi
    line=$(printf 'guard (%s%s): %s ms own CPU per call (sh and jq startup %s ms); budget %s ms' \
      "$input" "$label" "$own" "$shell" "$BUDGET_MS")
    verdict "$line" "$own" "$BUDGET_MS"
  done
}

# statusline DIR LABEL [step]: the status line's CPU per call (the whole process
# tree, startup included) for a session in the project at DIR. With "step" a
# running build's note (R190, .vbw/runtime/step.json) is on disk, and the bench
# fails when the step's end time did not show in the first line.
statusline() {
  local dir="$1" label="$2" cmd total line first errline
  selected "status line$label" || return 0
  # With the cost fields Claude Code sends, so the side file write (R173) is inside the measure.
  jq -nc --arg d "$dir" '{session_id: "bench", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"},
    cost: {total_cost_usd: 1.25}, context_window: {total_input_tokens: 12000, total_output_tokens: 3400, context_window_size: 200000}}' > "$work/statusline.json"
  rm -f "$dir/.vbw/runtime/cost.bench.json"
  # A lease is open (R192, .vbw/runtime/run-open) and Claude Code's list of chats
  # is on disk (<config>/sessions/*.json, one of them the lease's session), so the
  # status line's one jq pass over the list is inside the measure.
  local cfg="$work/chats-config"
  mkdir -p "$dir/.vbw/runtime" "$cfg/sessions"
  : > "$dir/.vbw/runtime/run-open"
  jq -nc '{pid: 101, sessionId: "bench", name: "Payments work", updatedAt: 1760000000000}' > "$cfg/sessions/101.json"
  jq -nc '{pid: 102, sessionId: "bench-two", name: "Other chat", updatedAt: 1760000001000}' > "$cfg/sessions/102.json"
  jq -nc '{pid: 103, sessionId: "bench-three", name: "Docs", updatedAt: 1760000002000}' > "$cfg/sessions/103.json"
  if [ "${3:-}" = step ]; then
    mkdir -p "$dir/.vbw/runtime"
    jq -nc 'def s($n): (now | floor) + $n | todateiso8601;
      {kind: "build", run: "build-1", session: "bench", pid: null, started_at: s(-300), ids: ["P1.1", "P1.2"], doing: "building P1.1, P1.2",
       parts: {done: 1, total: 2}, proof: null, first_end: s(720), end: s(720), late: false}' > "$dir/.vbw/runtime/step.json"
    first=$(CLAUDE_CONFIG_DIR="$cfg" NO_COLOR=1 bash "$PLUGIN/scripts/vbw-statusline.sh" < "$work/statusline.json" 2> /dev/null | head -n 1) || first=""
    # The end is 12 minutes away, so after 23:48 the line says "until around tomorrow HH:MM".
    case "$first" in
      *"1 of 2 · "*" min, until around "[0-9][0-9]:[0-9][0-9]* | *"1 of 2 · "*" min, until around tomorrow "[0-9][0-9]:[0-9][0-9]*) ;;
      *)
        printf 'status line%s: the step was not shown, so the measure left it out\n' "$label" >&2
        printf 'status line%s: first line: %s\n' "$label" "$first" >&2
        if [ -s "$dir/.vbw/runtime/statusline.err" ]; then
          while IFS= read -r errline || [ -n "$errline" ]; do
            printf 'status line%s: statusline.err: %s\n' "$label" "$errline" >&2
          done < "$dir/.vbw/runtime/statusline.err"
        fi
        status=1 ;;
    esac
  fi
  cmd="CLAUDE_CONFIG_DIR='$cfg' NO_COLOR=1 bash '$PLUGIN/scripts/vbw-statusline.sh'"
  read -r _ total < <(cpu_pair "$work/statusline.json" true "$cmd")
  if over "$total" "$STATUS_MS"; then
    again "status line$label" "$total ms CPU per call" "$STATUS_MS"
    read -r _ total < <(cpu_pair "$work/statusline.json" true "$cmd")
  fi
  if ! jq -e '.session == "bench" and .usd == 1.25' "$dir/.vbw/runtime/cost.bench.json" > /dev/null 2>&1; then
    printf 'status line%s: the cost side file was not written, so the measure left the write out\n' "$label" >&2
    status=1
  fi
  rm -f "$dir/.vbw/runtime/cost.bench.json" "$dir/.vbw/runtime/step.json" "$dir/.vbw/runtime/run-open"
  rm -rf "$cfg"
  line=$(printf 'status line%s: %s ms CPU per call; budget %s ms' "$label" "$total" "$STATUS_MS")
  verdict "$line" "$total" "$STATUS_MS"
}

# handback: the setting of `vbw statusline on` in a project that turns VBW off.
handback() {
  local proj="$work/off-project" cfg="$work/off-config" cmd base shell total own line out
  selected 'status line (VBW off)' || return 0
  mkdir -p "$proj/.claude" "$cfg/plugins/cache/vbw-marketplace/vbw"
  git -C "$proj" init -q
  printf '{"enabledPlugins": {"vbw@vbw-marketplace": false}}\n' > "$proj/.claude/settings.json"
  ln -s "$PLUGIN" "$cfg/plugins/cache/vbw-marketplace/vbw/0.0.0"
  printf '#!/bin/sh\necho "earlier status line (bench)"\n' > "$work/earlier.sh"
  jq -nc --arg c "sh '$work/earlier.sh'" '{statusLine: {type: "command", command: $c}}' > "$cfg/settings.json"
  CLAUDE_CONFIG_DIR="$cfg" "$PLUGIN/bin/vbw" statusline on > /dev/null
  jq -r '.statusLine.command' "$cfg/settings.json" > "$work/setting.sh"
  jq -nc --arg d "$proj" '{session_id: "bench", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"},
    cost: {total_cost_usd: 1.25}, context_window: {total_input_tokens: 12000, total_output_tokens: 3400, context_window_size: 200000}}' > "$work/handback.json"
  cmd="cd '$proj' && CLAUDE_CONFIG_DIR='$cfg' NO_COLOR=1 sh '$work/setting.sh'"
  out=$(sh -c "$cmd" < "$work/handback.json" 2> /dev/null || true)
  if [ "$out" != "earlier status line (bench)" ]; then
    printf 'status line (VBW off): the earlier status line did not show, so the measure left the hand-back out\n' >&2
    status=1
    return 0
  fi
  # The platform's part of the hand-back, which VBW cannot remove: one bash for
  # the setting, one jq to read the settings and the input, one sh to run the
  # earlier command text (D356), and the earlier status line itself. VBW's own
  # cost is the call minus that.
  printf "sh '%s'\n" "$work/earlier.sh" > "$work/earlier-setting.sh"
  base="cd '$proj' && bash -c : && jq -n empty && sh -c : && sh '$work/earlier-setting.sh'"
  read -r shell total < <(cpu_pair "$work/handback.json" "$base" "$cmd")
  own=$(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' -- "$shell" "$total")
  if over "$own" "$HANDBACK_MS"; then
    again "status line (VBW off)" "$own ms own CPU per call (a bash, a jq and a sh startup and the earlier status line: $shell ms)" "$HANDBACK_MS"
    read -r shell total < <(cpu_pair "$work/handback.json" "$base" "$cmd")
    own=$(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' -- "$shell" "$total")
  fi
  line=$(printf 'status line (VBW off): %s ms own CPU per call (a bash, a jq and a sh startup and the earlier status line: %s ms); budget %s ms' "$own" "$shell" "$HANDBACK_MS")
  verdict "$line" "$own" "$HANDBACK_MS"
}

# noproject: the same setting in a git folder with no .vbw at or above it (R224).
noproject() {
  local root cfg="$work/noproject-config" proj cmd base shell total own line out
  selected 'status line (no project)' || return 0
  root="$(mktemp -d)"
  proj="$root/folder"
  mkdir -p "$proj" "$cfg/plugins/cache/vbw-marketplace/vbw"
  git -C "$proj" init -q
  ln -s "$PLUGIN" "$cfg/plugins/cache/vbw-marketplace/vbw/0.0.0"
  printf '#!/bin/sh\necho "earlier status line (bench)"\n' > "$work/np-earlier.sh"
  jq -nc --arg c "sh '$work/np-earlier.sh'" '{statusLine: {type: "command", command: $c}}' > "$cfg/settings.json"
  CLAUDE_CONFIG_DIR="$cfg" "$PLUGIN/bin/vbw" statusline on > /dev/null
  jq -r '.statusLine.command' "$cfg/settings.json" > "$work/np-setting.sh"
  jq -nc --arg d "$proj" '{session_id: "bench", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"},
    cost: {total_cost_usd: 1.25}, context_window: {total_input_tokens: 12000, total_output_tokens: 3400, context_window_size: 200000}}' > "$work/noproject.json"
  cmd="cd '$proj' && CLAUDE_CONFIG_DIR='$cfg' NO_COLOR=1 sh '$work/np-setting.sh'"
  out=$(sh -c "$cmd" < "$work/noproject.json" 2> /dev/null || true)
  if [ "$out" != "earlier status line (bench)" ]; then
    printf 'status line (no project): the earlier status line did not show, so the measure left the hand-back out\n' >&2
    status=1
    rm -rf "$root"
    return 0
  fi
  printf "sh '%s'\n" "$work/np-earlier.sh" > "$work/np-earlier-setting.sh"
  base="cd '$proj' && bash -c : && jq -n empty && sh -c : && sh '$work/np-earlier-setting.sh'"
  read -r shell total < <(cpu_pair "$work/noproject.json" "$base" "$cmd")
  own=$(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' -- "$shell" "$total")
  if over "$own" "$HANDBACK_MS"; then
    again "status line (no project)" "$own ms own CPU per call (a bash, a jq and a sh startup and the earlier status line: $shell ms)" "$HANDBACK_MS"
    read -r shell total < <(cpu_pair "$work/noproject.json" "$base" "$cmd")
    own=$(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' -- "$shell" "$total")
  fi
  rm -rf "$root"
  line=$(printf 'status line (no project): %s ms own CPU per call (a bash, a jq and a sh startup and the earlier status line: %s ms); budget %s ms' "$own" "$shell" "$HANDBACK_MS")
  verdict "$line" "$own" "$HANDBACK_MS"
}

# loaded: the setting in a session that loaded the bench's plugin, next to a stand-in release.
loaded() {
  local cfg="$work/loaded-config" cmd total line out ver inst
  selected 'status line (loaded copy)' || return 0
  inst="$cfg/plugins/cache/vbw-marketplace/vbw/0.0.0/scripts"
  mkdir -p "$inst" "$work/loaded-env"
  printf '#!/bin/sh\necho "installed stand-in (bench)"\n' > "$inst/vbw-statusline.sh"
  jq -nc --arg d "$work" '{hook_event_name: "SessionStart", source: "startup", session_id: "loaded-bench", cwd: $d}' > "$work/loaded-start.json"
  CLAUDE_CONFIG_DIR="$cfg" CLAUDE_PLUGIN_DATA="$work/loaded-data/vbw-inline" CLAUDE_ENV_FILE="$work/loaded-env/env.sh" \
    sh -c "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$hooks_json")" < "$work/loaded-start.json" > /dev/null 2>&1 || true
  CLAUDE_CONFIG_DIR="$cfg" "$PLUGIN/bin/vbw" statusline on > /dev/null
  jq -r '.statusLine.command' "$cfg/settings.json" > "$work/loaded-setting.sh"
  jq -nc --arg d "$work" '{session_id: "loaded-bench", workspace: {project_dir: $d}, cwd: $d, model: {display_name: "Opus"},
    cost: {total_cost_usd: 1.25}, context_window: {total_input_tokens: 12000, total_output_tokens: 3400, context_window_size: 200000}}' > "$work/loaded.json"
  cmd="cd '$work' && CLAUDE_CONFIG_DIR='$cfg' NO_COLOR=1 sh '$work/loaded-setting.sh'"
  ver=$(jq -r .version "$PLUGIN/.claude-plugin/plugin.json")
  out=$(sh -c "$cmd" < "$work/loaded.json" 2> /dev/null || true)
  if [[ "$out" != *"VBW $ver"* ]]; then
    printf 'status line (loaded copy): the loaded copy did not show (VBW %s expected), so the measure left it out\n' "$ver" >&2
    status=1
    return 0
  fi
  read -r _ total < <(cpu_pair "$work/loaded.json" true "$cmd")
  if over "$total" "$STATUS_MS"; then
    again "status line (loaded copy)" "$total ms CPU per call" "$STATUS_MS"
    read -r _ total < <(cpu_pair "$work/loaded.json" true "$cmd")
  fi
  rm -f "$work/.vbw/runtime/cost.loaded-bench.json"
  line=$(printf 'status line (loaded copy): %s ms CPU per call; budget %s ms' "$total" "$STATUS_MS")
  verdict "$line" "$total" "$STATUS_MS"
}

guards "$work" ""
guards "$large" ", large record"
# A loop on and no lease: the main session's push, judged like the others.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, session_id: "bench", tool_input: {command: "git push origin main"}}' > "$work/loop.json"
loopproj() {
  local d="$1" src="$2"
  mkdir -p "$d/.vbw"
  git -C "$d" init -q
  jq -c --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" 'del(.lease) | .loop = {items: [{id: "T1", text: "Bench", proof: "auto", status: "waiting"}], ceiling: null, session: "bench", started_at: $t, baseline: {}}' "$src/.vbw/record.json" > "$d/.vbw/record.json"
  # The large record is rewritten by the kernel (its glance); the small one stands as written, like the other small cases.
  [ "$src" = "$work" ] || (cd "$d" && "$PLUGIN/bin/vbw" decide "Benchmark record written by the kernel" > /dev/null)
}
if selected 'guard (loop)'; then loopproj "$work/loop-small" "$work"; fi
if selected 'guard (loop, large record)'; then loopproj "$work/loop-large" "$large"; fi
guards "$work/loop-small" "" loop
guards "$work/loop-large" ", large record" loop
for n in $SIZES; do guards "$work/checks-$n" ", $n checks"; done
statusline "$work" ""
statusline "$large" " (large record)"
statusline "$work" " (step running)" step
handback
noproject
loaded
exit $status
