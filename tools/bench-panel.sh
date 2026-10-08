#!/usr/bin/env bash
# Panel cost budget (R55): the panel (plugin/hooks/panel.js) runs inside Claude
# Code for the whole session, so each refresh must stay cheap. tools/bench-panel.mjs
# mounts it on the test stand-in for Claude Code and measures the CPU time
# (user + system, not time spent waiting) of one refresh, averaged over
# VBW_BENCH_RUNS (default 200):
#   - tick, nothing changed: the timer fires, the files are only checked;
#   - refresh, state changed: a file changed, is read, and the panel redraws.
# The stand-in's own work is inside the numbers, so they are an upper bound.
# Measured on a developer Mac (node 22): about 0.02 ms and 0.04 ms. The budget
# is VBW_PANEL_BUDGET_MS per refresh (default 0.5, about 12x headroom for a
# loaded machine); a real regression (reading every file on every tick, a
# subprocess, a redraw per tick) costs several times more than that.
# CI sets a looser value for its slower machines. Needs node; skips without it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUDGET_MS="${VBW_PANEL_BUDGET_MS:-0.5}"

if ! command -v node > /dev/null 2>&1; then
  echo "node not installed; skipping the panel cost budget" >&2
  exit 0
fi

out="$(node "$ROOT/tools/bench-panel.mjs")"
tick="$(printf '%s\n' "$out" | awk '$1 == "tick" { print $2 }')"
refresh="$(printf '%s\n' "$out" | awk '$1 == "refresh" { print $2 }')"
sound="$(printf '%s\n' "$out" | awk '$1 == "sound" { print $2 }')"
glance="$(printf '%s\n' "$out" | awk '$1 == "glance" { print $2 }')"
whats_next="$(printf '%s\n' "$out" | awk '$1 == "whats-next" { print $2 }')"
[ -n "$whats_next" ] && [ -n "$glance" ] && [ -n "$sound" ] && [ -n "$tick" ] && [ -n "$refresh" ] || { echo "bench-panel: the driver printed no measurement: $out" >&2; exit 1; }

printf 'tick, nothing changed: %s ms CPU\n' "$tick"
printf 'refresh, state changed: %s ms CPU\n' "$refresh"
printf 'sound, need raised: %s ms CPU\n' "$sound"
printf 'refresh with cost and estimates: %s ms CPU\n' "$glance"
printf "refresh with what's next: %s ms CPU\n" "$whats_next"
printf 'budget: %s ms\n' "$BUDGET_MS"

status=0
for v in "$tick" "$refresh" "$sound" "$glance" "$whats_next"; do
  perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$v" "$BUDGET_MS" || status=1
done
[ "$status" -eq 0 ] || echo "bench-panel: a refresh is over the budget of $BUDGET_MS ms" >&2
exit "$status"
