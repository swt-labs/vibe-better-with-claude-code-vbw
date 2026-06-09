#!/bin/bash
# shellcheck disable=SC2034
# verification-freshness.sh -- shared helpers for determining whether a
# VERIFICATION.md artifact is stale relative to current product-code state.
#
# Contract:
# - verification_is_stale FILE returns 0 when the verification should be treated
#   as stale/pending, 1 when it is fresh or the file is missing, and sets
#   VERIFICATION_FRESHNESS_REASON to a short diagnostic token.
# - When FILE is empty or does not exist, returns 1 with reason "missing_file".
# - Any git/provenance error fails closed to stale. Under heavy parallel test
#   load, transient git subprocess failures must not be misclassified as fresh.
# - Submodule monorepos (.gitmodules present): the parent's gitlink pointers and
#   untracked files are excluded from the dirty check; only uncommitted tracked
#   content inside submodules (or in non-submodule top-level files) counts. This
#   prevents perpetual `working_tree_changed` QA loops where pointer drift keeps
#   the parent tree dirty even when all real code is committed.

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
  local _dirty _vac _cur_commit _cur_commit_ts _verif_mtime _toplevel _top_dirty _sub_dirty

  VERIFICATION_FRESHNESS_REASON=""
  if [ -z "$verif_file" ] || [ ! -f "$verif_file" ]; then
    VERIFICATION_FRESHNESS_REASON="missing_file"
    return 1
  fi

  # Dirty-tree check. In a submodule monorepo the parent repo's gitlink *pointers*
  # and untracked files are NOT "the verified work" -- the real code lives inside
  # the submodules. So when .gitmodules is present, ignore parent pointer drift and
  # untracked noise (which otherwise keep the tree perpetually dirty and loop QA),
  # and instead treat uncommitted tracked content INSIDE any submodule -- or in
  # non-submodule top-level tracked files -- as the dirty signal. Single-repo
  # projects (no .gitmodules) keep the original whole-tree check unchanged.
  _toplevel=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$_toplevel" ] && [ -f "$_toplevel/.gitmodules" ]; then
    if ! _top_dirty=$(git status --porcelain --untracked-files=no --ignore-submodules=all -- . ':!.vbw-planning' ':!CLAUDE.md' 2>/dev/null); then
      VERIFICATION_FRESHNESS_REASON="git_status_failed"
      return 0
    fi
    # Uncommitted tracked content inside any submodule (recursive). Fail closed to
    # stale on any foreach/git error -- never misread a transient failure as clean.
    if ! _sub_dirty=$(git submodule foreach --quiet --recursive 'git status --porcelain --untracked-files=no' 2>/dev/null); then
      VERIFICATION_FRESHNESS_REASON="git_status_failed"
      return 0
    fi
    if [ -n "$_top_dirty" ] || [ -n "$_sub_dirty" ]; then
      VERIFICATION_FRESHNESS_REASON="working_tree_changed"
      return 0
    fi
  else
    if ! _dirty=$(git status --porcelain --untracked-files=normal -- . ':!.vbw-planning' ':!CLAUDE.md' 2>/dev/null); then
      VERIFICATION_FRESHNESS_REASON="git_status_failed"
      return 0
    fi
    if [ -n "$_dirty" ]; then
      VERIFICATION_FRESHNESS_REASON="working_tree_changed"
      return 0
    fi
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
  _verif_mtime=$(stat -c %Y "$verif_file" 2>/dev/null || stat -f %m "$verif_file" 2>/dev/null || true)
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