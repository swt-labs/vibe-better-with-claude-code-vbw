#!/usr/bin/env bash
# Hook latency budget (build plan M3, K20): the PreToolUse guard runs before
# every tool call. Runs the hooks.json command the way Claude Code does (sh -c,
# JSON on stdin, CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR set) and times it with
# perl's HiRes clock. The budget applies to VBW's own cost: the p95 of the hook
# minus the median of the same `sh -c jq` with an empty program, measured in the
# same run. Shell and jq startup are the platform's (about 4 ms on Linux, 9 ms on
# a Mac), paid by any hook, and not ours to remove.
# The budget exists to catch regressions: an added subprocess costs 2 ms or more,
# and the 20 KB heredoc case catches work that grows faster than the input.
# Run serially, never inside the parallel test run, where timings mean nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET_MS="${VBW_HOOK_BUDGET_MS:-8}"
RUNS=40
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
hooks_json="$ROOT/plugin/hooks/hooks.json"
export CLAUDE_PLUGIN_ROOT="$ROOT/plugin" CLAUDE_PROJECT_DIR="$work"

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

# timing PERCENTILE INPUT ARGV...: that percentile of RUNS runs, in ms, as the
# best of three rounds: a round disturbed by other work on the machine is
# discarded, while a real regression slows every round.
timing() {
  perl -MTime::HiRes=time -e '
    my ($pct, $in, $runs, @cmd) = @ARGV; my $best;
    open(my $null, ">", "/dev/null") or die;
    for my $round (1 .. 3) {
      my @t;
      for (1 .. $runs) {
        open(STDIN, "<", $in) or die; open(my $out, ">&", \*STDOUT) or die; open(STDOUT, ">&", $null) or die;
        my $s = time; system { $cmd[0] } @cmd; push @t, (time - $s) * 1000;
        open(STDOUT, ">&", $out) or die;
      }
      @t = sort { $a <=> $b } @t;
      my $v = $t[int($runs * $pct / 100) - 1];
      $best = $v if !defined $best || $v < $best;
    }
    printf "%.1f\n", $best;
  ' "$1" "$2" "$RUNS" "${@:3}"
}

shell=$(timing 50 "$work/npm.json" sh -c "jq -nc 'input | empty' - \"$CLAUDE_PROJECT_DIR/.vbw/record.json\" \"$CLAUDE_PLUGIN_ROOT/hooks/end.json\" 2>/dev/null || true")
status=0
for input in git npm big read; do
  tool=$(jq -r .tool_name "$work/$input.json")
  hook=$(jq -r --arg t "$tool" '[.hooks.PreToolUse[] | select(.matcher as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$hooks_json")
  p95=$(timing 95 "$work/$input.json" sh -c "$hook")
  own=$(perl -e 'printf "%.1f", $ARGV[0] - $ARGV[1]' "$p95" "$shell")
  if perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' "$own" "$BUDGET_MS"; then
    printf 'guard (%s): %s ms own cost at p95 (budget %s ms; end to end %s ms, of which sh and jq startup %s ms)\n' \
      "$input" "$own" "$BUDGET_MS" "$p95" "$shell"
  else
    printf 'guard (%s): %s ms own cost at p95 is OVER the %s ms budget (end to end %s ms)\n' \
      "$input" "$own" "$BUDGET_MS" "$p95" >&2
    status=1
  fi
done
exit $status
