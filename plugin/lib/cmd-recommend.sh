#!/usr/bin/env bash
# vbw recommend < JSON: store the Architect's what's-next recommendation in the
# plan of record (.recommendation), replacing any earlier one (R123). The JSON
# is {top: {text, reason, size, source?}, runners: [{text, size, source?}]}
# (zero to two runners-up) or {empty: true}. A size is small, medium or large;
# a source is an open todo or a requirement of the active milestone that is not
# yet proven or accepted. A pick that was declined (vbw suggest decline), any
# run still open, or "empty" while work is open: refused, nothing changes.

# jq program: input is the record; $in is the recommendation as given. Prints
# the problem as a string, or the normalised recommendation as an object.
RECOMMEND_JQ='def norm: ascii_downcase | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
def okstr: type == "string" and (norm | length) > 0;
def sizes: ["small","medium","large"];
def bad_pick($what; $reason):
  (if (type == "object") then empty else "\($what) must be an object" end),
  (select(type == "object") |
    (if (.text | okstr) then empty else "\($what) needs a non-empty text" end),
    (if $reason then (if (.reason | okstr) then empty else "\($what) needs a non-empty reason" end) else empty end),
    (if (.size as $s | sizes | any(. == $s)) then empty else "\($what) needs a size: small, medium or large" end),
    (if has("source") and (.source | okstr | not) then "\($what) has an empty source" else empty end),
    (keys[] | select(. as $k | (["text","size","source"] + (if $reason then ["reason"] else [] end)) | any(. == $k) | not)
      | "\($what) has an unknown field: \(.)"));
def pick($reason): {text, size} + (if $reason then {reason} else {} end) + (if has("source") then {source} else {} end);
. as $rec
| ([.requirements[] | select(.milestone == $rec.milestone.id and .status != "proven" and .status != "accepted")]) as $openreq
| ([.todos[] | select(.status == "open" or .status == "in_progress")]) as $opentodo
| if ($in | type) != "object" then "the recommendation must be a JSON object"
  elif $in.empty == true then
    if ($in | keys) != ["empty"] then "an empty recommendation is exactly {\"empty\": true}"
    elif .lease != null then "a run is open: end it (vbw run end) before storing a recommendation"
    elif ($openreq | length) + ($opentodo | length) > 0 then "the backlog is not empty: \(([$openreq[].id] + [$opentodo[].id]) | join(", ")) still open; give a top pick"
    else {empty: true} end
  else
    ($in.top) as $top
    | ($in.runners // []) as $runners
    | (if ($in | has("top") | not) or $top == null then ["no top pick: give a top with text, reason and size"]
       else [$top | bad_pick("the top pick"; true)] end
       + (if ($runners | type) != "array" then ["runners must be an array"]
          elif ($runners | length) > 2 then ["at most two runners-up are allowed, got \($runners | length)"]
          else [$runners | to_entries[] | .key as $i | .value | bad_pick("runner-up \($i + 1)"; false)] end)
       + [$in | keys[] | select(. != "top" and . != "runners") | "unknown field: \(.)"]) as $shape
    | if ($shape | length) > 0 then $shape[0]
      elif .lease != null then "a run is open: end it (vbw run end) before storing a recommendation"
      else
        ([$top] + $runners) as $picks
        | ([$picks[] | select(has("source")) | .source as $s
            | select((any($opentodo[]; .id == $s) or any($openreq[]; .id == $s)) | not)
            | "source \($s) is not an open todo or an unproven requirement of \($rec.milestone.id)"]
           + [$picks[] | .text as $t | select(any((($rec.project.declined // [])[]); (.text | norm) == ($t | norm)))
              | "\"\($t)\" was declined; it is never offered again"]) as $refused
        | if ($refused | length) > 0 then $refused[0]
          else {top: ($top | pick(true)), runners: [$runners[] | pick(false)]} end
      end
  end'

cmd_recommend() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw recommend < JSON  ({top: {text, reason, size, source?}, runners: [{text, size, source?}]} or {empty: true})"
  vbw_require_project
  local input out
  input=$(cat)
  printf '%s' "$input" | jq -e . > /dev/null 2>&1 || vbw_die "the recommendation is not JSON"
  out=$(record_read | jq -c --argjson in "$input" "$RECOMMEND_JQ") || vbw_die "the recommendation could not be checked"
  if [ "$(printf '%s' "$out" | jq -r 'type')" = string ]; then
    vbw_die "$(printf '%s' "$out" | jq -r .)"
  fi
  record_update '.recommendation = ({at: $at} + $r)' --arg at "$(vbw_now)" --argjson r "$out"
  jq -r '.recommendation | if .empty then "recommended: the backlog is empty" else "recommended: \(.top.text) (\(.top.size))" end' "$VBW_RECORD"
}
