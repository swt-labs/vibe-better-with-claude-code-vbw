#!/usr/bin/env bash
# Shared helpers for the vbw kernel. Sourced by bin/vbw; never executed alone.
# Exit codes: 0 ok, 1 error, 2 usage, 3 corrupt record, 4 record written by a newer VBW.

# vbw_out FORMAT [ARG...]: printf, run in a child of its own. A shell with a
# live child (the producer of a loop fed by a process substitution) never writes
# with a builtin itself: macOS /bin/bash 3.2 catches SIGCHLD without SA_RESTART,
# so a write waiting for a slow reader (a full pipe) fails with EINTR when that
# child exits, and its text is lost. The subshell has no child and no trap of
# its own, so nothing interrupts its write. tools/check-loop-writes.sh keeps
# every such loop to it (tests/output-child-exit.bats).
vbw_out() {
  # shellcheck disable=SC2059 # the caller's format, as printf's own
  (printf "$@")
}

# vbw_die MESSAGE [CODE]: say why, clean up, exit CODE (default 1). It can run
# anywhere, a loop's body included, so it says it through vbw_out.
vbw_die() {
  vbw_out 'vbw: %s\n' "$1" >&2
  vbw_guard_run
  if [ -n "${VBW_DIE_HOOK:-}" ]; then local h=$VBW_DIE_HOOK; VBW_DIE_HOOK=; "$h" || true; fi
  exit "${2:-1}"
}

# Interrupt-safe cleanup. Temporary files and held lock directories are
# registered here; INT, TERM and HUP remove them and exit (so the caller's own
# EXIT trap still runs), and so does vbw_die. An EXIT trap is installed only
# when the process has none (the vbw entry point), so a caller's EXIT trap is
# never replaced or cleared, and no trap text is ever evaluated.
VBW_GUARD_FILES=()
VBW_GUARD_LOCKS=()
VBW_GUARD_DIRS=()
VBW_GUARD_EXIT=0

# vbw_guard_add KIND PATH: remove PATH on interrupt, die or vbw_guard_drop.
# KIND is file, lock (a lock file, or the lock directory of an older VBW) or dir (a directory tree, rm -rf;
# rm never follows a symlink inside it).
vbw_guard_add() {
  local kind="$1" path="$2"
  case "$kind" in
    lock) VBW_GUARD_LOCKS+=("$path") ;;
    dir) VBW_GUARD_DIRS+=("$path") ;;
    *) VBW_GUARD_FILES+=("$path") ;;
  esac
  trap 'vbw_guard_run; exit 130' INT
  trap 'vbw_guard_run; exit 143' TERM
  trap 'vbw_guard_run; exit 129' HUP
  if [ "$VBW_GUARD_EXIT" -eq 0 ] && [ -z "$(trap -p EXIT)" ]; then
    trap vbw_guard_run EXIT
    VBW_GUARD_EXIT=1
  fi
}

# Forget everything registered (a subshell calls this: it owns none of it).
vbw_guard_reset() {
  VBW_GUARD_FILES=()
  VBW_GUARD_LOCKS=()
  VBW_GUARD_DIRS=()
  VBW_GUARD_EXIT=0
}

# Remove everything registered (files and locks with rm, an old lock directory with rmdir).
vbw_guard_run() {
  local p
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do rm -f "$p" 2>/dev/null || true; done
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do rm -f "$p" 2>/dev/null || rmdir "$p" 2>/dev/null || true; done
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do chmod -R u+rwx "$p" 2>/dev/null || true; rm -rf "$p" 2>/dev/null || true; done
  VBW_GUARD_FILES=()
  VBW_GUARD_LOCKS=()
  VBW_GUARD_DIRS=()
}

