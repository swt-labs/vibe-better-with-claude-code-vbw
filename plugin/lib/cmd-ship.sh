#!/usr/bin/env bash
# vbw ship: the user ships the milestone once vbw next says so (everything
# proven on the current files and accepted). Marks it shipped and logs the
# decision; it publishes nothing (no tag, no push). The what's-next recommendation was
# written for the work before the ship, so the ship retires it (R123). A [human] requirement the
# user skipped (vbw req skip) is marked later: vbw milestone start moves it on.

# ship_changed_of LABEL ENTRY...: appends to the caller's rows "PROJECT-PATH<TAB>LABEL" lines, one
# per changed, deleted or new file the entries reach (vbw commit's own resolution: vbw_plan_paths,
# vbw_in_repo, vbw_changed; a submodule's file by project path; a moved pointer is no change).
ship_changed_of() {
  local label="$1" r f rels
  shift
  [ $# -gt 0 ] || return 0
  vbw_plan_paths "$@"
  for r in ${VBW_REPOS[@]+"${VBW_REPOS[@]}"}; do
    rels=()
    while IFS= read -r -d '' f; do rels+=("$f"); done < <(vbw_in_repo "$r")
    while IFS= read -r -d '' _ && IFS= read -r -d '' f; do
      f="${r:+$r/}$f"
      case "$f" in .vbw | .vbw/*) continue ;; esac
      rows="$rows$f"$'\t'"$label"$'\n'
    done < <(vbw_changed "$r" "${rels[@]}")
  done
}

# ship_line PATH PLANS PROTECTED: one blocking file's line, "  PATH (plan P1.1, protected check file)".
ship_line() {
  local what="" n
  if [ -n "$2" ]; then
    case "$2" in *,*) n=plans ;; *) n=plan ;; esac
    what="$n $2"
  fi
  [ "$3" = 0 ] || what="$what${what:+, }protected check file"
  printf '  %s (%s)' "$1" "$what"
}

# ship_uncommitted: the milestone's own uncommitted files, the ones vbw commit would commit: the
# file entries of every plan of the active milestone and the record's protected check files.
# Prints the whole refusal and returns 1, or prints nothing and returns 0. A user's own file
# never counts.
ship_uncommitted() {
  local rows="" pid entry m plans=() entries=() path label out="" cur="" curplans="" curprot=0
  local nextcmds="" haveprot=0 seenplans=" "
  m=$(jq -r .milestone.id "$VBW_RECORD")
  while IFS= read -r pid; do plans+=("$pid"); done < <(jq -r --arg m "$m" \
    '. as $r | .plans[] | select(.phase as $ph | any($r.phases[]; .id == $ph and .milestone == $m)) | .id' "$VBW_RECORD")
  for pid in ${plans[@]+"${plans[@]}"}; do
    entries=()
    while IFS= read -r entry; do entries+=("$entry"); done < <(jq -r --arg p "$pid" '.plans[] | select(.id == $p) | .files[]?' "$VBW_RECORD")
    ship_changed_of "$pid" ${entries[@]+"${entries[@]}"}
  done
  entries=()
  while IFS= read -r entry; do entries+=("$entry"); done < <(jq -r '.protected[]?' "$VBW_RECORD")
  ship_changed_of "" ${entries[@]+"${entries[@]}"}
  [ -n "$rows" ] || return 0
  rows=$(printf '%s' "$rows" | LC_ALL=C sort -u)
  while IFS=$'\t' read -r path label; do
    if [ "$path" != "$cur" ]; then
      [ -z "$cur" ] || out="$out$(ship_line "$cur" "$curplans" "$curprot")"$'\n'
      cur="$path" curplans="" curprot=0
    fi
    if [ -z "$label" ]; then
      curprot=1 haveprot=1
    else
      curplans="$curplans${curplans:+, }$label"
      case "$seenplans" in
        *" $label "*) ;;
        *)
          seenplans="$seenplans$label "
          nextcmds="$nextcmds${nextcmds:+; }vbw commit $label \"type(scope): description\""
          ;;
      esac
    fi
  done <<ROWS
$rows
ROWS
  out="$out$(ship_line "$cur" "$curplans" "$curprot")"
  [ "$haveprot" = 0 ] || nextcmds="$nextcmds${nextcmds:+; }vbw commit --fix FIX \"type(scope): description\" FILE for a check file of an open fix"
  printf "the milestone's work is not committed:\n%s\nNext: %s, then vbw ship\n" "$out" "$nextcmds"
  return 1
}

cmd_ship() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw ship"
  vbw_require_project
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  local action
  action=$(cmd_next --json | jq -r .action)
  [ "$action" = ship ] || vbw_die "not ready to ship: vbw next says $action ($(cmd_next | cut -d: -f2- | sed 's/^ //'))"
  # The proof reads the files on disk; the milestone's own files must also be in git history
  # (the user's own files never block: docs/workflows.md, "Submodules").
  local refusal
  refusal=$(ship_uncommitted) || vbw_die "$refusal"
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
  # The amendments made since the last approval (R250), in the lines vbw show contract --changes prints.
  contract_amendments_block "$(record_read)"
  jq -r '"shipped \(.milestone.id) \(.milestone.title)"' "$VBW_RECORD"
  # The test suite's cost, and how the milestone changed it (unittime.sh): a report, never a gate.
  # shellcheck source=unittime.sh
  . "$VBW_LIB/unittime.sh"
  unittime_ship_line "$(jq -r .milestone.id "$VBW_RECORD")"
}
