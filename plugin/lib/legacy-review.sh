#!/usr/bin/env bash
# vbw legacy review: the review of a VBW 1 folder (.vbw-planning/) that comes
# before the choice to convert or start fresh. Read-only and fixed: the same
# folder always gives the same facts and the same recommendation. It reads
# file names, file times, git history and the plans' front matter; it runs and
# interprets nothing it finds, and it never fails: what it could not read goes
# into "notes".

# legacy_review_rows ROOT: one tab-separated row per fact: P phase-dir done
# (a readable plan), U plan (an unreadable one), N path exists (a path a plan
# names under files_modified; absolute or climbing paths are never looked up),
# T epoch (a file time).
legacy_review_rows() {
  local root=$1 plan pdir base p f ct=
  while IFS= read -r -d '' plan; do
    if [ ! -s "$plan" ] || [ ! -r "$plan" ]; then printf 'U\t%s\n' "${plan#"$root"/}"; continue; fi
    pdir=${plan%/*}; base=${plan##*/}
    if [ -s "$pdir/${base%-PLAN.md}-SUMMARY.md" ]; then p=1; else p=0; fi
    printf 'P\t%s\t%s\n' "${pdir#"$root/$VBW_LEGACY/"}" "$p"
    awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit }
      /^[[:space:]]*files_modified:/ { on = 1; next }
      on && /^[[:space:]]*-[[:space:]]+/ { sub(/^[[:space:]]*-[[:space:]]+/, ""); gsub(/["'"'"']/, ""); sub(/\/$/, ""); print; next }
      on && /^[^[:space:]-]/ { on = 0 }' "$plan" 2> /dev/null | while IFS= read -r p; do
      case "$p" in "" | /* | .. | ../* | */.. | */../*) continue ;; esac
      if [ -e "$root/$p" ]; then printf 'N\t%s\t1\n' "$p"; else printf 'N\t%s\t0\n' "$p"; fi
    done
  done < <(find "$root/$VBW_LEGACY" \( -path "*/phases/*" \) -type f -name '*-PLAN.md' -print0 2> /dev/null | LC_ALL=C sort -z)
  for f in PROJECT.md STATE.md; do [ -s "$root/$VBW_LEGACY/$f" ] || printf 'M\t%s\n' "$f"; done
  if git -C "$root" rev-parse --git-dir > /dev/null 2>&1; then
    ct=$(git -C "$root" log -1 --format=%ct -- "$VBW_LEGACY" 2> /dev/null)
  else
    printf 'G\n'
  fi
  if [ -z "$ct" ]; then
    while IFS= read -r -d '' f; do
      printf 'T\t%s\n' "$(stat -f %m "$f" 2> /dev/null || stat -c %Y "$f" 2> /dev/null || printf 0)"
    done < <(find "$root/$VBW_LEGACY" -type f -print0 2> /dev/null)
  else
    printf 'T\t%s\n' "$ct"
  fi
}

legacy_review() {
  local root st="" choice
  root=$(git rev-parse --show-toplevel 2> /dev/null) || root=$PWD
  if [ ! -d "$root/$VBW_LEGACY" ]; then
    printf '{"legacy": false}\n'
    return 0
  fi
  if [ -f "$root/$VBW_LEGACY/.execution-state.json" ]; then
    st=$(jq -r 'if type == "object" then (.status // "") else error("x") end' "$root/$VBW_LEGACY/.execution-state.json" 2> /dev/null) || st=UNREADABLE
  fi
  choice=$(jq -c '.project.legacy // {}' "$root/.vbw/record.json" 2> /dev/null) || choice='{}'
  [ -n "$choice" ] || choice='{}'
  legacy_review_rows "$root" | jq -R -s -c --arg st "$st" --argjson now "$(date -u +%s)" --argjson c "$choice" '
    [split("\n")[] | select(length > 0) | split("\t")] as $r
    | [$r[] | select(.[0] == "P")] as $P | [$r[] | select(.[0] == "N")] as $N
    | ([$r[] | select(.[0] == "T") | .[1] | tonumber] | max // 0) as $ts
    | ($N | unique_by(.[1])) as $named
    | ($P | group_by(.[1]) | map({d: .[0][1], n: length, f: (map(select(.[2] == "1")) | length)})
       | map(select(.f > 0 and .f < .n) | "phase \(.d): \(.f) of \(.n) plans finished")) as $phase
    | {legacy: true, choice: ($c.choice // null), asked: (($c.choice // null) != null),
       readable: ($P | length > 0), finished: {done: ($P | map(select(.[2] == "1")) | length), total: ($P | length)},
       last_used: (if $ts > 0 then ($ts | strftime("%Y-%m-%d")) else null end),
       days_ago: (if $ts > 0 then (($now - $ts) / 86400 | floor) else null end),
       match: {named: ($named | length), found: ($named | map(select(.[2] == "1")) | length)},
       half_done: ($phase + (if ($st | IN("", "UNREADABLE", "complete", "completed", "done", "shipped", "finished")) then [] else ["an unfinished build was left behind (.execution-state.json says \"\($st)\")"] end)),
       notes: ([$r[] | select(.[0] == "U") | "\(.[1]) is empty or cannot be read, so it is not counted"]
         + (if ($P | length) == 0 then ["no plan could be read in .vbw-planning/"] else [] end)
         + (if $st == "UNREADABLE" then [".vbw-planning/.execution-state.json cannot be read, so an unfinished build could not be checked"] else [] end)
         + [$r[] | select(.[0] == "M") | ".vbw-planning/\(.[1]) is missing or empty"]
         + (if any($r[]; .[0] == "G") then ["this is not a git repository, so the last use comes from file times"] else [] end))}
    | (if (.readable | not) or (.match.named > 0 and .match.found * 2 < .match.named)
          or ((.days_ago // 0) > 365 and .finished.done * 2 < .finished.total) then "fresh" else "convert" end) as $rec
    | .recommendation = $rec
    | .reasons = (if .readable | not then ["No plan in the old folder could be read, so there is nothing to convert."] else
        ["\(.finished.done) of \(.finished.total) plans were finished."]
        + (if .match.named > 0 then ["\(.match.found) of \(.match.named) files and folders the plans name still exist in this project."]
           else ["The plans name no files, so they cannot be compared with the code."] end)
        + (if .last_used != null then ["It was last used on \(.last_used) (\(.days_ago) days ago)."] else [] end)
        + (if (.half_done | length) > 0 then ["Work was left half done: \(.half_done | join("; "))."] else [] end) end)' 2> /dev/null \
    || printf '{"legacy": true, "readable": false, "recommendation": "fresh", "notes": ["the review could not be put together"], "reasons": ["The old folder could not be reviewed, so there is nothing safe to convert."]}\n'
}