# vbw_guard_drop PATH: clean up one registered path now (file or lock dir);
# when nothing is left, the traps are removed again. A file or an empty lock
# folder costs one process (the gate's lock and place are given back between
# one unit and the next, T180); a registered tree is opened up, then removed.
vbw_guard_drop() {
  local p keep=() tree=''
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do [ "$p" != "$1" ] || tree=1; done
  if [ -n "$tree" ]; then
    { chmod -R u+rwx "$1"; rm -rf "$1"; } 2>/dev/null || true
  elif [ -d "$1" ] && [ ! -L "$1" ]; then
    rmdir "$1" 2>/dev/null || true
  elif [ -e "$1" ] || [ -L "$1" ]; then
    rm -f "$1" 2>/dev/null || true
  fi
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_FILES=(${keep[@]+"${keep[@]}"})
  keep=()
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_LOCKS=(${keep[@]+"${keep[@]}"})
  keep=()
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_DIRS=(${keep[@]+"${keep[@]}"})
  [ $(( ${#VBW_GUARD_FILES[@]} + ${#VBW_GUARD_LOCKS[@]} + ${#VBW_GUARD_DIRS[@]} )) -eq 0 ] || return 0
  trap - INT TERM HUP
  if [ "$VBW_GUARD_EXIT" -eq 1 ]; then trap - EXIT; VBW_GUARD_EXIT=0; fi
}

vbw_usage_error() {
  vbw_out 'vbw: %s\nusage: vbw <command> [args]   (vbw help for the list)\n' "$1" >&2
  exit 2
}

# The calling Claude Code session: VBW_SESSION_ID (skills pass ${CLAUDE_SESSION_ID}),
# else CLAUDE_CODE_SESSION_ID, else empty (unknown).
vbw_session() {
  printf '%s' "${VBW_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
}

vbw_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# This clone's own settings: $(git-common-dir)/vbw/settings.json (shared by the
# clone's worktrees, never in the shared record). Today: check_jobs, how many
# checks run at the same time (1 to 64; 1 is sequential). Without a setting
# the machine decides: three quarters of its processor cores. And sound, the
# panel's "needs you" voice: "off" or a folder name under assets/audio/ (the
# panel reads {"sound": "<value>"} from this file; unset means any voice).
vbw_clone_settings_file() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || vbw_die "not a git repository"
  printf '%s/vbw/settings.json\n' "$common"
}

# vbw_cores_ok N: N is a whole number of at least 1: digits only, no leading
# zero (it would read as octal), no sign, dot or trailing text.
vbw_cores_ok() {
  case "$1" in '' | *[!0-9]* | 0*) return 1 ;; esac
}

# vbw_cores: the processor core count, from the first of getconf, nproc and
# sysctl (found on PATH) that gives a whole number of at least 1; none gives
# "cannot be read" (status 1, no output).
vbw_cores() {
  local n
  n=$(getconf _NPROCESSORS_ONLN 2> /dev/null) || n=""
  vbw_cores_ok "$n" && { printf '%s\n' "$n"; return 0; }
  n=$(nproc 2> /dev/null) || n=""
  vbw_cores_ok "$n" && { printf '%s\n' "$n"; return 0; }
  n=$(sysctl -n hw.ncpu 2> /dev/null) || n=""
  vbw_cores_ok "$n" && { printf '%s\n' "$n"; return 0; }
  return 1
}

# vbw_claude_dir: the user's Claude config folder: CLAUDE_CONFIG_DIR when set,
# else ~/.config/claude-code when that folder exists, else ~/.claude.
vbw_claude_dir() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_CONFIG_DIR"
  elif [ -d "$HOME/.config/claude-code" ]; then
    printf '%s\n' "$HOME/.config/claude-code"
  else
    printf '%s\n' "$HOME/.claude"
  fi
}

# vbw_machine_limit: three quarters of the cores, rounded down, 1 to 64; 1 when
# the count cannot be read. No setting, no environment override.
vbw_machine_limit() {
  local n cores
  cores=$(vbw_cores) || cores=""
  if [ -z "$cores" ]; then printf '1\n'; return 0; fi
  n=$((cores * 3 / 4))
  [ "$n" -ge 1 ] || n=1
  [ "$n" -le 64 ] || n=64
  printf '%s\n' "$n"
}

# vbw_check_jobs_set_value: the check_jobs value set in this clone's settings,
# or nothing when missing, damaged or out of range.
vbw_check_jobs_set_value() {
  local file n
  file=$(vbw_clone_settings_file) || return 1
  n=$(jq -r '.check_jobs // empty' "$file" 2> /dev/null) || n=""
  case "$n" in
    [1-9] | [1-5][0-9] | 6[0-4]) printf '%s\n' "$n" ;;
  esac
  return 0
}

