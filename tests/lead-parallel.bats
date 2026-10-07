#!/usr/bin/env bats
# R102 (L1, the Lead's part): planning splits each phase into plans on separate
# files wherever the work allows, orders plans that must share a file into
# separate waves, and reads the contract's build-waves line to see the result.

load helper

LEAD="$PLUGIN_ROOT/agents/lead.md"

@test "R102: the Lead splits each phase into plans on separate files so as many as possible build at the same time" {
  grep -qiE 'separate files' "$LEAD"
  grep -qiE 'at the same time|in parallel|as many .* as possible' "$LEAD"
}

@test "R102: the Lead orders plans that must share a file into separate waves with after" {
  grep -qiE 'share a file' "$LEAD"
  grep -qiE 'wave' "$LEAD"
}

@test "R102: the Lead reads the build waves line of the contract after applying and splits further where it can" {
  grep -q 'build waves' "$LEAD"
}
