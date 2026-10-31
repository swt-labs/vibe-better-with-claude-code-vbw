#!/usr/bin/env bash
# vbw plan done|block|reset ID: a plan's outcome (docs/workflows.md). "done" is
# verified, not claimed: the plan has a commit carrying its VBW-Plan trailer (or
# all its files are committed in HEAD and a check of its requirements passes),
# none of its files has uncommitted changes, and the checks of every requirement
# it completes (no other open plan serves it) pass. "block" refuses a done plan.

# shellcheck source=steps.sh
. "$VBW_LIB/steps.sh"
# shellcheck source=mutate-queue.sh
. "$VBW_LIB/mutate-queue.sh"
# shellcheck source=history.sh
. "$VBW_LIB/history.sh"

cmd_plan() {
  local sub="${1:-}" id="${2:-}"
  case "$sub" in
    done|reset) [ $# -eq 2 ] || vbw_usage_error "usage: vbw plan $sub ID" ;;
    block) [ $# -eq 3 ] && [ -n "$3" ] || vbw_usage_error "usage: vbw plan block ID REASON" ;;
    *) vbw_usage_error "usage: vbw plan done ID | block ID REASON | reset ID" ;;
  esac
  vbw_require_project
  local record
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg p "$id" 'any(.plans[]; .id == $p)' > /dev/null || vbw_die "unknown plan $id"
  case "$sub" in
    done)
      local files=() completes=() f dirty trailer=0
      while IFS= read -r -d '' f; do files+=("$f"); done \
        < <(printf '%s' "$record" | jq -j --arg p "$id" '.plans[] | select(.id == $p) | .files[] | . + "\u0000"')
      dirty=$(vbw_dirty_files "${files[@]}")
      [ -z "$dirty" ] || vbw_die "$id has uncommitted changes in: $dirty"
      if plan_has_commit "$id" ${files[@]+"${files[@]}"}; then trailer=1; else
        # Work committed some other way (the approval commit, a plain commit):
        # every file must be tracked in HEAD of the repository that tracks it,
        # and a check must prove it below.
        [ ${#files[@]} -gt 0 ] || vbw_die "$id has no commit yet: commit its work with vbw commit $id \"type(scope): ...\""
        vbw_repos "${files[@]}"
        local i=0 r
        for f in "${files[@]}"; do
          r=${VBW_REPO_OF[$i]}
          i=$((i + 1))
          vbw_rel "$r" "$f"
          [ -n "$(git -C "$VBW_ROOT${r:+/$r}" ls-tree -r --name-only -z HEAD -- "$VBW_REL" 2> /dev/null | tr -d '\0')" ] \
            || vbw_die "$id has no commit yet: $f is not committed (commit it with vbw commit $id \"type(scope): ...\")"
        done
      fi
      # The checks of every requirement this plan completes (no other open
      # plan serves it) must pass now.
      while IFS= read -r f; do [ -n "$f" ] && completes+=("$f"); done < <(printf '%s' "$record" | jq -r --arg p "$id" '
        . as $r | (.plans[] | select(.id == $p)) as $pl
        | $pl.reqs[] as $q
        | select(all($r.plans[]; .id == $p or .status == "done" or (any(.reqs[]; . == $q) | not)))
        | $r.checks[] | select(.req == $q) | .id')
      # shellcheck source=checks.sh
      . "$VBW_LIB/checks.sh"
      if [ "$trailer" -eq 0 ]; then
        # Without a trailer, the plan's own requirements need a passing check.
        local own=()
        while IFS= read -r f; do [ -n "$f" ] && own+=("$f"); done < <(printf '%s' "$record" | jq -r --arg p "$id" '
          . as $r | (.plans[] | select(.id == $p)) as $pl | $r.checks[] | select(.req as $q | $pl.reqs | any(. == $q)) | .id')
        [ ${#own[@]} -gt 0 ] || vbw_die "$id has no commit with its trailer and no check of its requirements to prove its committed files"
        checks_must_pass "$record" "$id is committed but its checks do not pass" "${own[@]}"
      fi
      checks_must_pass "$record" "$id completes requirements whose checks do not pass" ${completes[@]+"${completes[@]}"}
      # A plan built in an open build run, at standard or deep, also waits for the
      # mutation check (R188): every rule it completes shown to be caught.
      local missing queued e
      missing=$(printf '%s' "$record" | plan_missing_breaks "$id")
      queued=$(mutate_queue_entries "$id" | while IFS= read -r e; do jq -r .target "$e/meta.json"; done | paste -sd ' ' -)
      [ -z "$missing" ] || [ -z "$queued" ] || missing="$missing
Queued, not run yet: $queued: run them with vbw mutate $id --run"
      [ -z "$missing" ] || vbw_die "$id has behaviour no recorded break has shown to be caught:
$missing"
      # Breaks still queued are not needed any more.
      rm -rf "$(mutate_queue_dir "$id")"
      record_update '(.plans[] | select(.id == $p)) |= (.status = "done" | del(.note))' --arg p "$id"
      step_plan_done
      printf '%s done\n' "$id"
      ;;
    block)
      printf '%s' "$record" | jq -e --arg p "$id" 'any(.plans[]; .id == $p and .status == "done") | not' > /dev/null \
        || vbw_die "$id is already done: a finished plan cannot be blocked (vbw plan reset $id first if it must be built again)"
      # A blocked Dev raises the plan's phase one step, in the same update.
      record_update "$VBW_JQ_DEFS"'(.plans[] | select(.id == $p)) as $pl
        | (.plans[] | select(.id == $p)) |= (.status = "blocked" | .note = $why)
        | escalate_phases([$pl.phase]; null; "Dev blocked \($p): \($why)"; $at)' \
        --arg p "$id" --arg why "$3" --arg at "$(vbw_now)"
      printf '%s blocked: %s\n' "$id" "$3"
      ;;
    reset)
      record_update '(.plans[] | select(.id == $p)) |= (.status = "planned" | del(.note))' --arg p "$id"
      printf '%s planned\n' "$id"
      ;;
  esac
}

# plan_missing_breaks ID (record on stdin): the refusal lines for what the
# mutation check still lacks, empty when nothing is asked (a plan not building in
# a build run, an express or untiered phase, requirements without checks). It asks
# one red break per rule the plan owes (owed_rules, VBW_JQ_DEFS), at standard and
# deep alike (T174): a rule counts once any plan of its requirement has a red break
# of it or a --none entry for it. A task break is the Dev's own call, for a task
# whose behaviour no rule's check covers; plan done asks none.
plan_missing_breaks() {
  jq -r --arg p "$1" "$VBW_JQ_DEFS"'
    . as $r | (.plans[] | select(.id == $p)) as $pl
    | if ($r.lease.kind // "") != "build" or $pl.status != "building" then empty else
        [owed_rules($p)[] | . as $o
          | select([$r.plans[].mutations[]? | select((.result == "red" or has("none")) and .rule.req == $o.req and .rule.text == $o.text)] | length == 0)
          | "  \(.req).\(.n) \(.text)"] as $rules
        | if ($rules | length) == 0 then empty else
            (["Rules no recorded break has made a check fail:"] + $rules
              + ["Next: break what each rule promises in this plan'"'"'s code and run vbw mutate \($p) Rn.k \"what you broke\" FILE..., or vbw mutate \($p) Rn.k --none REASON when its check reads nothing the plans build"])
            | join("\n") end
      end'
}

# plan_has_commit ID [FILE...]: true when some commit of the record's own
# history (lib/history.sh) carries "VBW-Plan: ID" (an exact token): an older
# commit naming the same id is an old roadmap's, not this plan's. Read in the
# project's repository and in each submodule that tracks one of the plan's FILEs
# (vbw_plan_paths, history_args_in), where vbw commit commits them.
plan_has_commit() {
  local id="$1" line r repos=("") HISTORY_ARGS=()
  shift
  vbw_plan_paths ${@+"$@"}
  for r in ${VBW_REPOS[@]+"${VBW_REPOS[@]}"}; do [ -z "$r" ] || repos+=("$r"); done
  for r in "${repos[@]}"; do
    history_args_in "$r"
    while IFS= read -r line; do
      [ "$line" = "$id" ] && return 0
    done < <(git -C "$VBW_ROOT${r:+/$r}" log --format='%(trailers:key=VBW-Plan,valueonly)' "${HISTORY_ARGS[@]}" 2> /dev/null)
  done
  return 1
}