# vbw_check_jobs: the one reader of check_jobs: a valid set value, else three
# quarters of the cores (rounded down, 1 to 64), 1 when the count cannot be read.
vbw_check_jobs() {
  local n
  n=$(vbw_check_jobs_set_value) || return 1
  if [ -n "$n" ]; then printf '%s\n' "$n"; return 0; fi
  vbw_machine_limit
}

# vbw_check_jobs_source: "set" or "machine default".
vbw_check_jobs_source() {
  local n
  n=$(vbw_check_jobs_set_value) || return 1
  if [ -n "$n" ]; then printf 'set\n'; else printf 'machine default\n'; fi
}

# vbw_clone_setting_set KEY JSON|default: atomic, locked change of one key of
# this clone's settings file; "default" removes the key, JSON is the new value.
vbw_clone_setting_set() {
  local file tmp lock
  file=$(vbw_clone_settings_file)
  mkdir -p "${file%/*}"
  lock="${file%/*}/settings.lock"
  vbw_lock_take "$lock" "this clone's settings"
  [ -f "$file" ] || printf '{}\n' > "$file"
  tmp=$(mktemp "${file%/*}/settings.XXXXXX") || vbw_die "cannot write ${file%/*}"
  vbw_guard_add file "$tmp"
  if [ "$2" = default ]; then
    jq --arg k "$1" 'del(.[$k])' "$file" > "$tmp" 2> /dev/null
  else
    jq --arg k "$1" --argjson n "$2" '.[$k] = $n' "$file" > "$tmp" 2> /dev/null
  fi || vbw_die "this clone's settings file is damaged ($file); delete it and set again"
  mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$lock"
}

# vbw_check_jobs_set N|default: atomic, locked change of check_jobs.
vbw_check_jobs_set() {
  vbw_clone_setting_set check_jobs "$1"
}

# Absolute path of the enclosing git repository, or die.
vbw_git_root() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || vbw_die "not a git repository (VBW needs git: it commits with provenance)"
  printf '%s\n' "$root"
}

# Sets VBW_ROOT, VBW_DIR, VBW_RECORD and VBW_RUNTIME for the current project.
vbw_project() {
  VBW_ROOT=$(vbw_git_root)
  VBW_DIR="$VBW_ROOT/.vbw"
  VBW_RECORD="$VBW_DIR/record.json"
  VBW_RUNTIME="$VBW_DIR/runtime"
}

