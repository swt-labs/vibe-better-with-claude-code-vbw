#!/usr/bin/env bash
# Per-agent effort: the table of the profile in use (lib/efforts.json).

# The roles and steps the workflows use, as role:step,step.
VBW_EFFORT_STEPS='architect:decide,scope,recommend lead:plan,close dev:build,fix docs:build qa:verify scout:survey,merge debugger:investigate,diagnose,fix'

# effort_table PROFILE: the profile's table as compact JSON. Refuses, naming the
# role, the step and the value, a value Claude Code does not accept (not low,
# medium, high, xhigh or max, or not text) and any missing role or step. Only
# the given profile is judged.
effort_table() {
  local profile=$1 file=$VBW_LIB/efforts.json bad
  [ -f "$file" ] || vbw_die "the effort table $file is missing: reinstall the VBW plugin"
  jq -e --arg p "$profile" '.[$p] | type == "object"' "$file" > /dev/null 2>&1 \
    || vbw_die "the effort table has no profile '$profile': add it to $file"
  bad=$(jq -r --arg p "$profile" --arg steps "$VBW_EFFORT_STEPS" '
    .[$p] as $t
    | $steps | split(" ")[] | split(":") as $rs | $rs[0] as $r | ($rs[1] | split(","))[] as $s
    | ($t[$r] // null) as $row
    | (if ($row | type) == "object" then ($row[$s] // null) else null end) as $v
    | if $v == null then "\($r) \($s): no effort set"
      elif ($v | type) != "string" then "\($r) \($s): effort \($v | tojson) is not text"
      elif ($v | IN("low", "medium", "high", "xhigh", "max")) then empty
      else "\($r) \($s): effort \"\($v)\" is not one of low, medium, high, xhigh, max" end' "$file" | head -n 1)
  [ -z "$bad" ] || vbw_die "the effort table for profile '$profile' is wrong at $bad (fix $file)"
  jq -c --arg p "$profile" '.[$p]' "$file"
}
