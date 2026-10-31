# shellcheck shell=bash
# Sourced by the hook scripts and the status line (docs/guards.md): the one
# definition, for them, of the project a session belongs to. The guard commands
# in hooks.json repeat the same loops inline, so a missing file can never stop
# a guard. Every part of VBW finds the project the way the kernel does
# (vbw_require_project: the git top, then the same walk up from a submodule), so
# a session started in a subfolder of a VBW project, or in a submodule of one
# with no record of its own, is a VBW session.

# vbw_project_of DIR: sets root to the project of a session started in DIR: the
# nearest folder at or above DIR that holds .git (a folder, or the file of a
# linked worktree or a submodule), never above /; DIR itself when none does.
# When that folder is a submodule (its .git is a file whose gitdir: line names a
# folder under modules/, not a linked worktree's worktrees/NAME) and it has no
# .vbw/record.json, the nearest folder above it holding .git and a record is the
# project, as for the kernel; a clone inside the project (its .git a folder) and
# a linked worktree inside it stay projects of their own. No process: [ -e ]
# tests, read and parameter expansion, for the hot paths. It is a VBW project
# when $root/.vbw/record.json exists.
# shellcheck disable=SC2034 # root is the function's answer, read by the caller
vbw_project_of() {
  root=$1
  local d=$1 l
  while [ "$d" != / ] && [ -n "$d" ] && [ ! -e "$d/.git" ]; do
    case "$d" in */*) d=${d%/*}; d=${d:-/} ;; *) d=/ ;; esac
  done
  [ -e "$d/.git" ] || return 0
  root=$d
  while [ "$d" != / ] && [ -f "$d/.git" ] && [ ! -f "$d/.vbw/record.json" ]; do
    l=; read -r l < "$d/.git" || :
    case "$l" in */modules/*) ;; *) break ;; esac
    case "${l##*/worktrees/}" in "$l" | */*) ;; *) break ;; esac
    case "$d" in */*) d=${d%/*}; d=${d:-/} ;; *) d=/ ;; esac
    while [ "$d" != / ] && [ ! -e "$d/.git" ]; do
      case "$d" in */*) d=${d%/*}; d=${d:-/} ;; *) d=/ ;; esac
    done
  done
  [ ! -f "$d/.vbw/record.json" ] || [ ! -e "$d/.git" ] || root=$d
}

# vbw_vbw_above DIR: sets vbwdir to the nearest folder at or above DIR that holds
# a .vbw folder, never above /; empty when none does. Walked like vbw_project_of,
# no process, so the hand-back outside a VBW project stays cheap.
# shellcheck disable=SC2034 # vbwdir is the function's answer, read by the caller
vbw_vbw_above() {
  vbwdir=""
  local d=$1
  while [ -n "$d" ]; do
    if [ -d "$d/.vbw" ]; then vbwdir=$d; return 0; fi
    [ "$d" != / ] || return 0
    case "$d" in */*) d=${d%/*}; d=${d:-/} ;; *) return 0 ;; esac
  done
}
