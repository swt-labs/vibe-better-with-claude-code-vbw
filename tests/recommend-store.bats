#!/usr/bin/env bats
# R123 (decision D205; L1): the kernel's part of the what's-next
# recommendation. vbw recommend reads one recommendation (JSON on stdin): a top
# pick with its reason and size, zero to two runners-up each with a size, each
# naming its source (a todo id or a requirement id) when it has one; or, with
# nothing open, {"empty": true}. It stores it in .vbw/record.json with the time
# it was written, replacing any earlier one; it refuses a malformed one, naming
# what is wrong, and then keeps the earlier one. A stored recommendation is a
# field VBW 2.0.27 does not read, so it raises the schema to 3. vbw status shows
# it, or one line saying there is none yet and how to ask for one.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '(.requirements[] | select(.id == "R1")).status = "proven"' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" todo add "Refunds" > /dev/null
  "$VBW" todo add "Gift cards" > /dev/null
}

teardown() { vbw_teardown; }

GOOD='{"top": {"text": "Finish the receipt", "reason": "It is the last open requirement of this milestone.", "size": "small", "source": "R2"},
  "runners": [{"text": "Refunds", "size": "medium", "source": "T1"}, {"text": "Gift cards", "size": "large", "source": "T2"}]}'

recommend() { printf '%s' "$1" | "$VBW" recommend; }

@test "R123: vbw recommend stores the top pick, its reason and size, the runners-up and the time it was written" {
  run recommend "$GOOD"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.recommendation
    | .top == {text: "Finish the receipt", reason: "It is the last open requirement of this milestone.", size: "small", source: "R2"}
    and .runners == [{text: "Refunds", size: "medium", source: "T1"}, {text: "Gift cards", size: "large", source: "T2"}]
    and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' .vbw/record.json
}

@test "R123: zero runners-up is fine, and a pick may have no source" {
  run recommend '{"top": {"text": "Write a guide", "reason": "New users ask how to start.", "size": "medium"}, "runners": []}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.recommendation.top.text == "Write a guide" and (.recommendation.top | has("source") | not) and .recommendation.runners == []' .vbw/record.json
}

@test "R123: a new recommendation replaces the earlier one, so only one is kept" {
  recommend "$GOOD" > /dev/null
  run recommend '{"top": {"text": "Refunds", "reason": "Customers ask for it.", "size": "medium", "source": "T1"}, "runners": []}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '(.recommendation | type) == "object" and .recommendation.top.text == "Refunds" and .recommendation.runners == []' .vbw/record.json
  jq -e '[paths(objects | has("top"))] | length == 1' .vbw/record.json
}

@test "R123: every malformed recommendation is refused with a message naming what is wrong, and the earlier one stays" {
  recommend "$GOOD" > /dev/null
  local before bad want
  before=$(jq -c .recommendation .vbw/record.json)
  while IFS='|' read -r want bad; do
    run recommend "$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $bad"; false; }
    printf '%s' "$output" | grep -qiE "$want" || { echo "for $bad the message does not name '$want': $output"; false; }
    [ "$(jq -c .recommendation .vbw/record.json)" = "$before" ] || { echo "changed by: $bad"; false; }
  done <<'EOF'
top|{"runners": []}
top|{"top": null, "runners": []}
reason|{"top": {"text": "Refunds", "reason": "", "size": "small"}, "runners": []}
reason|{"top": {"text": "Refunds", "size": "small"}, "runners": []}
size|{"top": {"text": "Refunds", "reason": "Asked for.", "size": "huge"}, "runners": []}
size|{"top": {"text": "Refunds", "reason": "Asked for.", "size": "small"}, "runners": [{"text": "Gift cards", "size": "XL"}]}
size|{"top": {"text": "Refunds", "reason": "Asked for."}, "runners": []}
runners-up|{"top": {"text": "A", "reason": "r", "size": "small"}, "runners": [{"text": "B", "size": "small"}, {"text": "C", "size": "small"}, {"text": "D", "size": "small"}]}
text|{"top": {"text": "", "reason": "r", "size": "small"}, "runners": []}
json|not json at all
EOF
}

@test "R123: a pick whose source is not open is refused: a shipped or proven requirement, a closed or unknown todo" {
  recommend "$GOOD" > /dev/null
  "$VBW" todo done T2 > /dev/null
  local before src
  before=$(jq -c .recommendation .vbw/record.json)
  for src in R1 R9 T2 T9 X1; do
    run recommend "$(jq -nc --arg s "$src" '{top: {text: "Something", reason: "r", size: "small", source: $s}, runners: []}')"
    [ "$status" -ne 0 ] || { echo "accepted source $src"; false; }
    [[ "$output" == *"$src"* ]] || { echo "the message does not name $src: $output"; false; }
  done
  run recommend '{"top": {"text": "Something", "reason": "r", "size": "small"}, "runners": [{"text": "Old", "size": "small", "source": "R1"}]}'
  [ "$status" -ne 0 ]
  [ "$(jq -c .recommendation .vbw/record.json)" = "$before" ]
}

