#!/usr/bin/env bash
# The clean copy vbw prove runs on (docs/proof.md): a detached git worktree of
# HEAD inside the project, so uncommitted changes and untracked files change no
# proof result. Git-ignored paths (dependencies, env files) are copied in, never
# linked (a copy-on-write clone where the file system offers one, a plain copy
# where it refuses), so the copy shares no writable folder with the working
# folder. Build output is not environment: the copy builds its own, so no
# artifact of a proof points into the working folder or another copy.
#
# A checked-out submodule (vbw_subs) gets a detached worktree of its own HEAD in
# its folder of the copy, and its own ignored paths are copied in the same way:
# vbw commit commits there and leaves the project's pointer where it was
# (docs/workflows.md, "Submodules"), so its HEAD is its committed code.
#
# A copy's folder is .vbw/runtime/proof.PID.XXXXXX: PID is the vbw process that
# made it. The next proof (proofcopy_create_slots) removes each copy whose owner
# has ended (kill -0 fails), never one whose owner runs. A copy without an owner
# part (proof.XXXXXX, an older VBW) goes only when over 24 hours old. A dead
# copy is first claimed by one atomic mv to proof.$$.swept-<its name>, so a
# second cleanup sees a live owner and leaves it, and a cleanup killed partway
# leaves a folder whose owner has ended. A copy that will not go prints one
# warning line and the proof goes on.
#
# Left out (R205): the paths listed under ## Clean copy in .vbw/spec.md (the
# record's project.leave_out) are not copied in: a listed path, or any ignored
# path under a listed folder, is skipped in every clean copy; a listed path with
# nothing at it matches nothing. Every other ignored path is still copied.
#
# One line about a plain copy (R206): when the copies of a command took the
# plain way (no copy-on-write clone) for more than 500 MB of ignored data
# (VBW_PROOFCOPY_PLAIN_KB, a test-only variable, lowers that threshold; equal
# is silent), proofcopy_create_slots prints one "vbw:" line on stderr naming the
# three largest top-level ignored paths with their sizes and the way out (the
# ## Clean copy list in .vbw/spec.md). The sizes (du -sk on the source) are
# read once per command, while the first copy is made, and only for a plain
# copy. The line changes no verdict, evidence, record or exit code.

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

# proofcopy_slots WORK: how many copies to make for WORK pieces of work: one per
# parallel slot, as many as check_jobs allows and the work needs (at least 1).
proofcopy_slots() {
  local n
  n=$(vbw_check_jobs) || n=1
  [ "$1" -ge "$n" ] || n=$1
  [ "$n" -ge 1 ] || n=1
  printf '%s\n' "$n"
}

# proofcopy_create: make the copy; sets PROOF_COPY (absolute path). Called
# directly, never in $(...), so the guard that removes it on interrupt holds.
proofcopy_create() {
  proofcopy_create_slots 1
}

# proofcopy_create_slots N: make N copies, each made like the single one; sets
# PROOF_COPIES (all of them) and PROOF_COPY (the first). Called directly, never
# in $(...). proofcopy_remove removes every one, and so does an interrupt.
proofcopy_create_slots() {
  local i
  PROOF_COPIES=()
  proofcopy_sweep
  for ((i = 0; i < $1; i++)); do proofcopy_make; done
  PROOF_COPY=${PROOF_COPIES[0]}
  proofcopy_plain_say
}

PROOFCOPY_HOW=''
PROOFCOPY_LEFT=()
PROOFCOPY_SIZES=''
PROOFCOPY_SAID=''

