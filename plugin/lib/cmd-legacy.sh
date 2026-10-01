#!/usr/bin/env bash
# vbw legacy [facts] | done | remove: a VBW 1 project (.vbw-planning/) and its
# conversion (docs/convert.md). VBW 2 never changes .vbw-planning/ on its own:
# facts only reads it; remove deletes it, after the conversion, only when the
# user chose to.

VBW_LEGACY=.vbw-planning

cmd_legacy() {
  local sub="${1:-facts}"
  [ $# -le 1 ] || vbw_usage_error "usage: vbw legacy [facts] | done | remove"
  case "$sub" in
    facts) legacy_facts ;;
    done)
      vbw_require_project
      [ -d "$VBW_ROOT/$VBW_LEGACY" ] || vbw_die "no $VBW_LEGACY/ here: nothing to convert"
      record_update '.converted = {from: $d, at: $at}' --arg d "$VBW_LEGACY" --arg at "$(vbw_now)"
      record_commit "chore(vbw): convert the VBW 1 plan"
      printf 'converted: %s/ stays as it is unless you remove it (vbw legacy remove)\n' "$VBW_LEGACY"
      ;;
    remove)
      vbw_require_project
      [ -d "$VBW_ROOT/$VBW_LEGACY" ] || vbw_die "no $VBW_LEGACY/ here"
      record_read | jq -e 'has("converted")' > /dev/null \
        || vbw_die "$VBW_LEGACY/ is not converted yet: convert it first (/vbw:convert), so nothing is lost"
      legacy_remove
      ;;
    *) vbw_usage_error "usage: vbw legacy [facts] | done | remove" ;;
  esac
}

# What a conversion needs to know, as JSON: which files hold the project's
# description, requirements, roadmap and state; the milestones (shipped or not)
# and phases with their plan counts (a plan with a SUMMARY is done); whether the
# folder is in git. Reads nothing else and changes nothing.
legacy_facts() {
  vbw_project
  local dir="$VBW_ROOT/$VBW_LEGACY" converted=false
  if [ ! -d "$dir" ]; then
    printf '{"legacy": false}\n'
    return 0
  fi
  [ -f "$VBW_RECORD" ] && jq -e 'has("converted")' "$VBW_RECORD" > /dev/null 2>&1 && converted=true
  (
    cd "$dir" || exit 1
    local f p tracked untracked
    tracked=$(git ls-files -z -- . | tr -cd '\000' | wc -c | tr -d ' ')
    untracked=$(git ls-files -z --others -- . | tr -cd '\000' | wc -c | tr -d ' ')
    {
      for f in PROJECT.md REQUIREMENTS.md ROADMAP.md STATE.md milestones/*/ROADMAP.md milestones/*/SHIPPED.md codebase/INDEX.md; do
        [ -f "$f" ] && printf 'file\t%s\n' "$f"
      done
      for p in milestones/*/; do
        [ -d "$p" ] || continue
        p=${p%/}
        if [ -f "$p/SHIPPED.md" ]; then printf 'milestone\t%s\ttrue\n' "$p"; else printf 'milestone\t%s\tfalse\n' "$p"; fi
      done
      for p in phases/*/ milestones/*/phases/*/; do
        [ -d "$p" ] || continue
        p=${p%/}
        printf 'phase\t%s\t%s\t%s\n' "$p" \
          "$(find "$p" -maxdepth 1 -name '*-PLAN.md' | wc -l | tr -d ' ')" \
          "$(find "$p" -maxdepth 1 -name '*-SUMMARY.md' | wc -l | tr -d ' ')"
      done
    } | jq -R -s -c --arg dir "$VBW_LEGACY" --argjson converted "$converted" \
          --argjson tracked "$tracked" --argjson untracked "$untracked" '
      [split("\n")[] | select(length > 0) | split("\t")] as $rows
      | {legacy: true, dir: $dir, converted: $converted,
         git: {tracked: $tracked, untracked: $untracked},
         files: [$rows[] | select(.[0] == "file") | "\($dir)/\(.[1])"],
         milestones: [$rows[] | select(.[0] == "milestone") | {dir: "\($dir)/\(.[1])", shipped: (.[2] == "true")}],
         phases: [$rows[] | select(.[0] == "phase")
                  | {dir: "\($dir)/\(.[1])", plans: (.[2] | tonumber), done: (.[3] | tonumber)}
                  | .status = (if .plans > 0 and .done >= .plans then "done"
                               elif .done > 0 then "partly done" else "not started" end)]}'
  )
}

# Delete .vbw-planning/: its tracked files with a commit of that deletion only
# (git keeps the history), then whatever is left (caches, untracked files).
legacy_remove() {
  local tracked
  tracked=$(git -C "$VBW_ROOT" ls-files -z -- "$VBW_LEGACY" | tr -cd '\000' | wc -c | tr -d ' ')
  if [ "$tracked" -gt 0 ]; then
    git -C "$VBW_ROOT" rm -r -q -- "$VBW_LEGACY" > /dev/null \
      || vbw_die "git could not remove $VBW_LEGACY/: nothing was deleted"
    git -C "$VBW_ROOT" commit --quiet --only -m "chore(vbw): remove the VBW 1 plan (converted to .vbw/)" -- "$VBW_LEGACY" > /dev/null 2>&1 \
      || printf 'vbw: warning: %s/ is removed and the removal is staged, but the commit failed; commit it yourself\n' "$VBW_LEGACY" >&2
  fi
  rm -rf "${VBW_ROOT:?}/$VBW_LEGACY"
  if [ "$tracked" -gt 0 ]; then
    printf 'removed %s/ (its files stay in git history)\n' "$VBW_LEGACY"
  else
    printf 'removed %s/ (it was not in git)\n' "$VBW_LEGACY"
  fi
}
