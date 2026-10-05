#!/usr/bin/env bats
# R62 (docs/tools.md): the tooling workflow runs a few Scouts in parallel, one
# per angle (safety, quality, tests, skills), each looking at the project's own
# stack and returning main picks with sources; it keeps a short list, marks what
# is not from a trusted source with a plain warning, and a Scout that fails or
# finds nothing, or a stack that cannot be determined, never stops it. No model
# is called: the runtime is stubbed (tests/helpers/run-workflow.js, L1).

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/tooling.js"

setup() {
  vbw_setup
  command -v node > /dev/null 2>&1 || skip "node not installed"
}

teardown() { vbw_teardown; }

# pick NAME ORIGIN [SOURCES_JSON]: one Scout pick.
pick() {
  jq -nc --arg n "$1" --arg o "$2" --argjson s "${3:-[\"https://example.org/$1\"]}" \
    '{name: $n, what: "does \($n)", why: "fits a node project", sources: $s, origin: $o}'
}

# go ARGS RESPONSES: runs the workflow, prints {calls, result, logs}.
go() { node "$RUN" "$WF" "$1" "$2"; }

ARGS='{"stack": "node 20, express, jest", "profile": {"level": "never", "depth": "plain with technical terms explained", "involvement": "options with a recommendation"}}'

all_four() {
  jq -nc --argjson a "$(pick eslint respected-open-source)" --argjson b "$(pick prettier respected-open-source)" \
    --argjson c "$(pick jest respected-open-source)" --argjson d "$(pick some-skill other)" \
    '{"scout safety": {picks: [$a]}, "scout quality": {picks: [$b]}, "scout tests": {picks: [$c]}, "scout skills": {picks: [$d]}}'
}

@test "R62: one Scout per angle (safety, quality, tests, skills), each given the project's stack and the user's words" {
  run go "$ARGS" "$(all_four)"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    ([.calls[].opts.label] | sort) == ["scout quality","scout safety","scout skills","scout tests"]
    and all(.calls[]; .opts.agentType == "vbw:scout" and (.opts.schema | type == "object")
      and (.prompt | contains("node 20, express, jest")) and (.prompt | contains("plain with technical terms explained")))
    and (.calls | map(select(.opts.label == "scout safety").prompt | test("safety|vulnerab|security"; "i")) | all)
    and (.calls | map(select(.opts.label == "scout tests").prompt | test("test"; "i")) | all)'
}

@test "R62: every returned pick says what it is, why it fits, where it came from, and has at least one source link" {
  run go "$ARGS" "$(all_four)"
  printf '%s' "$output" | jq -e '
    (.result.picks | length) == 4
    and all(.result.picks[]; (.angle | type == "string") and (.name | length > 0) and (.what | length > 0) and (.why | length > 0)
      and (.sources | length >= 1) and all(.sources[]; test("^https?://")))'
}

@test "R62: a pick with no source link is dropped, never shown" {
  local r
  r=$(jq -nc --argjson a "$(pick nolink respected-open-source '[]')" --argjson b "$(pick junk respected-open-source '["not a link"]')" \
    --argjson c "$(pick good respected-open-source)" '{"scout safety": {picks: [$a, $b, $c]}}')
  run go "$ARGS" "$r"
  printf '%s' "$output" | jq -e '[.result.picks[].name] == ["good"]'
}

@test "R62: respected open-source picks are proposed as they are; anything else carries a plain warning and is marked not trusted" {
  run go "$ARGS" "$(all_four)"
  printf '%s' "$output" | jq -e '
    all(.result.picks[] | select(.name != "some-skill"); .trusted == true and (.warning // null) == null)
    and (.result.picks[] | select(.name == "some-skill") | .trusted == false and (.warning | type == "string" and length > 20))'
}

@test "R62: the list is short: at most two picks per angle and six in all, trusted ones first" {
  local r many
  many=$(jq -nc --argjson a "$(pick t1 other)" --argjson b "$(pick t2 respected-open-source)" --argjson c "$(pick t3 respected-open-source)" '[$a, $b, $c]')
  r=$(jq -nc --argjson m "$many" --argjson x "$(pick q1 respected-open-source)" --argjson y "$(pick q2 respected-open-source)" --argjson z "$(pick s1 respected-open-source)" \
    --argjson w "$(pick k1 other)" --argjson v "$(pick k2 respected-open-source)" \
    '{"scout safety": {picks: $m}, "scout quality": {picks: [$x, $y]}, "scout tests": {picks: [$z]}, "scout skills": {picks: [$w, $v]}}')
  run go "$ARGS" "$r"
  printf '%s' "$output" | jq -e '
    (.result.picks | length) <= 6
    and ([.result.picks[] | .angle] | group_by(.) | all(length <= 2))
    and ([.result.picks[].trusted] | . == (sort | reverse))'
}

@test "R62: a Scout that fails or finds nothing is named in missing, the others' picks are kept, nothing stops" {
  local r
  r=$(jq -nc --argjson a "$(pick eslint respected-open-source)" '{"scout safety": {picks: [$a]}, "scout quality": {picks: []}}')
  run go "$ARGS" "$r"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    ([.result.picks[].name] == ["eslint"])
    and ((.result.missing | sort) == ["quality","skills","tests"])
    and (.result.error // null) == null'
}

@test "R62: when every Scout fails the result is no picks and a plain note, not an error" {
  run go "$ARGS" '{}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.result.picks == [] and (.result.missing | length) == 4 and (.result.note | type == "string" and length > 10) and (.result.error // null) == null'
}

@test "R62: when the stack cannot be determined no Scout is started and the note says so" {
  local a
  for a in '{}' '{"stack": ""}' '{"stack": "   "}'; do
    run go "$a" '{}'
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '(.calls | length) == 0 and .result.picks == [] and (.result.note | test("stack"; "i")) and (.result.error // null) == null'
  done
}
