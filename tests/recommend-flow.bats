#!/usr/bin/env bats
# R123 (decision D205; L1): after vbw ship succeeds inside /vbw:vibe, and
# whenever the user asks what to do next, VBW runs the Architect once through
# the recommending workflow (its model and effort from the profile, a reply
# schema) and the kernel stores what it returns (vbw recommend). The
# Architect works only from the record; with nothing open nothing is invented
# and no Architect runs; a failure is one line and changes nothing. The
# workflow runs under node with a stubbed runtime (tests/helpers/run-workflow.js:
# no model is called); the skills' and the Architect's parts are their text.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/recommending.js"
SKILL="$PLUGIN_ROOT/skills/whats-next/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
ARCHITECT="$PLUGIN_ROOT/agents/architect.md"
EFFORTS="$PLUGIN_ROOT/lib/efforts.json"
DOC="$REPO_ROOT/docs/whats-next.md"
README="$REPO_ROOT/README.md"

SUMMARY='{"milestone": {"id": "M3", "title": "Checkout", "status": "active"},
  "open": [{"id": "R7", "text": "A customer gets a receipt", "proof": "auto", "status": "open"}],
  "run": null,
  "todos": [{"id": "T4", "text": "Refunds", "sort": "next", "size": "small"}, {"id": "T9", "text": "Gift cards", "sort": "later", "size": "large"}, {"id": "T2", "text": "Dark mode"}]}'
EMPTY='{"milestone": {"id": "M3", "title": "Checkout", "status": "shipped"}, "open": [], "run": null, "todos": []}'
PICK='{"top": {"text": "Refunds", "reason": "Customers ask for it most.", "size": "small", "source": "T4"}, "runners": [{"text": "Gift cards", "size": "large", "source": "T9"}]}'

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$(basename "$1") lacks: $2"; return 1; }; }

# wf ARGS RESPONSES: the stubbed run of the recommending workflow.
wf() {
  command -v node > /dev/null || skip "node is not installed"
  [ -f "$WF" ] || { echo "no workflow $WF"; return 1; }
  node "$RUN" "$WF" "$1" "$2"
}

args() {
  jq -nc --argjson s "$1" '{summary: $s, declined: ["Add a dark mode"], models: {architect: "opus"},
    effort: {architect: {recommend: "high", scope: "xhigh"}}, profile: {level: "never", depth: "plain", involvement: "options with a recommendation"}}'
}

@test "R123: the recommending workflow runs the Architect once, with its model, its effort and a reply schema, and returns its recommendation" {
  local out label
  # The first run finds the Architect's label; the second answers under it.
  out=$(wf "$(args "$SUMMARY")" '{}') || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '.calls | length == 1' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '.calls[0].opts | .agentType == "vbw:architect" and .model == "opus" and .effort == "high" and (.schema | type) == "object"' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '.calls[0].opts.schema | tojson | test("small") and test("medium") and test("large") and test("maxItems")' || { echo "$out"; false; }
  label=$(printf '%s' "$out" | jq -r '.calls[0].opts.label')
  out=$(wf "$(args "$SUMMARY")" "$(jq -nc --arg l "$label" --argjson p "$PICK" '{($l): $p}')")
  printf '%s' "$out" | jq -e --argjson p "$PICK" '.result.recommendation == $p' || { echo "$out"; false; }
}

@test "R123: the Architect is given the record only: the open requirements, the backlog with each sort and size, the declined suggestions, and told to use decisions and never shipped work" {
  local out p
  out=$(wf "$(args "$SUMMARY")" '{}')
  p=$(printf '%s' "$out" | jq -r '.calls[0].prompt')
  for want in R7 "A customer gets a receipt" T4 Refunds next small T9 "Gift cards" later large T2 "Dark mode" "Add a dark mode"; do
    [[ "$p" == *"$want"* ]] || { echo "the prompt lacks $want: $p"; false; }
  done
  printf '%s' "$p" | grep -qi 'decision' || { echo "$p"; false; }
  printf '%s' "$p" | grep -qi 'shipped' || { echo "$p"; false; }
  printf '%s' "$p" | grep -qi 'declined' || { echo "$p"; false; }
  printf '%s' "$p" | grep -qi 'source' || { echo "$p"; false; }
}

