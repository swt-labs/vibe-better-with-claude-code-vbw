#!/usr/bin/env bash
# The loop's shared helpers (R178; docs/loop.md). Sourced by the loop commands and, later, the loop
# step and the gate. They read; they never write the record.

# loop_norm TEXT: whitespace collapsed and trimmed, the way vbw spec add writes a requirement's text.
loop_norm() {
  local IFS=$' \t\n'
  set -f
  # shellcheck disable=SC2086 # the split is the point
  set -- $1
  set +f
  printf '%s' "$*"
}

# loop_item_proof TEXT: human for a backlog text starting with "[human] ", else auto.
loop_item_proof() {
  case "$1" in '[human] '*) printf 'human' ;; *) printf 'auto' ;; esac
}

# loop_item_text TEXT: the requirement text of a backlog text: "[human] " and "[auto] " are the
# proof's marker and not part of it.
loop_item_text() {
  case "$1" in
    '[human] '*) printf '%s' "${1#'[human] '}" ;;
    '[auto] '*) printf '%s' "${1#'[auto] '}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# LOOP_USD_JQ: the jq definition of usd, a dollar amount to the cent ("$5.00").
# shellcheck disable=SC2034 # used by the loop commands that source this file
LOOP_USD_JQ='def usd: "$" + (. * 100 | round | tostring | if length < 3 then ("000" + .)[-3:] else . end | .[:-2] + "." + .[-2:]);'

# loop_figures_now: every known session's current figures as {SID: {usd, at}}, the baseline
# of a loop, an item or a milestone.
loop_figures_now() {
  local base="{}" sid figs
  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    figs=$(costs_figures "$sid")
    [ "$figs" = null ] || base=$(printf '%s' "$base" | jq -c --arg s "$sid" --arg at "$(vbw_now)" --argjson f "$figs" '.[$s] = $f + {at: $at}')
  done < <(costs_sessions)
  vbw_out '%s\n' "$base"
}

# loop_spend FILE [ITEM]: FILE is the record's path (never its data: jq reads it). The spend as
# {usd, sessions}: the sum over the sessions with a
# side file of the current figures minus the baseline (the loop's, or the item's own), exactly as a
# milestone's total is (costs_milestone_total reads a baseline from the record it is given, so it is
# given the baseline as a one-milestone record). null when no session has a figure.
loop_spend() {
  local tmp out
  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  tmp=$(mktemp "$VBW_RUNTIME/loop.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$tmp"
  jq --arg i "${2:-}" '{costs: {milestones: {loop: {baseline: (if $i == "" then .loop.baseline else ([.loop.items[] | select(.id == $i)][0].baseline) end // {})}}}}' "$1" > "$tmp"
  out=$(costs_milestone_total "$tmp" loop)
  vbw_guard_drop "$tmp"
  rm -f "$tmp"
  vbw_out '%s\n' "$out"
}

# loop_word RECORD SPEND_JSON: under, reached or cannot tell (no figure seen: it counts as reached
# for the stop rule); null when the loop has no ceiling.
loop_word() {
  jq -r --argjson s "${2:-null}" '.loop.ceiling as $c
    | if $c == null then "null"
      elif $s == null then "cannot tell"
      elif $s.usd >= $c.usd then "reached" else "under" end' "$1"
}
