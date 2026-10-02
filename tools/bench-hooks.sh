#!/usr/bin/env bash
# Hook cost budget (build plan M3, K20): the PreToolUse guard runs before
# every tool call. Runs the hooks.json command the way Claude Code does (sh -c,
# JSON on stdin, CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR set) and measures the
# CPU time (user + system) of the whole process tree per call, averaged over
# RUNS calls. The budget applies to VBW's own cost: the hook's CPU time minus
# that of the same `sh -c jq` with an empty program. Shell and jq startup are the
# platform's (about 8 ms of CPU on a Mac), paid by any hook, and not ours to
# remove.
# CPU time, not wall-clock time: time spent waiting for a busy machine is not
# the hook's work, so other load on the machine cannot fail the budget, while
# a real regression (an added subprocess, work that grows with the input, as
# the 20 KB heredoc case checks) costs CPU on every call.
# VBW_BENCH_RUNS and VBW_BENCH_PLUGIN_ROOT override the runs and the plugin (tests).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET_MS="${VBW_HOOK_BUDGET_MS:-8}"
RUNS="${VBW_BENCH_RUNS:-100}"
PLUGIN="${VBW_BENCH_PLUGIN_ROOT:-$ROOT/plugin}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
hooks_json="$PLUGIN/hooks/hooks.json"
export CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$work"

git -C "$work" init -q
mkdir -p "$work/.vbw" && printf '{}' > "$work/.vbw/record.json"

# Representative calls: a compound command the guard must read in full (git, a
# heredoc, quotes, a substitution), one it can skip unread, and a file read.
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command:
  "git status && npm test -- --watch=false 2>&1 | tail -20; cat <<EOF > notes.md\nhello \"world\" $(date)\nEOF"}}' > "$work/git.json"
jq -nc --arg d "$work" '{tool_name: "Bash", cwd: $d, tool_input: {command: "npm test -- --watch=false 2>&1 | tail -20"}}' > "$work/npm.json"
big=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "line %d with \"quotes\" and $(cmd) and git words\n", i }')
jq -nc --arg d "$work" --arg b "$big" '{tool_name: "Bash", cwd: $d, tool_input: {command: ("git add notes.md && cat > notes.md <<'\''EOF'\''\n" + $b + "EOF")}}' > "$work/big.json"
jq -nc --arg d "$work" '{tool_name: "Read", cwd: $d, tool_input: {file_path: ($d + "/src/app.js")}}' > "$work/read.json"

# cpu INPUT ARGV...: the mean CPU time in ms of RUNS runs of ARGV (perl's
# times: the children's user and system time, including their own children).
cpu() {
  perl -e '
    my ($in, $runs, @cmd) = @ARGV;
    open(my $null, ">", "/dev/null") or die;
    my @a = times;
    for (1 .. $runs) {
      open(STDIN, "<", $in) or die; open(my $out, ">&", \*STDOUT) or die; open(STDOUT, ">&", $null) or die;
      system { $cmd[0] } @cmd;
      open(STDOUT, ">&", $out) or die;
    }
    my @b = times;
    printf "%.1f\n", (($b[2] - $a[2]) + ($b[3] - $a[3])) * 1000 / $runs;
  ' "$1" "$RUNS" "${@:2}"
}

baseline="jq -nc 'input | empty' - \"$CLAUDE_PROJECT_DIR/.vbw/record.json\" \"$CLAUDE_PLUGIN_ROOT/hooks/end.json\" 2>/dev/null || true"
status=0
for input in git npm big read; do
  tool=$(jq -r .tool_name "$work/$input.json")
  hook=$(jq -r --arg t "$tool" '[.hooks.PreToolUse[] | select(.matcher as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$hooks_json")
  shell=$(cpu "$work/$input.json" sh -c "$baseline")
  total=$(cpu "$work/$input.json" sh -c "$hook")
  own=$(perl -e 'printf "%.1f", $ARGV[0] - $ARGV[1]' -- "$total" "$shell")
  if perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$own" "$BUDGET_MS"; then
    printf 'guard (%s): %s ms own CPU per call (budget %s ms; in all %s ms, of which sh and jq startup %s ms)\n' \
      "$input" "$own" "$BUDGET_MS" "$total" "$shell"
  else
    printf 'guard (%s): %s ms own CPU per call is OVER the %s ms budget (in all %s ms)\n' \
      "$input" "$own" "$BUDGET_MS" "$total" >&2
    status=1
  fi
done
exit $status
