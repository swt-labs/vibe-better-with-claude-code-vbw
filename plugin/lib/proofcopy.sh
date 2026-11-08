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
# Kept copies (#738, docs/proof.md "Kept copies"). A copy lives in a slot,
# .vbw/runtime/proof.keep.N (N from 1): tree/ (the worktree), pid (its owner,
# the vbw process using it: taken by an exclusive create, vbw_lock_create, and
# from an owner that has ended by vbw_lock_takeover), manifest (what the copy
# was last brought to: its submodules, and each ignored path copied in with its
# number of entries), stamp (written before that began) and done (written when
# it ended). A command claims free slots in order, up to the copies it needs,
# and makes a slot only when none is free; a slot whose pid file has stayed
# empty for 5 s is free too (an owner that died before it wrote its id, as the
# alone-check gate judges one). On a normal finish it hands each back
# (proofcopy_release: the pid file goes, the copy stays); an interrupt or
# vbw_die removes the slots it holds, as a half-used copy is not trusted.
#
# A claimed copy is brought up to date before any unit runs (proofcopy_refresh)
# and then holds what a copy made fresh at that moment would hold: HEAD
# detached and git reset --hard to the project's HEAD (each submodule to its
# own; a branch a unit checked out there never moves); git clean -ffdx, sparing only
# the ignored paths that are still to be copied in and were copied before; each
# ignored path new to the list copied in; in one copied before, the entries that
# changed brought up to date one by one (proofcopy_sync): those of its source
# changed after stamp (their change time, find -newercm, which no tool sets back,
# unlike a modification time) and those of the copy changed after done (a unit
# wrote there). It is copied again whole when its number of entries differs from
# the manifest's with no changed entry, or an entry cannot be brought up to date
# on its own. A failing step, a slot without a manifest, a
# changed set of submodules, or vbw prove --full (PROOFCOPY_FRESH): the copy is
# removed and made fresh in its slot. Every git command in a copy runs only
# after the copy is checked to be a worktree made for that place (proofcopy_own):
# git finds a repository by walking up, and above the copy is the user's project;
# a copied project folder holds the original's; a linked folder can lead to the
# user's own checkout. It runs without GIT_DIR and its kin (proofcopy_git). The
# stamp and done are each followed by a wait for the clock to move past them
# (proofcopy_tick), so no change in their tick is missed.
#
# The sweep (proofcopy_sweep, before every command's copies) removes a free slot
# unused for 24 hours (the slot folder's own modification time, which a claim
# and a hand-back move) or numbered past check_jobs; never one whose owner runs.
# A copy of an older VBW, .vbw/runtime/proof.PID.XXXXXX (PID the vbw process
# that made it), is removed once its owner has ended (kill -0 fails), never
# while it runs; one without an owner part (proof.XXXXXX) only when over 24
# hours old. A copy is first claimed by one atomic mv to
# proof.$$.swept-<its name>, so a second cleanup sees a live owner and leaves
# it, and a cleanup killed partway leaves a folder whose owner has ended. A
# copy that will not go prints one warning line and the proof goes on.
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
# read once per command, while the first copy is made or brought up to date,
# and only for a path copied the plain way. The line changes no verdict,
# evidence, record or exit code.

# Build-output folder names (Node, Python, Rust, Go and the like), at any depth.
PROOFCOPY_BUILD_DIRS='target dist build bin out __pycache__ .pytest_cache .mypy_cache .ruff_cache .tox .next .nuxt .gradle coverage'

# vbw prove --full sets it: every copy is made fresh, none brought up to date.
PROOFCOPY_FRESH=''
# What this command did with its copies (prooftime_total): kept copies claimed,
# of those the ones whose ignored paths were copied anew or removed, copies
# made, and the milliseconds spent bringing the claimed ones up to date.
PROOFCOPY_CLAIMED=0
PROOFCOPY_REFRESHED=0
PROOFCOPY_MADE=0
PROOFCOPY_REFRESH_MS=0
# The slots this command holds.
PROOF_SLOTS=()

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

# proofcopy_create_slots N: N copies, each a kept one claimed and brought up to
# date or a new one made; sets PROOF_COPIES (all of them) and PROOF_COPY (the
# first). Called directly, never in $(...). proofcopy_release hands every one
# back; proofcopy_remove and an interrupt remove them.
proofcopy_create_slots() {
  local n=1 d
  PROOF_COPIES=()
  PROOF_SLOTS=()
  mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
  proofcopy_sweep
  # Listed before the prune, so a worktree whose folder is gone is still left out.
  proofcopy_worktrees
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  while [ "${#PROOF_COPIES[@]}" -lt "$1" ]; do
    d="$VBW_RUNTIME/proof.keep.$n"
    if proofcopy_take "$d"; then proofcopy_ready "$d"; fi
    n=$((n + 1))
  done
  PROOF_COPY=${PROOF_COPIES[0]}
  proofcopy_plain_say
}