@test "R123: a pick that is a declined suggestion is refused" {
  "$VBW" suggest decline "Add a dark mode" > /dev/null
  run recommend '{"top": {"text": "add a  Dark Mode", "reason": "r", "size": "small"}, "runners": []}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"declined"* ]] || { echo "$output"; false; }
  jq -e 'has("recommendation") | not' .vbw/record.json
}

@test "R123: with no open requirement and an empty backlog the stored recommendation says the backlog is empty; with work open, 'empty' is refused" {
  run recommend '{"empty": true}'
  [ "$status" -ne 0 ] || { echo "empty accepted with R2, T1 and T2 open"; false; }
  jq '.requirements |= map(.status = "proven") | .todos |= map(.status = "done")' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  run recommend '{"empty": true}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.recommendation.empty == true and (.recommendation | has("top") | not) and (.recommendation.at | test("Z$"))' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi "what's next" || { echo "$output"; false; }
  printf '%s' "$output" | grep -qi 'backlog is empty' || { echo "$output"; false; }
}

@test "R123: while a run is open the kernel stores no recommendation and says so" {
  VBW_SESSION_ID=s-one "$VBW" run start plan > /dev/null
  run recommend "$GOOD"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qi 'run' || { echo "$output"; false; }
  jq -e 'has("recommendation") | not' .vbw/record.json
}

@test "R123: the validator accepts a record with and without a recommendation, and refuses a damaged one" {
  vbw_run status
  [ "$status" -eq 0 ]
  recommend "$GOOD" > /dev/null
  vbw_run status
  [ "$status" -eq 0 ]
  local damage
  for damage in '.recommendation.top.size = "huge"' '.recommendation.top.reason = ""' 'del(.recommendation.at)' \
    '.recommendation.runners += [{text: "x", size: "small"}]' '.recommendation.extra = 1' '.recommendation = "soon"' \
    'del(.recommendation.top)'; do
    jq "$damage" .vbw/record.json > "$TEST_ROOT/r.json"
    cp .vbw/record.json "$TEST_ROOT/good.json"
    cp "$TEST_ROOT/r.json" .vbw/record.json
    vbw_run status
    [ "$status" -eq 3 ] || { echo "accepted: $damage"; false; }
    cp "$TEST_ROOT/good.json" .vbw/record.json
  done
}

@test "R123: a stored recommendation raises the schema to 3; an older VBW asks for an update; without one and without sorted todos the schema stays as before" {
  jq '.todos = []' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" decide "re-validate" > /dev/null
  jq -e '.schema == 1' .vbw/record.json
  recommend '{"top": {"text": "Finish the receipt", "reason": "Last open one.", "size": "small", "source": "R2"}, "runners": []}' > /dev/null
  jq -e '.schema == 3' .vbw/record.json
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/old-plugin"
  sed 's/^VBW_SCHEMA_MAX=.*/VBW_SCHEMA_MAX=2/' "$PLUGIN_ROOT/lib/record.sh" > "$TEST_ROOT/old-plugin/lib/record.sh"
  run "$TEST_ROOT/old-plugin/bin/vbw" status < /dev/null
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"needs a newer VBW"* ]]
}

@test "R123: vbw status shows the what's-next part: the top pick, its reason and size, each runner-up with its size, and the date" {
  recommend "$GOOD" > /dev/null
  local day
  day=$(jq -r '.recommendation.at[0:10]' .vbw/record.json)
  vbw_run status
  [ "$status" -eq 0 ]
  local part
  part=$(printf '%s\n' "$output" | sed -n "/[Ww]hat's next/,\$p")
  [ -n "$part" ] || { echo "$output"; false; }
  [[ "$part" == *"Finish the receipt"*"small"* ]] || { echo "$part"; false; }
  [[ "$part" == *"It is the last open requirement of this milestone."* ]] || { echo "$part"; false; }
  [[ "$part" == *"Refunds"*"medium"*"Gift cards"*"large"* ]] || { echo "$part"; false; }
  [[ "$part" == *"$day"* ]] || { echo "$part"; false; }
}

@test "R123: with none stored, vbw status says there is none yet and how to ask for one" {
  vbw_run status
  [ "$status" -eq 0 ]
  local line
  line=$(printf '%s\n' "$output" | grep -i "what's next") || { echo "$output"; false; }
  printf '%s' "$line" | grep -qi 'none yet' || { echo "$line"; false; }
  printf '%s' "$line" | grep -qF "/vbw:vibe what's next" || { echo "$line"; false; }
}

@test "R123: vbw status --json carries the recommendation, or null when none is stored" {
  run "$VBW" status --json < /dev/null
  printf '%s' "$output" | jq -e 'has("recommendation") and .recommendation == null' || { echo "$output"; false; }
  recommend "$GOOD" > /dev/null
  run "$VBW" status --json < /dev/null
  printf '%s' "$output" | jq -e '.recommendation.top.text == "Finish the receipt" and (.recommendation.runners | length) == 2' || { echo "$output"; false; }
}

@test "R123: the kernel help lists vbw recommend" {
  vbw_run help
  printf '%s\n' "$output" | grep -qE '^  recommend ' || { echo "$output"; false; }
}