vbw_require_project() {
  local up l
  vbw_project
  # Inside a submodule (its .git is a file whose gitdir: line names a folder under
  # modules/) with no record of its own, the project is the nearest folder above
  # it holding .git and a record: the walk the guards and the status line make
  # (hooks/project.sh), so a session there is guarded as the project the commands
  # work on. A clone inside the project (its .git a folder) and a linked worktree
  # inside it (its gitdir worktrees/NAME) stay projects of their own. The command
  # then runs from that project's folder, so every path and bare git command
  # reads the project, as from its own folder.
  up=$VBW_ROOT
  while [ "$up" != / ] && [ -f "$up/.git" ] && [ ! -f "$up/.vbw/record.json" ]; do
    l=; read -r l < "$up/.git" || :
    case "$l" in */modules/*) ;; *) break ;; esac
    case "${l##*/worktrees/}" in "$l" | */*) ;; *) break ;; esac
    up=${up%/*}
    up=${up:-/}
    while [ "$up" != / ] && [ ! -e "$up/.git" ]; do up=${up%/*}; up=${up:-/}; done
  done
  if [ "$up" != "$VBW_ROOT" ] && [ -f "$up/.vbw/record.json" ] && [ -e "$up/.git" ]; then
    VBW_ROOT=$up
    VBW_DIR="$VBW_ROOT/.vbw"
    VBW_RECORD="$VBW_DIR/record.json"
    VBW_RUNTIME="$VBW_DIR/runtime"
    cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  fi
  [ -f "$VBW_RECORD" ] || vbw_die "not a VBW project (run /vbw:init)"
  mkdir -p "$VBW_RUNTIME"
}

# Repositories inside the project (docs/workflows.md, "Submodules"). A file is
# tracked by the repository whose top folder is the nearest folder at or above it
# that holds .git, the project's own repository when none below the project does
# (the rule the guards use, hooks/project.sh); a path whose folder does not exist
# yet is read the same way, folder by folder. A repository is named by its folder
# relative to the project, "" for the project itself. A folder holding .git that
# a symbolic link takes outside the project is no repository of the project: VBW
# acts on nothing outside it, and its files are the project's, whose git refuses
# a path beyond a symbolic link (the guards judge such a path by its name too).

# vbw_inside DIR: the project-relative DIR is a folder inside the project, symbolic
# links resolved. One subshell per folder asked, remembered for the process.
vbw_inside() {
  local p k="$VBW_ROOT/$1" root
  case "${VBW_INSIDE:-}" in *$'\037'"$k"$'\037'*) return 0 ;; esac
  root=$(cd -P "$VBW_ROOT" 2> /dev/null && pwd -P) || return 1
  p=$(cd -P "$k" 2> /dev/null && pwd -P) || return 1
  case "$p" in "$root"/?*) VBW_INSIDE="${VBW_INSIDE:-$'\037'}$k"$'\037' ;; *) return 1 ;; esac
}

# vbw_repos FILE...: sets VBW_REPOS, the repositories that track the
# project-relative FILEs (first seen first), VBW_REPO_OF, each FILE's
# repository, in FILE order, and VBW_PATHS, the FILEs (vbw_in_repo reads them).
# Builtins only, but for one vbw_inside per folder holding .git.
vbw_repos() {
  local f d x seen
  VBW_REPOS=()
  VBW_REPO_OF=()
  VBW_PATHS=(${@+"$@"})
  for f in "$@"; do
    d=${f%/}
    case "/$d/" in */../* | */./*) d= ;; esac
    while [ -n "$d" ]; do
      [ -d "$VBW_ROOT/$d" ] && [ -e "$VBW_ROOT/$d/.git" ] && vbw_inside "$d" && break
      case "$d" in */*) d=${d%/*} ;; *) d= ;; esac
    done
    VBW_REPO_OF+=("$d")
    seen=0
    for x in ${VBW_REPOS[@]+"${VBW_REPOS[@]}"}; do [ "$x" != "$d" ] || { seen=1; break; }; done
    [ "$seen" = 1 ] || VBW_REPOS+=("$d")
  done
}

# vbw_rel REPO FILE: sets VBW_REL, the project-relative FILE relative to the
# repository REPO that tracks it ("." for REPO's top folder). Builtins only: no
# subshell per file.
vbw_rel() {
  if [ -z "$1" ]; then VBW_REL=$2
  elif [ "${2%/}" = "$1" ]; then VBW_REL=.
  else VBW_REL=${2#"$1"/}; fi
}

# vbw_plan_paths ENTRY...: vbw_repos over the plan file ENTRYs and, for each
# folder entry (ending in /) or *, each checked-out submodule inside it, as
# "SUB/": the folder's own entry reaches only the files of the repository that
# holds the folder, and a submodule's files are its own repository's (covers()
# counts them as the folder's). No folder entry: no git command.
vbw_plan_paths() {
  local e s want=0 subs=() all=("$@")
  for e in "$@"; do case "$e" in */ | '*') want=1 ;; esac; done
  if [ "$want" = 1 ]; then
    while IFS= read -r -d '' s; do subs+=("$s"); done < <(vbw_subs)
    for s in ${subs[@]+"${subs[@]}"}; do
      for e in "$@"; do
        e=${e#./}
        case "$e" in
          '*') all+=("$s/"); break ;;
          */) if [ "$e" != "$s/" ] && [ "${s#"$e"}" != "$s" ]; then all+=("$s/"); break; fi ;;
        esac
      done
    done
  fi
  vbw_repos ${all[@]+"${all[@]}"}
}