# proofcopy_take SLOT: hold SLOT, or return 1. A free slot (no owner, or one
# that has ended) is taken, a missing one made; a slot whose owner runs, or
# that another command takes first, is left alone. A held slot is removed on an
# interrupt or vbw_die.
proofcopy_take() {
  local h
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    if ! vbw_lock_create "$1/pid"; then
      h=$(vbw_lock_holder "$1/pid")
      if [ -n "$h" ]; then
        { ! vbw_lock_alive "$h" && vbw_lock_takeover "$1/pid" "$h"; } || return 1
      else
        # No id for 5 s: an owner that died before it wrote one (the alone-check gate's rule).
        { [ $(($(date +%s) - $(vbw_mtime "$1/pid"))) -ge 5 ] && vbw_lock_takeover "$1/pid" ""; } || return 1
      fi
    fi
  elif [ -e "$1" ] || [ -L "$1" ]; then
    return 1
  elif ! vbw_lock_dir "$1"; then
    [ -e "$1" ] || vbw_die "cannot create a directory in $VBW_RUNTIME"
    return 1
  fi
  vbw_guard_add dir "$1"
  PROOF_SLOTS+=("$1")
}

# proofcopy_ready SLOT: the held slot's copy brought up to date, or made fresh
# when that is not possible; added to PROOF_COPIES.
proofcopy_ready() {
  local d=$1 first='' t0='' PROOFCOPY_CHANGED=''
  if [ "${#PROOF_COPIES[@]}" -eq 0 ]; then first=1; proofcopy_note_open; fi
  # The read tracking's state describes the copy as the last command left it.
  rm -rf "$d/reads"
  if [ -z "$PROOFCOPY_FRESH" ] && [ -f "$d/manifest" ]; then
    [ -z "${PROOFTIME_FILE:-}" ] || t0=$(prooftime_clock)
    if proofcopy_refresh "$d"; then
      PROOFCOPY_CLAIMED=$((PROOFCOPY_CLAIMED + 1))
      [ -z "$PROOFCOPY_CHANGED" ] || PROOFCOPY_REFRESHED=$((PROOFCOPY_REFRESHED + 1))
      [ -z "$t0" ] || PROOFCOPY_REFRESH_MS=$((PROOFCOPY_REFRESH_MS + $(prooftime_ms "$(prooftime_clock)") - $(prooftime_ms "$t0")))
      PROOF_COPIES+=("$d/tree")
      return 0
    fi
  fi
  proofcopy_discard "$d"
  proofcopy_make "$d"
  PROOFCOPY_MADE=$((PROOFCOPY_MADE + 1))
  PROOF_COPIES+=("$d/tree")
}

# proofcopy_git ARG...: git without the variables that point it at a repository
# (GIT_DIR and its kin): exported, they would make a command run in a copy act on
# the user's repository and index.
proofcopy_git() (
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
  exec git "$@"
)

