#!/bin/bash
# shellcheck disable=SC2034
# verification-freshness.sh -- shared helpers for determining whether a
# VERIFICATION.md artifact is stale relative to current product-code state.
#
# Contract:
# - verification_is_stale FILE returns 0 when the verification should be treated
#   as stale/pending, 1 when it is fresh, and sets
#   VERIFICATION_FRESHNESS_REASON to a short diagnostic token.
# - Any git/provenance error fails closed to stale. Under heavy parallel test
#   load, transient git subprocess failures must not be misclassified as fresh.

extract_verified_at_commit() {
  local verif_file="$1"
  [ -n "$verif_file" ] && [ -f "$verif_file" ] || return 0
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^verified_at_commit:/ { sub(/^verified_at_commit:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
  ' "$verif_file" 2>/dev/null || true
}

verification_is_stale() {
  local verif_file="$1"
  local _dirty _vac _cur_commit _cur_commit_ts _verif_mtime

  VERIFICATION_FRESHNESS_REASON=""
  [ -n "$verif_file" ] && [ -f "$verif_file" ] || return 1

  if ! _dirty=$(git status --porcelain --untracked-files=normal -- . ':!.vbw-planning' ':!CLAUDE.md' 2>/dev/null); then
    VERIFICATION_FRESHNESS_REASON="git_status_failed"
    return 0
  fi
  if [ -n "$_dirty" ]; then
    VERIFICATION_FRESHNESS_REASON="working_tree_changed"
    return 0
  fi

  _vac=$(extract_verified_at_commit "$verif_file")
  if [ -n "$_vac" ]; then
    if ! _cur_commit=$(git log -1 --format='%H' -- . ':!.vbw-planning' ':!CLAUDE.md' 2>/dev/null); then
      VERIFICATION_FRESHNESS_REASON="git_log_failed"
      return 0
    fi
    if [ -z "$_cur_commit" ]; then
      VERIFICATION_FRESHNESS_REASON="product_commit_unavailable"
      return 0
    fi
    if [ "$_cur_commit" != "$_vac" ]; then
      VERIFICATION_FRESHNESS_REASON="verified_at_commit_mismatch"
      return 0
    fi
    VERIFICATION_FRESHNESS_REASON="fresh"
    return 1
  fi

  if ! _cur_commit_ts=$(git log -1 --format='%ct' -- . ':!.vbw-planning' ':!CLAUDE.md' 2>/dev/null); then
    VERIFICATION_FRESHNESS_REASON="git_log_failed"
    return 0
  fi
  _verif_mtime=$(perl -e 'print +(stat shift)[9]' "$verif_file" 2>/dev/null || true)
  if [ -z "$_cur_commit_ts" ] || [ -z "$_verif_mtime" ]; then
    VERIFICATION_FRESHNESS_REASON="freshness_baseline_unavailable"
    return 0
  fi
  if [ "$_cur_commit_ts" -ge "$_verif_mtime" ]; then
    VERIFICATION_FRESHNESS_REASON="product_changed_after_verification"
    return 0
  fi

  VERIFICATION_FRESHNESS_REASON="fresh"
  return 1
}