# proofcopy_plain_say: once per process, sum the plain-copy sizes the first
# copy recorded and print the one line when they exceed the threshold; then
# drop the scratch file. Never fails, never changes the caller's result.
proofcopy_plain_say() {
  local f=$PROOFCOPY_SIZES total=0 limit=${VBW_PROOFCOPY_PLAIN_KB:-512000} list='' n kb k=0
  PROOFCOPY_SIZES=''
  [ -n "$f" ] && [ -f "$f" ] || return 0
  if [ -z "$PROOFCOPY_SAID" ]; then
    PROOFCOPY_SAID=1
    case "$limit" in '' | *[!0-9]*) limit=512000 ;; esac
    total=$(awk -F'\t' '$1 == "plain" {t += $3} END {printf "%d", t}' "$f" 2> /dev/null) || total=0
    if [ "${total:-0}" -gt "$limit" ] 2> /dev/null; then
      while IFS=$'\t' read -r n kb; do
        [ "${kb:-0}" -gt 0 ] || continue
        [ "$k" -lt 3 ] || break
        list="$list${list:+, }$n $(proofcopy_fmt_kb "$kb")"
        k=$((k + 1))
      done < <(awk -F'\t' '$1 == "plain" {s[$2] += $3} END {for (n in s) printf "%s\t%d\n", n, s[n]}' "$f" 2> /dev/null | sort -t$'\t' -k2,2nr -k1,1)
      vbw_out 'vbw: %s of git-ignored data was copied file by file (the disk offers no instant clone): %s; list them under ## Clean copy in .vbw/spec.md, then vbw spec sync\n' "$(proofcopy_fmt_kb "$total")" "$list" >&2
    fi
  fi
  rm -f "$f" 2> /dev/null || true
  vbw_guard_drop "$f"
  return 0
}

# proofcopy_fmt_kb KB: KB as MB (below 1 GB) or GB, one decimal, integer maths.
proofcopy_fmt_kb() {
  local t
  if [ "$1" -lt 1048576 ]; then
    t=$(($1 * 10 / 1024))
    printf '%d.%d MB' "$((t / 10))" "$((t % 10))"
  else
    t=$(($1 * 10 / 1048576))
    printf '%d.%d GB' "$((t / 10))" "$((t % 10))"
  fi
}