# proofcopy_own DIR REPO: DIR, a folder under the project, is a worktree of
# REPO made for this place: no link anywhere on its path below the project (a
# linked folder can lead to the user's own checkout), the top of a repository of
# its own (never a folder git would take for part of one above it), sharing
# REPO's repository (in a copied project folder the kept copy's .git still names
# the original's, which git would change), with a git dir among REPO's worktrees
# whose gitdir file names DIR itself.
proofcopy_own() {
  local top here real common gd
  [ -f "$1/.git" ] || return 1
  case "$1" in "$VBW_ROOT"/*) ;; *) return 1 ;; esac
  real=$(cd -P "$VBW_ROOT" 2> /dev/null && pwd -P) || return 1
  here=$(cd -P "$1" 2> /dev/null && pwd -P) || return 1
  [ "$here" = "$real${1#"$VBW_ROOT"}" ] || return 1
  top=$(proofcopy_git -C "$1" rev-parse --show-toplevel 2> /dev/null) || return 1
  [ "$(cd -P "$top" 2> /dev/null && pwd -P)" = "$here" ] || return 1
  common=$(proofcopy_git -C "$1" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || return 1
  [ "$common" = "$(proofcopy_git -C "$2" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" ] || return 1
  gd=$(proofcopy_git -C "$1" rev-parse --absolute-git-dir 2> /dev/null) || return 1
  case "$gd" in "$common"/worktrees/*) ;; *) return 1 ;; esac
  top=$(cat "$gd/gitdir" 2> /dev/null) || return 1
  [ "$(cd -P "$(dirname "$top")" 2> /dev/null && pwd -P)" = "$here" ]
}

# proofcopy_reset COPY SHA: COPY's HEAD detached at SHA, then its index and
# files reset to it. A branch a unit checked out in the copy stays where it is:
# reset --hard alone would move it.
proofcopy_reset() {
  proofcopy_git -C "$1" update-ref --no-deref HEAD "$2" > /dev/null 2>&1 \
    && proofcopy_git -C "$1" -c submodule.recurse=false reset -q --hard "$2" > /dev/null 2>&1
}

# proofcopy_tick FILE: return once the clock, as the file system records a
# change, has moved past FILE's modification time, so a change made after the
# return is strictly newer (find -newercm is strict: one in the same tick, about
# 4 ms on Linux and 1 s on HFS+, would be missed). Gives up after about 3 s.
proofcopy_tick() {
  local i=0
  touch "$1.tick" 2> /dev/null || return 0
  while [ -z "$(find "$1.tick" -newercm "$1" -print 2> /dev/null)" ] && [ "$i" -lt 300 ]; do
    sleep 0.01
    touch "$1.tick" 2> /dev/null || break
    i=$((i + 1))
  done
  rm -f "$1.tick"
}

# proofcopy_subs_json: the project's checked-out submodules, as a JSON array.
proofcopy_subs_json() {
  vbw_subs | jq -Rsc 'split("\u0000")[:-1]'
}

# proofcopy_left_read: what a copy leaves out (PROOFCOPY_LEFT): the ## Clean
# copy list from the record, then the worktree folders (PROOFCOPY_WT, R253).
proofcopy_left_read() {
  local l
  PROOFCOPY_LEFT=()
  if [ -f "${VBW_RECORD:-}" ]; then
    while IFS= read -r l; do
      l=${l%/}
      [ -z "$l" ] || PROOFCOPY_LEFT+=("$l")
    done < <(jq -r '(.project.leave_out // [])[]' "$VBW_RECORD" 2> /dev/null)
  fi
  for l in ${PROOFCOPY_WT[@]+"${PROOFCOPY_WT[@]}"}; do PROOFCOPY_LEFT+=("$l"); done
}

# proofcopy_make SLOT: a fresh copy in the held, empty slot.
proofcopy_make() {
  local d=$1 copy=$1/tree real l p subs=()
  touch "$d/stamp.next" || vbw_die "cannot write in $d"
  proofcopy_tick "$d/stamp.next"
  l=$(proofcopy_checkout "$VBW_ROOT" "$copy" 2>&1) \
    || { proofcopy_remove; vbw_die "cannot make a clean copy of the committed code: ${l##*$'\n'}"; }
  # Each checked-out submodule: a detached worktree of its own HEAD (its committed
  # code, which vbw commit moves; the project's pointer may lag), in its folder.
  while IFS= read -r -d '' p; do subs+=("$p"); done < <(vbw_subs)
  for p in ${subs[@]+"${subs[@]}"}; do
    l=$(proofcopy_checkout "$VBW_ROOT/$p" "$copy/$p" 2>&1) \
      || { proofcopy_remove; vbw_die "cannot make a clean copy of the submodule $p's committed code: ${l##*$'\n'}"; }
  done
  real=$(cd -P "$VBW_ROOT" && pwd -P) || vbw_die "cannot resolve $VBW_ROOT"
  proofcopy_left_read
  proofcopy_paths | jq -j -Rs 'split("\u0000")[:-1][] | ., "\u0000new\u0000"' > "$d/plan" \
    || { proofcopy_remove; vbw_die "cannot list the ignored paths of the project"; }
  proofcopy_fill "$d"
}

# proofcopy_refresh SLOT: bring the held slot's kept copy up to date; returns 1,
# leaving the slot to be emptied, when any step fails.
proofcopy_refresh() {
  local d=$1 copy=$1/tree real s p old subs=() owner=() kept=() ex=() i
  [ -f "$d/stamp" ] && [ -f "$d/done" ] && proofcopy_own "$copy" "$VBW_ROOT" || return 1
  # Until the new manifest is written the slot holds none: a refresh cut short
  # leaves a slot the next claim empties.
  mv "$d/manifest" "$d/manifest.old" 2> /dev/null || return 1
  touch "$d/stamp.next" || return 1
  proofcopy_tick "$d/stamp.next"
  p=$(git -C "$VBW_ROOT" rev-parse HEAD) || return 1
  proofcopy_reset "$copy" "$p" || return 1
  while IFS= read -r -d '' s; do subs+=("$s"); done < <(vbw_subs)
  [ "$(proofcopy_subs_json)" = "$(jq -c '.subs' "$d/manifest.old" 2> /dev/null)" ] || return 1
  for s in ${subs[@]+"${subs[@]}"}; do
    proofcopy_own "$copy/$s" "$VBW_ROOT/$s" || return 1
    p=$(proofcopy_git -C "$VBW_ROOT/$s" rev-parse HEAD) || return 1
    proofcopy_reset "$copy/$s" "$p" || return 1
  done
  proofcopy_left_read
  proofcopy_paths | jq -j -Rs --slurpfile m "$d/manifest.old" '$m[0].paths as $o
    | split("\u0000")[:-1][] as $p | $p, "\u0000", (if $o | has($p) then $o[$p] | tostring else "new" end), "\u0000"' > "$d/plan" || return 1
  # The paths copied in before and still to be: git clean spares them, each in
  # the repository it lies in (a submodule's are its own), anchored at its top.
  while IFS= read -r -d '' p && IFS= read -r -d '' old; do
    [ "$old" != new ] || continue
    s=''
    for i in ${subs[@]+"${subs[@]}"}; do
      case "$p" in "$i"/*) s=$i ;; esac
    done
    kept+=("$p")
    owner+=("$s")
  done < "$d/plan"
  # A path copied in before and no longer to be: git clean removes it below.
  [ "${#kept[@]}" -eq "$(jq '.paths | length' "$d/manifest.old")" ] || PROOFCOPY_CHANGED=1
  for s in '' ${subs[@]+"${subs[@]}"}; do
    ex=()
    i=0
    while [ "$i" -lt "${#kept[@]}" ]; do
      if [ "${owner[i]}" = "$s" ]; then ex+=(-e "/$(proofcopy_pattern "${kept[i]#"${s:+$s/}"}")"); fi
      i=$((i + 1))
    done
    proofcopy_git -C "$copy${s:+/$s}" -c submodule.recurse=false clean -q -ffdx ${ex[@]+"${ex[@]}"} > /dev/null 2>&1 || return 1
  done
  real=$(cd -P "$VBW_ROOT" && pwd -P) || return 1
  proofcopy_fill "$d"
  rm -f "$d/manifest.old"
}

# proofcopy_pattern PATH: PATH as a gitignore pattern that matches it alone
# (each \, *, ?, [ and space escaped).
proofcopy_pattern() {
  local p=$1 o='' c
  while [ -n "$p" ]; do
    c=${p:0:1}
    p=${p:1}
    case "$c" in '\' | '*' | '?' | '[' | ' ') o="$o\\$c" ;; *) o="$o$c" ;; esac
  done
  printf '%s\n' "$o"
}

# proofcopy_fill SLOT: copy into the copy (the caller's copy, real and first)
# each ignored path of SLOT/plan ("PATH\0COUNT\0", COUNT the manifest's number
# of entries, or "new") that is new or stale; then write done, the manifest and
# the stamp. Sets PROOFCOPY_CHANGED when a path was copied.
proofcopy_fill() {
  local d=$1 p old c w
  : > "$d/counts" || vbw_die "cannot write in $d"
  while IFS= read -r -d '' p && IFS= read -r -d '' old; do
    c=''
    if [ "$old" != new ]; then
      # The copy's walk (did a unit write there?) runs beside the source's: each
      # reads every entry of a large node_modules, a few seconds apiece.
      find "$copy/$p" -newercm "$d/done" -print -quit > "$d/wrote" 2> /dev/null &
      w=$!
      c=$(proofcopy_walk "$VBW_ROOT/$p" "$d/stamp")
      wait "$w" || true
      if { [ ! -e "$copy/$p" ] && [ ! -L "$copy/$p" ]; } || { [ "$c" != stale ] && [ "$c" != "$old" ]; }; then
        c=''
      elif [ "$c" = stale ] || [ -s "$d/wrote" ]; then
        # Only the entries that changed, on either side, are copied again.
        if proofcopy_sync "$p" "$d" "$old"; then c=synced; else c=''; fi
      fi
    fi
    if [ "$c" = synced ] || [ -z "$c" ]; then
      [ -n "$c" ] || proofcopy_put "$p"
      PROOFCOPY_CHANGED=1
      c=$(proofcopy_walk "$VBW_ROOT/$p" "$d/stamp.next")
      # Changed while it was copied: the next claim copies it again.
      [ "$c" != stale ] || c=-1
    fi
    vbw_out '%s\0%s\0' "$p" "$c" >> "$d/counts"
  done < "$d/plan"
  touch "$d/done" || vbw_die "cannot write in $d"
  # A unit's write in the copy, made after this, is strictly newer than done.
  proofcopy_tick "$d/done"
  proofcopy_subs_json | jq -c --rawfile c "$d/counts" '{subs: ., paths: ($c | split("\u0000")[:-1] | [range(0; length; 2) as $i | {key: .[$i], value: (.[$i + 1] | tonumber)}] | from_entries)}' > "$d/manifest.next" \
    && mv "$d/manifest.next" "$d/manifest" && mv "$d/stamp.next" "$d/stamp" \
    || vbw_die "cannot write the manifest of $d"
  rm -f "$d/plan" "$d/counts" "$d/wrote" "$d/dirty" "$d/kids"
}

# proofcopy_sync P SLOT OLD: bring the copy's ignored path P to the working folder's
# by the entries that changed: those of the copy changed after SLOT/done (a unit
# wrote them) and those of the working folder changed after SLOT/stamp, parents
# first. A changed folder present on both sides gets its listing matched (a
# child added, removed or renamed changes its folder's change time); any other
# changed entry is copied again or removed. Fails, leaving the whole path to be
# copied again, when more than one in 20 of its entries changed, or a step fails
# (a read-only folder, a type that changed).
proofcopy_sync() {
  local p=$1 d=$2 q s c n
  { (cd "$copy" && find "$p" -newercm "$d/done" -print0) && (cd "$VBW_ROOT" && find "$p" -newercm "$d/stamp" -print0); } 2> /dev/null \
    | LC_ALL=C sort -zu > "$d/dirty" || return 1
  # One entry costs about 25 times more on its own (a process each) than inside
  # a clone of the whole path (measured on APFS, 2,500 entries): past one in 20
  # of OLD, the path's entries in the manifest, the whole path is cheaper.
  n=$(tr -cd '\0' < "$d/dirty" | wc -c)
  [ $((n * 20)) -le "$3" ] || return 1
  while IFS= read -r -d '' q; do
    s=$VBW_ROOT/$q
    c=$copy/$q
    if [ -d "$s" ] && [ ! -L "$s" ] && [ -d "$c" ] && [ ! -L "$c" ]; then
      [ -w "$c" ] || return 1
      (cd "$c" && find . -mindepth 1 -maxdepth 1 -print0) > "$d/kids" || return 1
      while IFS= read -r -d '' n; do
        n=${n#./}
        [ -e "$s/$n" ] || [ -L "$s/$n" ] || { chmod -R u+rwx "$c/$n" 2> /dev/null; rm -rf "${c:?}/$n"; } || return 1
      done < "$d/kids"
      (cd "$s" && find . -mindepth 1 -maxdepth 1 -print0) > "$d/kids" || return 1
      while IFS= read -r -d '' n; do
        n=${n#./}
        [ -e "$c/$n" ] || [ -L "$c/$n" ] || proofcopy_copy "$s/$n" "$c/$n" || return 1
      done < "$d/kids"
    elif [ ! -e "$s" ] && [ ! -L "$s" ]; then
      # Gone from the source (most often already gone with its parent's listing).
      [ ! -e "$c" ] && [ ! -L "$c" ] || { chmod -R u+rwx "$c" 2> /dev/null; rm -rf "$c"; } || return 1
    elif [ ! -e "$c" ] && [ ! -L "$c" ]; then
      proofcopy_copy "$s" "$c" || return 1
    elif [ -d "$s" ] && [ ! -L "$s" ] || [ -d "$c" ] && [ ! -L "$c" ]; then
      return 1
    else
      [ -w "$(dirname "$c")" ] && rm -f "$c" && proofcopy_copy "$s" "$c" || return 1
    fi
  done < "$d/dirty"
  rm -f "$d/dirty" "$d/kids"
}

# proofcopy_walk PATH STAMP: one walk of PATH: "stale" when an entry of it
# changed after STAMP was written (its change time against STAMP's modification
# time), or the walk failed; else its number of entries.
proofcopy_walk() {
  local r
  # A stale entry ends the walk with a newline, every other entry ends with a NUL.
  r=$({ find "$1" \( -newercm "$2" -print -quit \) -o -print0 || printf 'x\n'; } 2> /dev/null | tr -cd '\0\n' | tr '\0\n' 'os')
  case "$r" in '' | *s) printf 'stale\n' ;; *) r=${r//s/}; printf '%s\n' "${#r}" ;; esac
}

# proofcopy_paths: the ignored paths a clean copy holds (relative to the
# project), "PATH\0" each: the top-level ignored paths of the project and of
# each submodule (the caller's subs), less .git, .vbw and build folders, with
# the ## Clean copy list (PROOFCOPY_LEFT) applied by proofcopy_entry.
proofcopy_paths() {
  local s
  git -C "$VBW_ROOT" ls-files -z --others --ignored --exclude-standard --directory | while IFS= read -r -d '' p; do
    p=${p%/}
    case "$p" in .git | .git/* | .vbw | .vbw/*) continue ;; esac
    ! proofcopy_is_build_dir "$p" || continue
    proofcopy_entry "$p"
  done
  # A submodule's ignored paths (its dependencies) are its own repository's to list.
  for s in ${subs[@]+"${subs[@]}"}; do
    git -C "$VBW_ROOT/$s" ls-files -z --others --ignored --exclude-standard --directory | while IFS= read -r -d '' p; do
      p="$s/${p%/}"
      ! proofcopy_is_build_dir "$p" || continue
      proofcopy_entry "$p"
    done
  done
}

# proofcopy_entry P: the ignored path P as the paths to copy in, "PATH\0"
# each, by the parsed list PROOFCOPY_LEFT. A listed path, or one under it, is
# none. A folder that holds a listed path is not copied whole: its children are
# copied one by one around the listed path, as deep as the path goes, so the
# data the list spares is never read.
proofcopy_entry() {
  local p=$1 L skip='' parent=''
  for L in ${PROOFCOPY_LEFT[@]+"${PROOFCOPY_LEFT[@]}"}; do
    case "$p" in "$L" | "$L"/*) skip=1; break ;; esac
    case "$L" in "$p"/*) parent=1 ;; esac
  done
  [ -z "$skip" ] || return 0
  if [ -n "$parent" ] && [ -d "$VBW_ROOT/$p" ] && [ ! -L "$VBW_ROOT/$p" ]; then
    find "$VBW_ROOT/$p" -mindepth 1 -maxdepth 1 -print0 | while IFS= read -r -d '' c; do
      proofcopy_entry "$p/${c##*/}"
    done
    return 0
  fi
  printf '%s\0' "$p"
}