# vbw_in_repo REPO: of the files vbw_repos was given (VBW_PATHS), those REPO
# tracks, relative to REPO (vbw_rel), NUL-ended.
vbw_in_repo() {
  local r="$1" f i=0
  for f in ${VBW_PATHS[@]+"${VBW_PATHS[@]}"}; do
    if [ "${VBW_REPO_OF[$i]}" = "$r" ]; then
      vbw_rel "$r" "$f"
      printf '%s\0' "$VBW_REL"
    fi
    i=$((i + 1))
  done
}

# vbw_changed REPO PATH...: of the pathspecs PATH (relative to REPO), the files
# that differ from REPO's HEAD (changed, staged or not, or deleted) as "c", then
# the new ones git does not ignore as "n", each "c|n NUL FILE NUL", FILE relative
# to REPO. A repository's folder inside REPO (a moved submodule pointer) is never
# listed: VBW commits inside a submodule, never its pointer in the one above.
vbw_changed() {
  local d="$VBW_ROOT${1:+/$1}" f
  shift
  git -C "$d" diff --name-only -z HEAD -- "$@" | while IFS= read -r -d '' f; do
    [ -e "$d/$f/.git" ] || printf 'c\0%s\0' "$f"
  done
  git -C "$d" ls-files -z --others --exclude-standard -- "$@" | while IFS= read -r -d '' f; do
    printf 'n\0%s\0' "$f"
  done
}

