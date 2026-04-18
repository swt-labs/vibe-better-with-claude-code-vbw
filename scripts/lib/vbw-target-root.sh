#!/usr/bin/env bash

# vbw-target-root.sh — Shared target root resolution for context scripts.
#
# These helpers let scripts that accept explicit planning/phase/plan paths resolve
# the intended workspace root and git root without depending on the caller's cwd.

vbw_candidate_dir_for_path() {
  local candidate="$1"

  [ -n "$candidate" ] || return 1
  [ -e "$candidate" ] || return 1

  if [ -d "$candidate" ]; then
    (
      cd "$candidate" 2>/dev/null && pwd -P 2>/dev/null
    ) || printf '%s\n' "$candidate"
  else
    local dir
    dir=$(dirname "$candidate")
    (
      cd "$dir" 2>/dev/null && pwd -P 2>/dev/null
    ) || printf '%s\n' "$dir"
  fi
}

vbw_walk_up_for_workspace_root() {
  local current="$1" next

  while :; do
    if [ "$(basename "$current")" = ".vbw-planning" ]; then
      dirname "$current"
      return 0
    fi

    if [ -d "$current/.vbw-planning" ]; then
      printf '%s\n' "$current"
      return 0
    fi

    if [ "$current" = "/" ]; then
      break
    fi

    next=$(dirname "$current")
    [ "$next" = "$current" ] && break
    current="$next"
  done

  return 1
}

vbw_resolve_target_root() {
  local explicit_scope="$1"
  shift || true

  local candidate candidate_dir pwd_dir

  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    candidate_dir=$(vbw_candidate_dir_for_path "$candidate" 2>/dev/null || true)
    [ -n "$candidate_dir" ] || continue

    if vbw_walk_up_for_workspace_root "$candidate_dir" 2>/dev/null; then
      return 0
    fi

    if git -C "$candidate_dir" rev-parse --is-inside-work-tree &>/dev/null; then
      git -C "$candidate_dir" rev-parse --show-toplevel 2>/dev/null || return 0
      return 0
    fi
  done

  if [ "$explicit_scope" != "1" ]; then
    pwd_dir=$(pwd -P 2>/dev/null || pwd)

    if vbw_walk_up_for_workspace_root "$pwd_dir" 2>/dev/null; then
      return 0
    fi

    if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
      git rev-parse --show-toplevel 2>/dev/null || return 0
      return 0
    fi
  fi

  return 1
}

vbw_resolve_target_git_root() {
  local explicit_scope="$1"
  shift || true

  local candidate candidate_dir

  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    candidate_dir=$(vbw_candidate_dir_for_path "$candidate" 2>/dev/null || true)
    [ -n "$candidate_dir" ] || continue

    if git -C "$candidate_dir" rev-parse --is-inside-work-tree &>/dev/null; then
      git -C "$candidate_dir" rev-parse --show-toplevel 2>/dev/null || return 0
      return 0
    fi
  done

  if [ "$explicit_scope" != "1" ] && command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    git rev-parse --show-toplevel 2>/dev/null || return 0
    return 0
  fi

  return 1
}

vbw_resolve_repo_path() {
  local root="$1" path="$2"

  if [ -z "$path" ]; then
    printf '\n'
    return 0
  fi

  case "$path" in
    /*)
      printf '%s\n' "$path"
      ;;
    *)
      if [ -n "$root" ]; then
        printf '%s/%s\n' "$root" "$path"
      else
        printf '%s\n' "$path"
      fi
      ;;
  esac
}

vbw_workspace_subpath_from_git_root() {
  local workspace_root="${1%/}" git_root="${2%/}"

  [ -n "$workspace_root" ] || return 1
  [ -n "$git_root" ] || return 1

  if [ "$workspace_root" = "$git_root" ]; then
    printf '\n'
    return 0
  fi

  case "$workspace_root/" in
    "$git_root"/*)
      printf '%s\n' "${workspace_root#"$git_root"/}"
      ;;
    *)
      return 1
      ;;
  esac
}

vbw_git_path_to_workspace_path() {
  local git_path="$1" workspace_root="$2" git_root="$3" workspace_subpath

  [ -n "$git_path" ] || return 1

  case "$git_path" in
    /*)
      printf '%s\n' "$git_path"
      return 0
      ;;
  esac

  workspace_subpath=$(vbw_workspace_subpath_from_git_root "$workspace_root" "$git_root" 2>/dev/null || true)

  if [ -z "$workspace_subpath" ]; then
    printf '%s\n' "$git_path"
    return 0
  fi

  case "$git_path" in
    "$workspace_subpath"/*)
      printf '%s\n' "${git_path#"$workspace_subpath"/}"
      ;;
    "$workspace_subpath")
      printf '.\n'
      ;;
    *)
      return 1
      ;;
  esac
}