# proofcopy_put P: copy the ignored path P into the copy (the caller's locals:
# copy, real, first), in place of whatever the copy holds there.
proofcopy_put() {
  local p=$1 l t
  if [ -e "$copy/$p" ] || [ -L "$copy/$p" ]; then
    chmod -R u+rwx "$copy/$p" 2> /dev/null || true
    rm -rf "${copy:?}/$p"
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

# proofcopy_sweep: remove the slots no command should keep and the copies of an
# older VBW whose owner has ended. Never fails.
proofcopy_sweep() {
  local d n rest pid cap k
  cap=$(vbw_check_jobs 2> /dev/null) || cap=''
  for d in "$VBW_RUNTIME"/proof.*; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    n=${d##*/}
    rest=${n#proof.}
    case "$rest" in
      keep.*)
        k=${rest#keep.}
        case "$k" in '' | *[!0-9]*) continue ;; esac
        # Unused for 24 hours, or past the cap; then only once held, so never
        # one whose owner runs or that another command claims meanwhile.
        if [ -z "$(find "$d" -maxdepth 0 -mmin +1440 -print 2> /dev/null)" ]; then
          [ -n "$cap" ] && [ "$k" -gt "$cap" ] || continue
        fi
        proofcopy_take "$d" || continue
        vbw_guard_forget "$d"
        proofcopy_drop_held "$d"
        proofcopy_sweep_rm "$d"
        continue
        ;;
    esac
    pid=${rest%%.*}
    if [ "$pid" != "$rest" ] && [ -n "${rest#*.}" ] && [ -n "$pid" ] && [ -z "${pid//[0-9]/}" ]; then
      ! kill -0 "$pid" 2> /dev/null || continue
    else
      [ -n "$(find "$d" -maxdepth 0 -mmin +1440 -print 2> /dev/null)" ] || continue
    fi
    proofcopy_sweep_rm "$d"
  done
  return 0
}

# proofcopy_drop_held SLOT: forget SLOT among the slots this command holds.
proofcopy_drop_held() {
  local s keep=()
  for s in ${PROOF_SLOTS[@]+"${PROOF_SLOTS[@]}"}; do [ "$s" = "$1" ] || keep+=("$s"); done
  PROOF_SLOTS=(${keep[@]+"${keep[@]}"})
}

# proofcopy_sweep_rm DIR: claim DIR by one atomic mv, then remove it with its
# worktree entries; one warning line when it will not go.
proofcopy_sweep_rm() {
  local claim="$VBW_RUNTIME/proof.$$.swept-${1##*/}"
  # Not moved aside: a slot this command held is handed back, never kept.
  { [ ! -e "$claim" ] && mv "$1" "$claim" 2> /dev/null; } || { rm -f "$1/pid"; return 0; }
  chmod -R u+rwx "$claim" > /dev/null 2>&1 || true
  rm -rf "$claim" > /dev/null 2>&1 || true
  git -C "$VBW_ROOT" worktree prune > /dev/null 2>&1 || true
  proofcopy_prune_subs
  [ ! -e "$claim" ] || printf 'vbw: cannot remove the leftover proof copy %s; remove it by hand\n' ".vbw/runtime/${claim##*/}" >&2
}

# proofcopy_checkout REPO DEST: a detached worktree of REPO's HEAD at DEST. When
# git cannot write it (Claude Code's sandbox refuses to create any file named
# .gitmodules), the half-made one goes and it is made again with every file but
# the .gitmodules files, which stay unwritten, marked skip-worktree: git status
# stays clean, git reads them from the index, and so does vbw_subs, told by
# vbw-gitmodules-index in the copy's git directory. Git's error on stderr.
proofcopy_checkout() {
  git -C "$1" -c core.hooksPath=/dev/null worktree add -q --detach "$2" HEAD > /dev/null 2>&1 && return 0
  rm -rf "$2"
  git -C "$1" worktree prune
  git -C "$1" -c core.hooksPath=/dev/null worktree add -q --no-checkout --detach "$2" HEAD > /dev/null || return 1
  proofcopy_git -C "$2" read-tree HEAD || return 1
  proofcopy_git -C "$2" ls-files -z -- ':(glob)**/.gitmodules' | proofcopy_git -C "$2" update-index -z --skip-worktree --stdin || return 1
  proofcopy_git -C "$2" checkout-index -a -q -u || return 1
  : > "$(proofcopy_git -C "$2" rev-parse --absolute-git-dir)/vbw-gitmodules-index"
}

# Worktrees (R253): the folder of every worktree of the repository that lies
# inside the project (git worktree list --porcelain, paths made physical), and
# .claude/worktrees, are left out of every clean copy whatever the list says,
# the same way a listed path is: a worktree under an ignored folder is skipped by
# descending around it (D509), a worktree whose folder is gone is ignored.

# proofcopy_worktrees: sets PROOFCOPY_WT to the project-relative paths of the
# worktree folders inside the project, plus .claude/worktrees. Never fails.
proofcopy_worktrees() {
  local real l p d b
  PROOFCOPY_WT=(.claude/worktrees)
  real=$(cd -P "$VBW_ROOT" 2> /dev/null && pwd -P) || return 0
  while IFS= read -r l; do
    case "$l" in 'worktree '*) p=${l#worktree } ;; *) continue ;; esac
    if [ -d "$p" ]; then
      p=$(cd -P "$p" 2> /dev/null && pwd -P) || continue
    else
      d=$(cd -P "$(dirname "$p")" 2> /dev/null && pwd -P) || continue
      b=${p##*/}
      p="$d/$b"
    fi
    case "$p" in "$real"/*) ;; *) continue ;; esac
    p=${p#"$real"/}
    case "$p" in .vbw | .vbw/* | .git | .git/*) continue ;; esac
    PROOFCOPY_WT+=("$p")
  done < <(git -C "$VBW_ROOT" worktree list --porcelain 2> /dev/null)
  return 0
}

# proofcopy_is_skipped P: P is, or lies under, a worktree folder.
proofcopy_is_skipped() {
  local w
  for w in ${PROOFCOPY_WT[@]+"${PROOFCOPY_WT[@]}"}; do
    case "$1" in "$w" | "$w"/*) return 0 ;; esac
  done
  return 1
}

# proofcopy_size_kb P: du -sk of the project-relative path P, a worktree folder
# below it not counted (the sum of the children around it).
proofcopy_size_kb() {
  local p=$1 w parent='' c t=0 k
  for w in ${PROOFCOPY_WT[@]+"${PROOFCOPY_WT[@]}"}; do
    case "$w" in "$p"/*) parent=1 ;; esac
  done
  if [ -n "$parent" ] && [ -d "$VBW_ROOT/$p" ] && [ ! -L "$VBW_ROOT/$p" ]; then
    while IFS= read -r -d '' c; do
      ! proofcopy_is_skipped "$p/${c##*/}" || continue
      k=$(proofcopy_size_kb "$p/${c##*/}")
      t=$((t + k))
    done < <(find "$VBW_ROOT/$p" -mindepth 1 -maxdepth 1 -print0)
    printf '%d\n' "$t"
    return 0
  fi
  du -sk "$VBW_ROOT/$p" 2> /dev/null | awk 'NR == 1 {t = $1} END {printf "%d\n", t}'
}

# proofcopy_disk_kind: print "clone" when the project's disk makes copy-on-write
# clones (a clone of a small file under $VBW_RUNTIME succeeds: cp -c on macOS,
# cp --reflink=always elsewhere), else "plain". The disk decides, never a folder's
# name, a stack or a language. The probe is removed. VBW_PROOFCOPY_DISK=clone|plain
# is the test override and answers without trying. Never fails.
proofcopy_disk_kind() {
  case "${VBW_PROOFCOPY_DISK:-}" in clone | plain) vbw_out '%s\n' "$VBW_PROOFCOPY_DISK"; return 0 ;; esac
  local flag=--reflink=always src dst kind=plain
  [ "$(uname)" != Darwin ] || flag=-c
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || true
  src="$VBW_RUNTIME/disk-probe-src.$$"
  dst="$VBW_RUNTIME/disk-probe-dst.$$"
  if printf 'vbw\n' > "$src" 2> /dev/null && cp "$flag" "$src" "$dst" 2> /dev/null; then kind=clone; fi
  rm -f "$src" "$dst" 2> /dev/null || true
  vbw_out '%s\n' "$kind"
  return 0
}

# proofcopy_big_ignored: one line "name/ (1.0 GB)" for each git-ignored folder
# inside the project over VBW_PROOFCOPY_PLAIN_KB (500 MB by default); a worktree
# folder and .claude/worktrees are never candidates and never counted. Never fails.
proofcopy_big_ignored() {
  local limit=${VBW_PROOFCOPY_PLAIN_KB:-512000} p kb
  case "$limit" in '' | *[!0-9]*) limit=512000 ;; esac
  proofcopy_worktrees
  while IFS= read -r -d '' p; do
    p=${p%/}
    case "$p" in .git | .git/* | .vbw | .vbw/*) continue ;; esac
    [ -d "$VBW_ROOT/$p" ] && [ ! -L "$VBW_ROOT/$p" ] || continue
    ! proofcopy_is_skipped "$p" || continue
    kb=$(proofcopy_size_kb "$p")
    [ "${kb:-0}" -gt "$limit" ] || continue
    vbw_out '%s/ (%s)\n' "$p" "$(proofcopy_fmt_kb "$kb")"
  done < <(git -C "$VBW_ROOT" ls-files -z --others --ignored --exclude-standard --directory 2> /dev/null)
  return 0
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

# proofcopy_discard SLOT: empty the held slot but for its pid file; git forgets
# the worktrees that were in it. Read-only folders are opened up first.
proofcopy_discard() {
  chmod -R u+rwx "$1" 2> /dev/null || true
  find "$1" -mindepth 1 -maxdepth 1 ! -name pid -exec rm -rf {} + 2> /dev/null || true
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  proofcopy_prune_subs
}

# proofcopy_release: hand back every slot this command holds, copy and all,
# for the next command to claim (a normal finish).
proofcopy_release() {
  local d
  for d in ${PROOF_SLOTS[@]+"${PROOF_SLOTS[@]}"}; do
    vbw_guard_forget "$d"
    rm -f "$d/pid"
  done
  PROOF_SLOTS=()
  PROOF_COPIES=()
  PROOF_COPY=
}

# proofcopy_remove: remove every slot this command holds, worktrees and all,
# read-only folders included (rm never follows a link out of a copy).
proofcopy_remove() {
  local d
  for d in ${PROOF_SLOTS[@]+"${PROOF_SLOTS[@]}"}; do
    vbw_guard_drop "$d"
  done
  git -C "$VBW_ROOT" worktree prune 2> /dev/null || true
  proofcopy_prune_subs
  PROOF_SLOTS=()
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

# proofcopy_judge COPY JUDGED: each file of JUDGED (a JSON object {file: git blob id}, the
# approved content of an added-to check file, R269) written into COPY as the approval
# held it, in place so the file keeps its mode. Only the copy changes, never the working
# folder. Dies when a blob cannot be read.
proofcopy_judge() {
  local f b
  while IFS= read -r -d '' f && IFS= read -r -d '' b; do
    [ ! -L "$1/$f" ] || rm -f "$1/$f"
    git -C "$VBW_ROOT" cat-file blob "$b" > "$1/$f" 2> /dev/null || vbw_die "cannot put the approved content of $f into the clean copy"
  done < <(printf '%s' "$2" | jq -j 'to_entries[] | .key, "\u0000", .value, "\u0000"')
}

# proofcopy_unjudge COPY JUDGED: the files of JUDGED back as the copy's commit holds them,
# for the next unit that takes the copy.
proofcopy_unjudge() {
  local f
  while IFS= read -r -d '' f; do
    proofcopy_git -C "$1" checkout -q -- "$f" > /dev/null 2>&1 || true
  done < <(printf '%s' "$2" | jq -j 'keys[] + "\u0000"')
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