# vbw_commit_paths MESSAGE TRAILERS FILE...: commit the project-relative plan
# FILEs that changed (vbw_changed; a folder entry covers the submodules inside it,
# vbw_plan_paths), one commit per repository that tracks one of them, each with
# MESSAGE and, when not empty, the trailer paragraph TRAILERS. Only those files
# are committed (--only): the rest of each repository's index and working tree
# stays as it was. Sets VBW_COMMITTED (the files committed, project-relative) and
# VBW_COMMITS (per commit "REPO<TAB>HASH<TAB>COUNT"). Returns 1, committing
# nothing, when no FILE changed. Dies, committing nothing, when a repository
# inside the project with changes is on no branch (its commit would be dropped by
# the next submodule update). When a repository's git add or commit fails, the
# repositories after it are not tried: returns 2 with VBW_COMMIT_ERR, one line
# naming the repository that failed and each commit already made (still in
# VBW_COMMITTED and VBW_COMMITS, for the caller to escalate); the caller says how
# to finish (its command again commits only what is still changed, since what was
# committed no longer differs). The caller holds the project lock.
vbw_commit_paths() {
  local msg="$1" trailers="$2" r t f rels changed untracked hash c cr n ok done_say=""
  shift 2
  VBW_COMMITTED=()
  VBW_COMMITS=()
  VBW_COMMIT_ERR=
  vbw_plan_paths "$@"
  local todo=()
  for r in "${VBW_REPOS[@]}"; do
    rels=()
    while IFS= read -r -d '' f; do rels+=("$f"); done < <(vbw_in_repo "$r")
    [ -n "$(vbw_changed "$r" "${rels[@]}" | tr -d '\0')" ] || continue
    [ -z "$r" ] || git -C "$VBW_ROOT/$r" symbolic-ref -q HEAD > /dev/null \
      || vbw_die "$r is on no branch: a commit there would be lost at the next submodule update
Next: put it on a branch (git -C $r switch BRANCH), then commit again"
    todo+=("$r")
  done
  [ ${#todo[@]} -gt 0 ] || return 1
  for r in "${todo[@]}"; do
    rels=() changed=() untracked=()
    while IFS= read -r -d '' f; do rels+=("$f"); done < <(vbw_in_repo "$r")
    while IFS= read -r -d '' t && IFS= read -r -d '' f; do
      changed+=("$f")
      [ "$t" = c ] || untracked+=("$f")
    done < <(vbw_changed "$r" "${rels[@]}")
    ok=1
    [ ${#untracked[@]} -eq 0 ] || git -C "$VBW_ROOT${r:+/$r}" add -- "${untracked[@]}" || ok=0
    if [ "$ok" = 1 ] && [ -n "$trailers" ]; then
      git -C "$VBW_ROOT${r:+/$r}" commit --quiet --only -m "$msg" -m "$trailers" -- "${changed[@]}" || ok=0
    elif [ "$ok" = 1 ]; then
      git -C "$VBW_ROOT${r:+/$r}" commit --quiet --only -m "$msg" -- "${changed[@]}" || ok=0
    fi
    if [ "$ok" = 1 ]; then
      hash=$(git -C "$VBW_ROOT${r:+/$r}" rev-parse --short HEAD)
      VBW_COMMITS+=("$r	$hash	${#changed[@]}")
      for f in "${changed[@]}"; do VBW_COMMITTED+=("${r:+$r/}$f"); done
      continue
    fi
    for c in ${VBW_COMMITS[@]+"${VBW_COMMITS[@]}"}; do
      cr=${c%%	*}
      t=${c#*	}
      n=${t#*	}
      done_say="$done_say${done_say:+, }${t%%	*} in ${cr:-the project} ($n file$([ "$n" -eq 1 ] || printf s))"
    done
    # shellcheck disable=SC2034 # read by the callers (cmd-commit.sh, record.sh)
    VBW_COMMIT_ERR="git commit failed in ${r:-the project}${done_say:+; already committed: $done_say}"
    return 2
  done
}

# vbw_subs [REPO]: the submodules of the HEAD of the project (or of its repository
# REPO, a folder relative to the project) that are checked out, one level deep,
# "PATH\0" each, relative to that repository: the paths .gitmodules names that
# HEAD holds as a submodule and whose folder holds .git. No .gitmodules: nothing,
# no git command.
# shellcheck disable=SC2120 # cmd-ship.sh passes REPO
vbw_subs() {
  local line paths=() top="$VBW_ROOT${1:+/$1}"
  [ -f "$top/.gitmodules" ] || return 0
  # -z: "key NEWLINE value NUL" per entry.
  while IFS= read -r -d '' line; do
    line=${line#*$'\n'}
    # Inside the project only: a checkout swapped for a symbolic link out is no submodule.
    if [ -e "$top/$line/.git" ] && vbw_inside "${1:+$1/}$line"; then paths+=("$line"); fi
  done < <(git -C "$top" config -z -f .gitmodules --get-regexp '^submodule\..*\.path$' 2> /dev/null)
  [ ${#paths[@]} -gt 0 ] || return 0
  git -C "$top" ls-tree -z HEAD -- "${paths[@]}" 2> /dev/null | while IFS= read -r -d '' line; do
    case "$line" in "160000 commit "*) printf '%s\0' "${line#*$'\t'}" ;; esac
  done
}

# vbw_commits_say ID: one line per commit vbw_commit_paths made for ID.
vbw_commits_say() {
  local c r rest hash n
  for c in "${VBW_COMMITS[@]}"; do
    r=${c%%	*}
    rest=${c#*	}
    hash=${rest%%	*}
    n=${rest#*	}
    printf 'committed %s%s for %s (%d file%s)\n' "$hash" "${r:+ in $r}" "$1" "$n" "$([ "$n" -eq 1 ] || printf s)"
  done
}

# SHA-256 hex digest of stdin (GNU coreutils or BSD/macOS shasum).
vbw_sha256() {
  local out
  if command -v sha256sum > /dev/null 2>&1; then
    out=$(sha256sum)
  else
    out=$(shasum -a 256)
  fi
  printf '%s\n' "${out%% *}"
}

# The git tree id of the project's files as they are now (tracked and new,
# committed or not; ignored files, .vbw/ and a kept VBW 1 .vbw-planning/
# excluded): a content fingerprint that no commit changes. Built in a temporary
# index seeded from the real one, so only changed files are rehashed; the
# user's index and files are untouched.
# vbw_head_tree: the tree of the committed code (HEAD, without .vbw and
# .vbw-planning), which is what vbw prove runs on: the fingerprint of what a
# proof proved. Prints nothing when there is no commit yet.
# A checked-out submodule counts at its own HEAD (vbw_subs), not at the commit
# the project points it at: what the proof copy holds (lib/proofcopy.sh).
vbw_head_tree() {
  local idx status p sha subs=()
  git -C "$VBW_ROOT" rev-parse -q --verify HEAD > /dev/null 2>&1 || return 0
  while IFS= read -r -d '' p; do
    sha=$(git -C "$VBW_ROOT/$p" rev-parse -q --verify HEAD 2> /dev/null) && subs+=("160000,$sha,$p")
  done < <(vbw_subs)
  idx=$(mktemp "$VBW_RUNTIME/index.XXXXXX") || return 1
  vbw_guard_add file "$idx"
  (
    cd "$VBW_ROOT" || exit 1
    export GIT_INDEX_FILE="$idx"
    git read-tree HEAD || exit 1
    for p in ${subs[@]+"${subs[@]}"}; do git update-index --cacheinfo "$p" || exit 1; done
    git rm -r -q --cached --ignore-unmatch -- .vbw .vbw-planning > /dev/null 2>&1 &&
      git write-tree
  )
  status=$?
  vbw_guard_drop "$idx"
  return $status
}

vbw_code_tree() {
  local idx real
  idx=$(mktemp "$VBW_RUNTIME/index.XXXXXX") || return 1
  vbw_guard_add file "$idx"
  real=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-path index)
  if [ -f "$real" ]; then cp "$real" "$idx"; else rm -f "$idx"; fi
  (
    cd "$VBW_ROOT" || exit 1
    export GIT_INDEX_FILE="$idx"
    # git add fails on an exclude naming an ignored path (#695); an ignored
    # folder needs none, since add -A skips it and git rm drops its tracked files.
    local ignored dir
    local -a skip=()
    ignored=$(git check-ignore --no-index -- .vbw .vbw-planning 2> /dev/null)
    for dir in .vbw .vbw-planning; do
      case "
$ignored
" in *"
$dir
"*) ;; *) skip+=(":(exclude)$dir") ;; esac
    done
    git add -A -- . ${skip[@]+"${skip[@]}"} > /dev/null 2>&1 &&
      git rm -r -q --cached --ignore-unmatch -- .vbw .vbw-planning > /dev/null 2>&1 &&
      git write-tree
  )
  local status=$?
  vbw_guard_drop "$idx"
  return $status
}

# Modification time in epoch seconds. GNU stat first: on Linux, BSD's `stat -f`
# means "file system status" and succeeds with other output, while macOS rejects
# GNU's `-c`. Only a number is ever returned (0 when it cannot be read).
vbw_mtime() {
  local t
  t=$(stat -c %Y "$1" 2>/dev/null) || t=$(stat -f %m "$1" 2>/dev/null) || t=0
  case "$t" in "" | *[!0-9]*) t=0 ;; esac
  printf '%s\n' "$t"
}

# vbw_mtime_newest DIR: the newest modification time (epoch seconds) of the files
# under DIR, links not followed (0 when none can be read). One pass: find hands
# stat many paths per call, in the flavour vbw_mtime uses (GNU first), so a tree of
# 100,000 files (node_modules) takes seconds, not a process per file. An unreadable
# folder is skipped, as before.
vbw_mtime_newest() {
  local fmt=-c spec=%Y
  stat -c %Y "$1" > /dev/null 2>&1 || { fmt=-f; spec=%m; }
  { find "$1" ! -type d -exec stat "$fmt" "$spec" {} + 2> /dev/null || true; } \
    | awk '/^[0-9]+$/ && $1 + 0 > m { m = $1 + 0 } END { printf "%.0f\n", m }'
}

# vbw_stamp_newer DIR FILE...: gives each FILE (a path under DIR) a modification
# time one second later than the newest file under DIR, build output included. The
# time comes from the files' times, never from the clock, so it holds when a file is
# stamped ahead of now. A missing FILE is left missing. The stamp is written and read
# in UTC: a local one in the hour a clock change repeats names two moments.
vbw_stamp_newer() {
  local dir="$1" newest t f stamp
  shift
  newest=$(vbw_mtime_newest "$dir")
  case "$newest" in "" | *[!0-9]*) newest=0 ;; esac
  t=$((newest + 1))
  stamp=$(TZ=UTC0 date -d "@$t" +%Y%m%d%H%M.%S 2> /dev/null) || stamp=$(TZ=UTC0 date -r "$t" +%Y%m%d%H%M.%S 2> /dev/null) || return 0
  for f in "$@"; do
    if [ -e "$dir/$f" ] || [ -L "$dir/$f" ]; then TZ=UTC0 touch -h -t "$stamp" "$dir/$f" 2> /dev/null || TZ=UTC0 touch -t "$stamp" "$dir/$f" 2> /dev/null || true; fi
  done
}

# vbw_dirty_files FILE...: those of the project-relative FILEs that differ from
# HEAD or are new, comma-separated, each read in the repository that tracks it
# (vbw_plan_paths: a folder entry covers the submodules inside it; vbw_changed).
vbw_dirty_files() {
  [ $# -gt 0 ] || return 0
  local f r t rels out=""
  vbw_plan_paths "$@"
  for r in "${VBW_REPOS[@]}"; do
    rels=()
    while IFS= read -r -d '' f; do rels+=("$f"); done < <(vbw_in_repo "$r")
    while IFS= read -r -d '' t && IFS= read -r -d '' f; do out="$out${out:+, }${r:+$r/}$f"; done \
      < <(vbw_changed "$r" "${rels[@]}")
  done
  printf '%s' "$out"
}

VBW_MIN_JQ=1.7

# version_at_least HAVE NEED: dotted numeric comparison.
version_at_least() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$2" ]
}

# vbw_jq_floor: read `jq --version` once and set VBW_JQ_VERSION (empty when jq is
# missing), VBW_JQ_MSG and VBW_JQ_FIX. Returns 1 for a missing jq or one below
# VBW_MIN_JQ, 0 otherwise. A missing jq never ends a shell running under set -e.
vbw_jq_floor() {
  local raw=""
  raw=$(jq --version 2> /dev/null) || raw=""
  VBW_JQ_VERSION=$(printf '%s' "$raw" | sed 's/^jq-//; s/-.*//')
  VBW_JQ_MSG="" VBW_JQ_FIX=""
  if [ -z "$VBW_JQ_VERSION" ]; then
    VBW_JQ_MSG="jq is missing"
    VBW_JQ_FIX="install jq (brew install jq / apt install jq)"
    return 1
  fi
  if ! version_at_least "$VBW_JQ_VERSION" "$VBW_MIN_JQ"; then
    VBW_JQ_MSG="jq $VBW_JQ_VERSION is too old (VBW needs $VBW_MIN_JQ or later)"
    VBW_JQ_FIX="a current jq from github.com/jqlang/jq/releases; on Debian 12: apt install -t bookworm-backports jq"
    return 1
  fi
  return 0
}

# vbw_require_jq: vbw_jq_floor, and on failure the message and its fix on stderr.
vbw_require_jq() {
  vbw_jq_floor && return 0
  vbw_out 'vbw: %s\n    fix: %s\n' "$VBW_JQ_MSG" "$VBW_JQ_FIX" >&2
  return 1
}
