#!/usr/bin/env bats
# R243 (T212, L1): the cause is removed, shown on GitHub's runners. tools/bench-steps-result.sh RUN_ID...
# reads each bench-steps.yml run's job logs (gh run view) and writes the step tables to
# tools/probes/guard-steps.json: per run its id, commit, 'before' or 'after' the fix, and per
# runner each row's four cells as {ms, q}. Written by the script from the runs, never by hand.
#
# The runs before the fix: 41312931896 (plow/2.1.23 at 808bfcde) and 41305323924 (main).

load helper

@test "R243: the committed step tables hold the before run and an after run on GitHub's three runners, and after the fix each Ubuntu runner's program run quotient is within 1.25 times macOS's" {
  local script="$REPO_ROOT/tools/bench-steps-result.sh" result="$REPO_ROOT/tools/probes/guard-steps.json"
  [ -x "$script" ] && grep -q 'gh run view' "$script" && grep -q 'tools/probes/guard-steps.json' "$script" \
    || { echo "no executable tools/bench-steps-result.sh reading the runs with gh run view into tools/probes/guard-steps.json"; false; }
  [ -f "$result" ] || { echo "no step tables committed at tools/probes/guard-steps.json"; false; }
  jq -e '.probe == "guard-steps"
    and any(.runs[]; .id == "41312931896" and .when == "before")
    and ([.runs[] | select(.when == "after")] | length >= 1)
    and all(.runs[]; (.sha | test("^[0-9a-f]{7,40}$")) and (.tables | keys | contains(["macos-latest", "ubuntu-latest", "ubuntu-26.04"]))
      and all(.tables[]; all(.["program run", "program compile", "reference run"]; type == "array" and length == 4 and all(.[]; (.ms | type == "number") and (.q | type == "number")))))' "$result" \
    || { jq '{probe, runs: [.runs[]? | {id, sha, when, runners: (.tables // {} | keys)}]}' "$result"; false; }
  jq -e 'def mean(r): [r[].q] | add / length;
    [.runs[] | select(.when == "after")] | last | .tables as $t
    | mean($t["macos-latest"]["program run"]) as $mac
    | all("ubuntu-latest", "ubuntu-26.04"; mean($t[.]["program run"]) <= 1.25 * $mac)' "$result" \
    || { echo "after the fix an Ubuntu runner's program run quotient exceeds 1.25 times macOS's:"; jq '[.runs[] | select(.when == "after")] | last | .tables | map_values(.["program run"] | map(.q))' "$result"; false; }
}
