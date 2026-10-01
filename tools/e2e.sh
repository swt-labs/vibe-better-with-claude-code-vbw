#!/usr/bin/env bash
# End-to-end run of the VBW lifecycle on a fixture (build plan M4, K22): real
# headless Claude Code sessions, the v2 plugin, auto mode, sandbox on.
#
#   tools/e2e.sh FIXTURE [MODEL]        (MODEL defaults to sonnet)
#
# Drives the loop the /vbw:vibe router will drive: ask `vbw next`; for plan,
# build and fix open a run lease, start the workflow in a headless session,
# close the lease; prove after every run; at the approve gate act as the user
# (vbw approve); stop at ship or at any other human gate. A fixture's optional
# break.sh runs once at the first ship (a regression), and the loop continues,
# so the fix path is exercised too. Prints a summary with the cost per session;
# the project stays in $TMPDIR for inspection.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Never the user's own Claude setup: v2's SessionStart removes VBW 1 command
# copies from the config dir it runs with (K15). Use an isolated, logged-in one.
: "${VBW_TEST_CLAUDE_CONFIG_DIR:?set VBW_TEST_CLAUDE_CONFIG_DIR to an isolated, logged-in Claude config dir}"
[ "$VBW_TEST_CLAUDE_CONFIG_DIR" != "$HOME/.claude" ] || { echo "VBW_TEST_CLAUDE_CONFIG_DIR must not be ~/.claude" >&2; exit 2; }
export CLAUDE_CONFIG_DIR="$VBW_TEST_CLAUDE_CONFIG_DIR"
fixture="${1:?usage: tools/e2e.sh FIXTURE [MODEL]}"
model="${2:-sonnet}"
src="$ROOT/tools/e2e/$fixture"
[ -f "$src/spec.md" ] || { echo "no fixture $src/spec.md" >&2; exit 2; }
VBW="$ROOT/plugin/bin/vbw"

work=$(mktemp -d "${TMPDIR:-/tmp}/vbw-e2e-$fixture.XXXXXX")
cd "$work"
git init -q
git config user.email e2e@vbw.local
git config user.name "VBW e2e"
[ -d "$src/seed" ] && cp -R "$src/seed/." .
printf '# %s\n' "$fixture" > README.md
git add -A && git commit -qm "chore: seed"
"$VBW" init > /dev/null
cp "$src/spec.md" .vbw/spec.md
"$VBW" spec sync > /dev/null
git add -A && git commit -qm "chore(vbw): spec"

settings='{"enabledPlugins":{"vbw@vbw-marketplace":false},"enableWorkflows":true,"sandbox":{"enabled":true}}'
log="$work.log"
: > "$log"
total=0
broke=0

# workflow NAME ARGS_JSON: run one workflow in a headless session.
workflow() {
  local name="$1" args="$2" out cost
  out="$work.$name.$$.$RANDOM.json"
  local ask="Run the VBW $name workflow now: call the Workflow tool with name vbw:$name"
  [ "$args" = "null" ] || ask="$ask and args $args (a JSON object, not a string)"
  claude -p --model "$model" --permission-mode auto --max-turns 12 --plugin-dir "$ROOT/plugin" \
    --settings "$settings" --allowedTools "Workflow(vbw:$name)" --output-format json \
    "$ask. Wait for it to finish, then reply with its returned result as JSON, verbatim." < /dev/null > "$out" 2>> "$log" || true
  cost=$(jq -r '.total_cost_usd // 0' "$out" 2> /dev/null || echo 0)
  total=$(perl -e 'printf "%.4f", $ARGV[0] + $ARGV[1]' "$total" "$cost")
  printf '  %-6s %s  $%s  %s\n' "$name" "$args" "$cost" "$(jq -c '.result // "no result" | (fromjson? // .)' "$out" 2> /dev/null | cut -c1-300)"
}

for step in $(seq 1 15); do
  next=$("$VBW" next --json)
  action=$(printf '%s' "$next" | jq -r .action)
  printf '%2d. next: %s\n' "$step" "$(printf '%s' "$next" | jq -r '"\(.action): \(.instruction)"')"
  case "$action" in
    plan)
      "$VBW" run start plan > /dev/null
      workflow plan null
      "$VBW" run end > /dev/null
      ;;
    approve)
      "$VBW" show contract | sed 's/^/     /'
      "$VBW" approve > /dev/null
      git add -A && git commit -qm "chore(vbw): approve the contract" || true
      ;;
    build)
      ids=$(printf '%s' "$next" | jq -r '.detail.plans | join(" ")')
      # shellcheck disable=SC2086 # plan ids are single words
      "$VBW" run start build $ids > /dev/null
      workflow build "$(printf '%s' "$next" | jq -c '{plans: .detail.plans}')"
      "$VBW" run end > /dev/null
      "$VBW" prove > /dev/null || true
      ;;
    fix)
      ids=$(printf '%s' "$next" | jq -r '.detail.fixes // [] | join(" ")')
      [ -n "$ids" ] || { echo "     a fix without fix items (rejected human requirement): stopping"; break; }
      # shellcheck disable=SC2086 # fix ids are single words
      "$VBW" run start fix $ids > /dev/null
      workflow fix "$(printf '%s' "$next" | jq -c '{fixes: .detail.fixes}')"
      "$VBW" run end > /dev/null
      "$VBW" prove > /dev/null || true
      ;;
    prove)
      "$VBW" prove | sed 's/^/     /' || true
      ;;
    ship)
      if [ -f "$src/break.sh" ] && [ $broke -eq 0 ]; then
        broke=1
        echo "     injecting the fixture's regression (break.sh)"
        sh "$src/break.sh"
        git add -A && git commit -qm "chore: an unrelated edit" || true
        continue
      fi
      break
      ;;
    *) echo "     a human gate: stopping"; break ;;
  esac
done

echo "final: $("$VBW" next)"
"$VBW" show roadmap | sed 's/^/  /'
git log -12 --format='  %h %s %(trailers:key=VBW-Plan,valueonly,separator=%x2C)'
echo "session cost: \$$total (workflow agents' own usage is in the session transcripts)"
echo "project: $work   log: $log"
[ "$action" = ship ]
