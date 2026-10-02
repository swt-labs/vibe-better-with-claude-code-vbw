#!/usr/bin/env bats
# Run ownership across sessions (R13, R14): a session that does not own the open
# run is told to wait, and cannot end it except when the user states the owner
# is closed (--owner-closed) or the run is older than 24 hours.
# A session is named by VBW_SESSION_ID (skills pass ${CLAUDE_SESSION_ID}).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  VBW_SESSION_ID=sessA "$VBW" run start qa > /dev/null
}

teardown() { vbw_teardown; }

as() { local s="$1"; shift; VBW_SESSION_ID="$s" run "$VBW" "$@" < /dev/null; }

age_run() {
  jq --argjson h "$1" '.lease.started_at = (now - $h * 3600 | todate)' .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
}

@test "run start records the owning session in the lease" {
  jq -e '.lease.session == "sessA"' .vbw/record.json
}

@test "next in another session says the run belongs elsewhere and never says to end it" {
  as sessB next --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.action == "run" and (.instruction | test("another session")) and (.instruction | test("wait")) and (.instruction | test("vbw status"))'
  echo "$output" | jq -e '.instruction | test("run end|end the run|end it") | not'
}

@test "next in the owning session still says to wait or end an interrupted run" {
  as sessA next --json
  echo "$output" | jq -e '.instruction | test("vbw run end")'
}

@test "run end from another session is refused and the run stays open" {
  as sessB run end
  [ "$status" -ne 0 ]
  [[ "$output" == *"another session"* ]]
  jq -e '.lease.session == "sessA"' .vbw/record.json
}

@test "run end from another session works when the user states the owner is closed" {
  as sessB run end --owner-closed
  [ "$status" -eq 0 ]
  jq -e '.lease == null' .vbw/record.json
}

@test "run end from another session works at 25 hours and is refused at 23" {
  age_run 23
  as sessB run end
  [ "$status" -ne 0 ]
  jq -e '.lease != null' .vbw/record.json
  age_run 25
  as sessB run end
  [ "$status" -eq 0 ]
  jq -e '.lease == null' .vbw/record.json
}

@test "run end from the owning session succeeds" {
  as sessA run end
  [ "$status" -eq 0 ]
  jq -e '.lease == null' .vbw/record.json
}
