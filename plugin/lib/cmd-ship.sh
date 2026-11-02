#!/usr/bin/env bash
# vbw ship: the user ships the milestone once vbw next says so (everything
# proven on the current files and accepted). Marks it shipped and logs the
# decision; it publishes nothing (no tag, no push). The what's-next recommendation was
# written for the work before the ship, so the ship retires it (R123). A [human] requirement the
# user skipped (vbw req skip) is marked later: vbw milestone start moves it on.

# ship_dirty_subs REPO: adds to the caller's dirty, by project path, each changed
# file of every checked-out submodule of REPO ("" for the project), every level down.
ship_dirty_subs() {
  local s p entry
  while IFS= read -r -d '' s; do
    p="${1:+$1/}$s"
    while IFS= read -r -d '' entry; do
      dirty="$dirty $p/${entry:3}"
    done < <(git -C "$VBW_ROOT/$p" status --porcelain=v1 -z --no-renames --untracked-files=all --ignore-submodules=all)
    ship_dirty_subs "$p"
  done < <(vbw_subs "$1")
}

cmd_ship() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw ship"
  vbw_require_project
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  local action
  action=$(cmd_next --json | jq -r .action)
  [ "$action" = ship ] || vbw_die "not ready to ship: vbw next says $action ($(cmd_next | cut -d: -f2- | sed 's/^ //'))"
  # The proof reads the files on disk; shipped work must also be in git history.
  # A submodule's files are read in the submodule, at every level down; its
  # pointer moving is no change (vbw commit never moves it: docs/workflows.md,
  # "Submodules").
  local entry dirty=""
  while IFS= read -r -d '' entry; do
    dirty="$dirty ${entry:3}"
  done < <(git -C "$VBW_ROOT" status --porcelain=v1 -z --no-renames --untracked-files=all --ignore-submodules=all -- . ':(exclude).vbw')
  ship_dirty_subs ""
  [ -z "$dirty" ] || vbw_die "the proven work is not committed:$dirty (commit it, then vbw ship)"
  # Freeze the milestone's cost; null (unknown) when no session has figures.
  local total
  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  total=$(costs_milestone_total "$VBW_RECORD" "$(jq -r .milestone.id "$VBW_RECORD")")
  record_update "$VBW_JQ_DEFS"'.milestone.id as $m | .milestone.status = "shipped"
    | if $total == null then . else .costs.milestones[$m] = ((.costs.milestones[$m] // {baseline: {}}) + {total: $total}) end
    | (.requirements[] | select(.milestone == $m and .skipped == true and .status != "accepted")).later = true
    | [.requirements[] | select(.milestone == $m and .later == true) | .id] as $moved
    | .shipped += [{id: .milestone.id, title: .milestone.title, at: $at}]
    | del(.recommendation)
    | .decisions += [{id: (.decisions | next_id("D")), at: $at,
        text: ("Shipped \(.milestone.id) \(.milestone.title): \([.requirements[] | select(.milestone == $m and (.status | IN("proven", "accepted")))] | length) requirement\(if ([.requirements[] | select(.milestone == $m and (.status | IN("proven", "accepted")))] | length) == 1 then "" else "s" end) proven or accepted"
          + (if ($moved | length) > 0 then "; moved to the next milestone to judge: \($moved | join(", "))" else "" end))}]' \
    --arg at "$(vbw_now)" --argjson total "$total"
  record_commit "chore(vbw): ship $(jq -r .milestone.id "$VBW_RECORD")"
  jq -r '"shipped \(.milestone.id) \(.milestone.title)"' "$VBW_RECORD"
  # The test suite's cost, and how the milestone changed it (unittime.sh): a report, never a gate.
  # shellcheck source=unittime.sh
  . "$VBW_LIB/unittime.sh"
  unittime_ship_line "$(jq -r .milestone.id "$VBW_RECORD")"
}
