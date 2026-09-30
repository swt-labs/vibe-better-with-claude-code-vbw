#!/usr/bin/env bash
# Direct baseline runner, for plugins that cannot run under `claude plugin eval`
# (its sandbox is always on when Bash is granted, and v1 VBW fails under the
# sandbox: ledger D296).
#
#   direct.sh vbw|plain <case> <workdir> [model]
#
# Arm "vbw" uses the installed VBW plugin (what users run) and prefixes the
# request with the case's v1 slash command. Arm "plain" disables it and sends
# the bare request. After the run it grades by executing the case's check
# script in the workspace, and prints one JSON line with the outcome and cost.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
arm="${1:?arm: vbw|plain}"; case_name="${2:?case}"; work="${3:?workdir}"; model="${4:-sonnet}"
case_dir="$HERE/cases/$case_name"
meta() { sed -n "s/^$1=//p" "$case_dir/case.meta"; }

mkdir -p "$work"
ws="$(mktemp -d "$work/$arm-$case_name.XXXXXX")"
seed="$(mktemp -d "$work/seed.XXXXXX")"
fixture_dir="$HERE/fixtures/$(meta fixture)"
request="$(cat "$case_dir/request.txt")"

if [ "$arm" = "vbw" ]; then
  plugin_json='{}'
  cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
  installed="$(ls -1 "$cache" 2>/dev/null | sort -V | tail -1)"
  [ -n "$installed" ] || { echo "no installed VBW under $cache" >&2; exit 2; }
  # The fixture seeds .vbw-planning/ when v1-defaults.json sits beside it.
  cp "$cache/$installed/config/defaults.json" "$seed/v1-defaults.json"
  request="$(meta v1_command) $request"
else
  plugin_json='{"enabledPlugins":{"vbw@vbw-marketplace":false}}'
fi

# Seed the workspace from outside it, so the fixture never commits itself. The
# fixture's cache-link step is for `claude plugin eval` only and is skipped here.
cp "$fixture_dir/fixture.sh" "$seed/fixture.sh"
(cd "$ws" && VBW_BASELINE_NO_CACHE_LINK=1 bash "$seed/fixture.sh" >/dev/null)
rm -rf "$seed"

start=$(date +%s)
(cd "$ws" && claude -p --model "$model" --settings "$plugin_json" \
  --allowedTools Bash Write Edit --max-turns "$(meta max_turns)" \
  --output-format json "$request" < /dev/null > "$ws/.result.json" 2> "$ws/.stderr") || true
elapsed=$(( $(date +%s) - start ))

check_ok=false
(cd "$ws" && bash "$case_dir/check.sh" >/dev/null 2>&1) && check_ok=true

jq -c --arg arm "$arm" --arg case "$case_name" --arg model "$model" --arg ws "$ws" \
  --argjson ok "$check_ok" --argjson elapsed "$elapsed" --arg installed "${installed:-}" \
  '{arm: $arm, case: $case, model: $model, installed_vbw: $installed, check_passed: $ok,
    cost_usd: .total_cost_usd, turns: .num_turns, wall_s: $elapsed, workspace: $ws}' "$ws/.result.json"