# proofcopy_note PATH: while the first copy of the command is made, record the
# way the entry was copied and, for a plain copy, its size (du -sk on the
# source) in the per-process scratch file. Never fails.
proofcopy_note() {
  local p=$1 name kb=''
  [ -n "$PROOFCOPY_SIZES" ] || return 0
  name=${p%%/*}
  [ "$name" = "$p" ] && [ ! -d "$VBW_ROOT/$p" ] || name="$name/"
  if [ "$PROOFCOPY_HOW" = plain ]; then
    kb=$(du -sk "$VBW_ROOT/$p" 2> /dev/null | awk 'NR == 1 {printf "%d", $1}') || kb=0
    : "${kb:=0}"
  fi
  printf '%s\t%s\t%s\n' "$PROOFCOPY_HOW" "$name" "$kb" >> "$PROOFCOPY_SIZES" 2> /dev/null || true
  return 0
}

# proofcopy_sweep: remove the proof copies whose owner has ended. Never fails.
proofcopy_sweep() {
  local d n rest pid claim
  for d in "$VBW_RUNTIME"/proof.*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    n=${d##*/}
    rest=${n#proof.}
    pid=${rest%%.*}
    if [ "$pid" != "$rest" ] && [ -n "${rest#*.}" ] && [ -n "$pid" ] && [ -z "${pid//[0-9]/}" ]; then
      ! kill -0 "$pid" 2> /dev/null || continue
    else
      [ -n "$(find "$d" -maxdepth 0 -mmin +1440 -print 2> /dev/null)" ] || continue
    fi
    claim="$VBW_RUNTIME/proof.$$.swept-$n"
    [ ! -e "$claim" ] || continue
    mv "$d" "$claim" 2> /dev/null || continue
    chmod -R u+rwx "$claim" > /dev/null 2>&1 || true
    rm -rf "$claim" > /dev/null 2>&1 || true
    git -C "$VBW_ROOT" worktree prune > /dev/null 2>&1 || true
    proofcopy_prune_subs
    [ ! -e "$claim" ] || printf 'vbw: cannot remove the leftover proof copy %s; remove it by hand\n' ".vbw/runtime/${claim##*/}" >&2
  done
  return 0
}

# proofcopy_make: one more copy, added to PROOF_COPIES.
proofcopy_make() {
  local dir p real copy first='' l
  PROOFCOPY_LEFT=()
  dir=$(mktemp -d "$VBW_RUNTIME/proof.$$.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$dir"
  copy="$dir/tree"
  if [ "${#PROOF_COPIES[@]}" -eq 0 ]; then first=1; proofcopy_note_open; fi
  PROOF_COPIES+=("$copy")
  PROOF_COPY=$copy
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  git -C "$VBW_ROOT" -c core.hooksPath=/dev/null worktree add -q --detach "$copy" HEAD > /dev/null 2>&1 \
    || { proofcopy_remove; vbw_die "cannot make a clean copy of the committed code (does the project have a commit?)"; }
  # Each checked-out submodule: a detached worktree of its own HEAD (its committed
  # code, which vbw commit moves; the project's pointer may lag), in its folder.
  local subs=()
  while IFS= read -r -d '' p; do subs+=("$p"); done < <(vbw_subs)
  for p in ${subs[@]+"${subs[@]}"}; do
    git -C "$VBW_ROOT/$p" -c core.hooksPath=/dev/null worktree add -q --detach "$copy/$p" HEAD > /dev/null 2>&1 \
      || { proofcopy_remove; vbw_die "cannot make a clean copy of the submodule $p's committed code"; }
  done
  real=$(cd -P "$VBW_ROOT" && pwd -P) || vbw_die "cannot resolve $VBW_ROOT"
  if [ -f "${VBW_RECORD:-}" ]; then
    while IFS= read -r l; do
      l=${l%/}
      [ -z "$l" ] || PROOFCOPY_LEFT+=("$l")
    done < <(jq -r '(.project.leave_out // [])[]' "$VBW_RECORD" 2> /dev/null)
  fi
  while IFS= read -r -d '' p; do
    p=${p%/}
    case "$p" in .git | .git/* | .vbw | .vbw/*) continue ;; esac
    ! proofcopy_is_build_dir "$p" || continue
    proofcopy_entry "$p"
  done < <(git -C "$VBW_ROOT" ls-files -z --others --ignored --exclude-standard --directory)
  # A submodule's ignored paths (its dependencies) are its own repository's to list.
  local s q
  for s in ${subs[@]+"${subs[@]}"}; do
    while IFS= read -r -d '' q; do
      p="$s/${q%/}"
      ! proofcopy_is_build_dir "$p" || continue
      proofcopy_entry "$p"
    done < <(git -C "$VBW_ROOT/$s" ls-files -z --others --ignored --exclude-standard --directory)
  done
}

# proofcopy_entry P: copy the ignored path P into the copy being made (the
# caller's locals: copy, real, first; the list is PROOFCOPY_LEFT). A listed path, or one under it, is
# skipped. A folder that holds a listed path is not copied whole: its children
# are copied one by one around the listed path, as deep as the path goes, so
# the data the list spares is never read.
proofcopy_entry() {
  local p=$1 L skip='' parent='' c l t
  for L in ${PROOFCOPY_LEFT[@]+"${PROOFCOPY_LEFT[@]}"}; do
    case "$p" in "$L" | "$L"/*) skip=1; break ;; esac
    case "$L" in "$p"/*) parent=1 ;; esac
  done
  [ -z "$skip" ] || return 0
  [ ! -e "$copy/$p" ] && [ ! -L "$copy/$p" ] || return 0
  if [ -n "$parent" ] && [ -d "$VBW_ROOT/$p" ] && [ ! -L "$VBW_ROOT/$p" ]; then
    mkdir -p "$copy/$p"
    while IFS= read -r -d '' c; do
      proofcopy_entry "$p/${c##*/}"
    done < <(find "$VBW_ROOT/$p" -mindepth 1 -maxdepth 1 -print0)
    return 0
  fi
  mkdir -p "$copy/$(dirname "$p")"
  proofcopy_copy "$VBW_ROOT/$p" "$copy/$p" || { proofcopy_remove; vbw_die "cannot copy the ignored path $p into the clean copy (is it readable?)"; }
  [ -z "$first" ] || proofcopy_note "$p"
  while IFS= read -r -d '' l; do
    t=$(readlink "$copy/$l")
    case "$t" in /*) t=$(cd -P "$(dirname "$t")" 2> /dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$t")") || t=$(readlink "$copy/$l") ;; esac
    # A link into .vbw (an old proof copy) is the stale-link scan's to report.
    case "$t" in "$real"/.vbw | "$real"/.vbw/*) ;; "$real" | "$real"/*)
      vbw_out 'vbw: %s links into the working folder (%s); it is copied as a link\n' "$l" "$(readlink "$copy/$l")" >&2 ;;
    esac
  done < <(cd "$copy" && find "$p" -type l -print0)
}

# proofcopy_note_open: open this process's scratch file of copy sizes; without
# it every note is a no-op. Never fails.
proofcopy_note_open() {
  PROOFCOPY_SIZES=''
  if [ -n "${VBW_RUNTIME:-}" ] && mkdir -p "$VBW_RUNTIME" 2> /dev/null && : > "$VBW_RUNTIME/proofcopy.$$.sizes" 2> /dev/null; then
    PROOFCOPY_SIZES=$VBW_RUNTIME/proofcopy.$$.sizes
    vbw_guard_add file "$PROOFCOPY_SIZES"
  fi
  return 0
}

# proofcopy_warn_stale: read-only scan of the working folder (git-ignored
# folders included, links never followed, .git and .vbw skipped) naming each
# link that points into this project's proof copies, with the repair. Says
# nothing when there is none. Never fails.
proofcopy_warn_stale() {
  local real l t n d r fix='re-run the project install command'
  real=$(cd -P "$VBW_ROOT" 2> /dev/null && pwd -P) || return 0
  [ ! -f "$VBW_ROOT/pnpm-lock.yaml" ] && [ ! -f "$VBW_ROOT/pnpm-workspace.yaml" ] || fix='delete node_modules and run pnpm install'
  while IFS= read -r -d '' l; do
    t=$(readlink "$l") || continue
    case "$t" in /*) ;; *) t="$(cd -P "$(dirname "$l")" 2> /dev/null && pwd -P)/$t" ;; esac
    # Fold . and .. away, then resolve the deepest folder that still exists.
    n=$(printf '%s' "$t" | awk -F/ '{for (i = 1; i <= NF; i++) if ($i == "..") { if (k) k-- } else if ($i != "" && $i != ".") p[++k] = $i; for (i = 1; i <= k; i++) printf "/%s", p[i]}')
    d=$n; while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done
    r=$(cd -P "$d" 2> /dev/null && pwd -P)${n#"$d"}
    case "$n:$r" in "$VBW_ROOT/.vbw/runtime/proof."* | "$real/.vbw/runtime/proof."* | *":$real/.vbw/runtime/proof."*)
      vbw_out 'vbw: %s -> %s points into a proof copy of an earlier run; %s\n' "${l#./}" "$t" "$fix" >&2 ;;
    esac
  done < <(cd "$VBW_ROOT" && find . \( -name .git -o -path ./.vbw \) -prune -o -type l -print0 2> /dev/null)
}

# proofcopy_copy SRC DST: a copy-on-write clone first, a plain copy when the
# file system refuses; links inside stay links. A failed try leaves nothing.
proofcopy_copy() {
  local flag=--reflink
  [ "$(uname)" != Darwin ] || flag=-c
  PROOFCOPY_HOW=clone
  cp -RP "$flag" "$1" "$2" 2> /dev/null && return 0
  rm -rf "$2" 2> /dev/null || true
  PROOFCOPY_HOW=plain
  cp -RP "$1" "$2" 2> /dev/null && return 0
  chmod -R u+rwx "$2" 2> /dev/null || true
  rm -rf "$2"
  return 1
}

# proofcopy_remove: drop every copy's worktree and whatever is left of its
# directory, read-only folders included (rm never follows a link out of a copy).
proofcopy_remove() {
  local c
  for c in ${PROOF_COPIES[@]+"${PROOF_COPIES[@]}"}; do
    chmod -R u+rwx "$c" 2> /dev/null || true
    git -C "$VBW_ROOT" worktree remove --force "$c" > /dev/null 2>&1 || true
    vbw_guard_drop "$(dirname "$c")"
  done
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  proofcopy_prune_subs
  PROOF_COPIES=()
  PROOF_COPY=
}

# proofcopy_prune_subs: each submodule forgets the worktrees of removed copies
# (removing a copy's folder removed theirs). Never fails.
proofcopy_prune_subs() {
  local p
  while IFS= read -r -d '' p; do
    git -C "$VBW_ROOT/$p" worktree prune > /dev/null 2>&1 || true
  done < <(vbw_subs)
  return 0
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
