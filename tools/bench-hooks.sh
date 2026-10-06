#!/usr/bin/env bash
# Hook cost budget (build plan M3, K20): the PreToolUse guard runs before
# every tool call. Runs the hooks.json command the way Claude Code does (sh -c,
# JSON on stdin, CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR set) and measures the
# CPU time (user + system) of the whole process tree per call, averaged over
# RUNS calls. VBW's own cost is the hook's CPU time minus that of the same
# `sh -c jq` with an empty program: shell and jq startup are the platform's
# (about 8 ms of CPU on an idle Mac), paid by any hook, and not ours to remove.
# The budget: VBW's own CPU per call is within VBW_HOOK_BUDGET_MS (default 8),
# or within VBW_HOOK_BUDGET times that startup (default 1.0x).
# - CPU time, not wall-clock time: waiting for a busy machine is not the hook's
#   work.
# - The relative bound covers a loaded machine: processes run on slower cores,
#   so startup and the guard's own cost grow together (7.7 to 15.5 ms of
#   startup on one Mac, the guard staying near 0.8x). It cannot stand alone:
#   platforms differ in startup (3.4 ms on a Linux CI runner, the guard 2.2x),
#   so the absolute bound covers a quiet machine of any platform.
# A real regression still shows: an added subprocess costs about one startup
# more, and the 20 KB heredoc case catches work that grows faster than the input.
# VBW_BENCH_RUNS and VBW_BENCH_PLUGIN_ROOT override the runs and the plugin (tests).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET="${VBW_HOOK_BUDGET:-1.0}"
BUDGET_MS="${VBW_HOOK_BUDGET_MS:-8}"
RUNS="${VBW_BENCH_RUNS:-100}"
PLUGIN="${VBW_BENCH_PLUGIN_ROOT:-$ROOT/plugin}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# A step that fails under set -e says where, instead of ending the bench silently.
trap 'echo "bench-hooks: stopped at line $LINENO (status $?)" >&2' ERR
hooks_json="$PLUGIN/hooks/hooks.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$work"

git -C "$work" init -q
mkdir -p "$work/.vbw"
# A build lease on the record: the interp case is a build agent's command, which
# the guard reads in full. Calls without an agent_type are never held to it.
jq -nc --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{lease: {run: "build-1", kind: "build", session: "bench", started_at: $t, files: ["src/pay.py"]}}' > "$work/.vbw/record.json"

# Representative calls: a compound command the guard must read in full (git, a
# heredoc, quotes, a substitution), one it can skip unread, and a file read, and a build agent's program command.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command:
  "git status && npm test -- --watch=false 2>&1 | tail -20; cat <<EOF > notes.md\nhello \"world\" $(date)\nEOF"}}' > "$work/git.json"
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command: "npm test -- --watch=false 2>&1 | tail -20"}}' > "$work/npm.json"
big=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "line %d with \"quotes\" and $(cmd) and git words\n", i }')
jq -nc --arg d "$work" --arg b "$big" '{tool_name: "Bash", cwd: $d, tool_input: {command: ("git add notes.md && cat > notes.md <<'\''EOF'\''\n" + $b + "EOF")}}' > "$work/big.json"
# A build agent running Python from a heredoc on a build lease: the program is read for the files it writes.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, session_id: "bench", agent_id: "x1", agent_type: "workflow-subagent", tool_input: {command:
  "python3 - <<'\''EOF'\''\nimport json\nwith open(\"src/pay.py\", \"w\") as f:\n    json.dump({\"paid\": True}, f)\nprint(open(\"src/pay.py\").read())\nEOF"}}' > "$work/interp.json"
jq -nc --arg d "$work" '{tool_name: "Read", cwd: $d, tool_input: {file_path: ($d + "/src/app.js")}}' > "$work/read.json"
# An answered question unrelated to approval: the PostToolUse hook runs after
# every AskUserQuestion and must stay cheap when the answer is not an approval.
jq -nc --arg d "$work" '{hook_event_name: "PostToolUse", tool_name: "AskUserQuestion", cwd: $d,
  tool_input: {questions: [{question: "Which database should the app use?", options: [{label: "SQLite"}, {label: "Postgres"}]}]},
  tool_response: {answers: {"Which database should the app use?": "SQLite"}}}' > "$work/answer.json"

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

baseline="jq -nc 'input | empty' - \"$CLAUDE_PROJECT_DIR/.vbw/record.json\" \"$CLAUDE_PLUGIN_ROOT/hooks/end.json\" 2>/dev/null || true"
status=0
for input in git npm big interp read answer; do
  tool=$(jq -r .tool_name "$work/$input.json")
  event=PreToolUse
  [ "$input" != answer ] || event=PostToolUse
  hook=$(jq -r --arg t "$tool" --arg e "$event" '[.hooks[$e][] | select(.matcher as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$hooks_json")
  read -r shell total < <(cpu_pair "$work/$input.json" "$baseline" "$hook")
  own=$(perl -e 'printf "%.1f", $ARGV[0] - $ARGV[1]' -- "$total" "$shell")
  ratio=$(perl -e 'printf "%.2f", $ARGV[1] > 0 ? $ARGV[0] / $ARGV[1] : 99' -- "$own" "$shell")
  line=$(printf 'guard (%s): %s ms own CPU per call, %sx the platform'"'"'s sh and jq startup (%s ms); budget %s ms or %sx' \
    "$input" "$own" "$ratio" "$shell" "$BUDGET_MS" "$BUDGET")
  if perl -e 'exit($ARGV[0] <= $ARGV[1] || $ARGV[2] <= $ARGV[3] ? 0 : 1)' -- "$own" "$BUDGET_MS" "$ratio" "$BUDGET"; then
    printf '%s\n' "$line"
  else
    printf '%s: OVER\n' "$line" >&2
    status=1
  fi
done
exit $status