@test "R123: with no open requirement and an empty backlog no Architect runs and the result says the backlog is empty" {
  local out
  out=$(wf "$(args "$EMPTY")" '{}')
  printf '%s' "$out" | jq -e '(.calls | length) == 0 and .result.recommendation == {empty: true}' || { echo "$out"; false; }
}

@test "R123: when the Architect fails, the workflow returns an error and no recommendation" {
  local out
  out=$(wf "$(args "$SUMMARY")" '{}')
  printf '%s' "$out" | jq -e '(.result | has("recommendation") | not) and (.result.error | type == "string" and length > 0)' || { echo "$out"; false; }
}

@test "R123: the profile's effort table has an Architect step for the recommendation in every profile" {
  jq -e 'all(.quality, .balanced, .budget; .architect.recommend | IN("low", "medium", "high", "xhigh", "max"))' "$EFFORTS"
}

@test "R123: the what's-next skill loads the summary, runs the workflow and stores the result with vbw recommend" {
  [ -f "$SKILL" ]
  grep -qx 'name: whats-next' "$SKILL"
  grep -qE '^allowed-tools:.*Workflow\(vbw:recommending\)' "$SKILL"
  grep -qF '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" triage --json' "$SKILL"
  grep -qF 'vbw recommend' "$SKILL"
  has "$SKILL" 'models'
  has "$SKILL" 'effort'
}

@test "R123: when another run is open the skill says so and does not start the step" {
  has "$SKILL" 'run is open|open run'
  has "$SKILL" 'say so'
  has "$SKILL" "(do not|never|don't) start"
}

@test "R123: a failure or a refusal is told in one line, the earlier recommendation stays and the ship is not undone" {
  has "$SKILL" 'one line'
  has "$SKILL" 'earlier recommendation (stays|is kept)'
  has "$SKILL" 'ship.{0,80}(not undone|never undone|already done|stays shipped)'
  has "$SKILL" 'refus'
}

@test "R123: the router runs the step after vbw ship, which never waits for it, and when the user asks what's next" {
  grep -qF 'vbw:whats-next' "$ROUTER"
  has "$ROUTER" 'vbw ship.{0,120}vbw:whats-next'
  has "$ROUTER" "what's next.{0,120}vbw:whats-next|vbw:whats-next.{0,120}what's next"
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
}

@test "R123: the Architect has a what's-next job: only the record, never shipped requirements or declined suggestions, each pick's source, and nothing invented when the backlog is empty" {
  has "$ARCHITECT" "what's next"
  has "$ARCHITECT" 'top pick'
  has "$ARCHITECT" 'runners-up'
  has "$ARCHITECT" 'small.{0,20}medium.{0,20}large'
  has "$ARCHITECT" 'only (from )?the record|from the record only'
  has "$ARCHITECT" 'shipped'
  has "$ARCHITECT" 'declined'
  has "$ARCHITECT" 'source'
  has "$ARCHITECT" 'invent'
  [ "$(wc -w < "$ARCHITECT")" -le 900 ]
}

@test "R123: the user documentation explains the recommendation, when it is written, its cost of one Architect run and how to ask for a new one" {
  [ -f "$DOC" ]
  has "$DOC" "what's next"
  has "$DOC" 'after .{0,40}ship'
  has "$DOC" 'one architect run|an architect run|architect runs once'
  has "$DOC" "/vbw:vibe what's next"
  has "$DOC" 'vbw status'
  has "$DOC" 'top pick'
  has "$DOC" 'runners-up'
  grep -qF 'docs/whats-next.md' "$README"
}

@test "R123: fields the kernel does not know are dropped from every pick, so a runner-up with a reason still stores" {
  local out label extra
  out=$(wf "$(args "$SUMMARY")" '{}')
  label=$(printf '%s' "$out" | jq -r '.calls[0].opts.label')
  extra='{"top": {"text": "Refunds", "reason": "Customers ask for it most.", "size": "small", "source": "T4", "why": "x"}, "runners": [{"text": "Gift cards", "reason": "Later.", "size": "large", "source": "T9"}]}'
  out=$(wf "$(args "$SUMMARY")" "$(jq -nc --arg l "$label" --argjson p "$extra" '{($l): $p}')")
  printf '%s' "$out" | jq -e --argjson p "$PICK" '.result.recommendation == $p' || { echo "$out"; false; }
}
