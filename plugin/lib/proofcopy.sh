#!/usr/bin/env bash
# The clean copy vbw prove runs on (docs/proof.md): a detached git worktree of
# HEAD inside the project, so uncommitted changes and untracked files change no
# proof result. Git-ignored paths (dependencies, env files) are copied in, never
# linked (a copy-on-write clone where the file system offers one, a plain copy
# where it refuses), so the copy shares no writable folder with the working
# folder. Build output is not environment: the copy builds its own, so no
# artifact of a proof points into the working folder or another copy.

# Build-output folder names (Node, Python, Rust, Go and the like), at any depth.
PROOFCOPY_BUILD_DIRS='target dist build bin out __pycache__ .pytest_cache .mypy_cache .ruff_cache .tox .next .nuxt .gradle coverage'

# proofcopy_is_build_dir PATH: PATH's last segment names a build folder.
proofcopy_is_build_dir() {
  local b=${1##*/} n
  for n in $PROOFCOPY_BUILD_DIRS; do
    [ "$b" != "$n" ] || return 0
  done
  return 1
}

# proofcopy_create: make the copy; sets PROOF_COPY (absolute path). Called
# directly, never in $(...), so the guard that removes it on interrupt holds.
proofcopy_create() {
  local dir p l t real
  dir=$(mktemp -d "$VBW_RUNTIME/proof.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$dir"
  PROOF_COPY="$dir/tree"
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  git -C "$VBW_ROOT" -c core.hooksPath=/dev/null worktree add -q --detach "$PROOF_COPY" HEAD > /dev/null 2>&1 \
    || vbw_die "cannot make a clean copy of the committed code (does the project have a commit?)"
  real=$(cd -P "$VBW_ROOT" && pwd -P) || vbw_die "cannot resolve $VBW_ROOT"
  while IFS= read -r -d '' p; do
    p=${p%/}
    case "$p" in .git | .git/* | .vbw | .vbw/*) continue ;; esac
    ! proofcopy_is_build_dir "$p" || continue
    [ ! -e "$PROOF_COPY/$p" ] && [ ! -L "$PROOF_COPY/$p" ] || continue
    mkdir -p "$PROOF_COPY/$(dirname "$p")"
    proofcopy_copy "$VBW_ROOT/$p" "$PROOF_COPY/$p" || { proofcopy_remove; vbw_die "cannot copy the ignored path $p into the clean copy (is it readable?)"; }
    while IFS= read -r -d '' l; do
      t=$(readlink "$PROOF_COPY/$l")
      case "$t" in /*) t=$(cd -P "$(dirname "$t")" 2> /dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$t")") || t=$(readlink "$PROOF_COPY/$l") ;; esac
      case "$t" in "$real" | "$real"/*)
        printf 'vbw: %s links into the working folder (%s); it is copied as a link\n' "$l" "$(readlink "$PROOF_COPY/$l")" >&2 ;;
      esac
    done < <(cd "$PROOF_COPY" && find "$p" -type l -print0)
  done < <(git -C "$VBW_ROOT" ls-files -z --others --ignored --exclude-standard --directory)
}

# proofcopy_norm PATH: PATH with . and .. folded away (no file system access).
proofcopy_norm() {
  local IFS=/ part out=() parts=()
  read -r -a parts <<< "$1"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      '' | .) ;;
      ..) [ ${#out[@]} -eq 0 ] || unset "out[$((${#out[@]} - 1))]" ;;
      *) out+=("$part") ;;
    esac
  done
  printf '/%s' "${out[*]-}"
}

# proofcopy_warn_stale: read-only scan of the working folder (git-ignored
# folders included, links never followed, .git and .vbw skipped) naming each
# link that points into this project's proof copies, with the repair. Says
# nothing when there is none. Never fails.
proofcopy_warn_stale() {
  local real l t n d r fix='re-run the project install command'
  real=$(cd -P "$VBW_ROOT" 2> /dev/null && pwd -P) || return 0
  { [ -f "$VBW_ROOT/pnpm-lock.yaml" ] || [ -f "$VBW_ROOT/pnpm-workspace.yaml" ]; } && fix='delete node_modules and run pnpm install'
  while IFS= read -r -d '' l; do
    t=$(readlink "$l") || continue
    case "$t" in /*) ;; *) t="$(cd -P "$(dirname "$l")" 2> /dev/null && pwd -P)/$t" ;; esac
    n=$(proofcopy_norm "$t")
    d=$n
    while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
    r=$(cd -P "$d" 2> /dev/null && pwd -P)${n#"$d"}
    case "$n:$r" in "$VBW_ROOT/.vbw/runtime/proof."* | "$real/.vbw/runtime/proof."* | *":$real/.vbw/runtime/proof."*)
      printf 'vbw: %s -> %s points into a proof copy of an earlier run; %s\n' "${l#./}" "$(readlink "$l")" "$fix" >&2 ;;
    esac
  done < <(cd "$VBW_ROOT" && find . \( -name .git -o -path ./.vbw \) -prune -o -type l -print0 2> /dev/null) || true
  return 0
}

# proofcopy_copy SRC DST: a copy-on-write clone first, a plain copy when the
# file system refuses; links inside stay links. A failed try leaves nothing.
proofcopy_copy() {
  local flag=--reflink=always
  [ "$(uname)" != Darwin ] || flag=-c
  cp -RP "$flag" "$1" "$2" 2> /dev/null && return 0
  rm -rf "$2" 2> /dev/null || true
  cp -RP "$1" "$2" 2> /dev/null && return 0
  chmod -R u+rwx "$2" 2> /dev/null || true
  rm -rf "$2"
  return 1
}

# proofcopy_remove: drop the worktree and whatever is left of the directory,
# read-only folders included (rm never follows a link out of the copy).
proofcopy_remove() {
  [ -n "${PROOF_COPY:-}" ] || return 0
  chmod -R u+rwx "$PROOF_COPY" 2> /dev/null || true
  git -C "$VBW_ROOT" worktree remove --force "$PROOF_COPY" > /dev/null 2>&1 || true
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  vbw_guard_drop "$(dirname "$PROOF_COPY")"
  PROOF_COPY=
}

# proofcopy_verify HASH RECORD: die naming every check file whose committed
# bytes differ from the approved ones.
proofcopy_verify() {
  local f bad=""
  [ "$(VBW_ROOT="$PROOF_COPY" contract_hash "$2")" != "$1" ] || return 0
  while IFS= read -r -d '' f; do
    cmp -s "$VBW_ROOT/$f" "$PROOF_COPY/$f" 2> /dev/null || bad="$bad $f"
  done < <(printf '%s' "$2" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  proofcopy_remove
  vbw_die "check files not committed as approved:${bad:- (the committed contract differs)}: commit them, then ask the user with the approval menu (AskUserQuestion)"
}
