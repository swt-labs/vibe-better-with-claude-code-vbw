#!/usr/bin/env bash
# What a run reads in its own clean copy (docs/proof.md, R166). Before a run
# the access time (atime, the time the system notes when a file is read) of
# every tracked file and folder of the copy, and of the copy's .git file, is
# set back with touch -a to an old date. After it, what moved forward was read:
# a file was opened, a folder was listed, git was used. The copy is a worktree,
# and its .git file (the line naming its git folder) is what every git command
# run inside the copy reads first; its HEAD and index sit in the repository's
# shared git folder, which git run elsewhere in the repository also reads (git
# worktree list, git branch, another worktree being made), so they would tell
# nothing about the run. Build output a run writes (a file under a folder named
# in PROOFCOPY_BUILD_DIRS, proofcopy.sh) is gone before the next run, which
# starts without it as the first run of a fresh copy does. Any other file a run
# writes remembers that run's read list; a later run in the same copy that
# reads it adds that list to its own.
#
# Per slot a state folder (outside the copy) holds: tracked (the tracked paths,
# a submodule's under its folder, reads_tracked), files and dirs (the
# tracked paths, "./"-prefixed, NUL-separated), kids.json ({kids: folder -> names
# directly in it, files: the tracked file paths}), built (the files under build
# folders the copy was made with, NUL-separated), unbuilt (the build output the
# last reset removed), ready (empty, written last: the first reset completed),
# ref (modification and access time set to the old date plus a day: the
# yardstick "read since" compares with), mark (just before the run started:
# "written since"), moved (every path whose access time moved in the last
# collected run, NUL-separated), wlist (written files, for a full set-back),
# written.json ({lists: run id -> read list, files: path -> [run id]}) and
# runid (the last run id given).

# The old date, for touch -t (local time): a set-back time is a day before the
# yardstick file (READS_OLD_DAY) that "read since" is compared with.
READS_OLD=200001010000
READS_OLD_DAY=200001020000

# reads_probe DIR: the start-of-proof test of the file system DIR is on. A
# file's access time is set back and must stay behind the yardstick; reading
# the file and listing a folder must then move it past it. The same comparison
# (find -anewer) the collector uses, so the probe proves what the proof relies on.
# A copy of a file must move it too, made with cp and with cat into a file: where
# the file system copies by a copy-on-write clone (btrfs, XFS with reflink), the
# data is shared and never read, so the source's access time stays, and a run that
# copies a tracked file (a test copying a fixture) would not have it on its list.
# Nothing is reused there either; the message says which test failed.
reads_probe() {
  local p ok=0
  p=$(mktemp -d "$1/probe.XXXXXX" 2> /dev/null) || ok=1
  if [ "$ok" -eq 0 ]; then
    mkdir "$p/d" 2> /dev/null && printf 'x\n' > "$p/d/f" 2> /dev/null || ok=1
    : > "$p/ref" && touch -t "$READS_OLD_DAY" "$p/ref" 2> /dev/null || ok=1
    touch -a -t "$READS_OLD" "$p/d/f" "$p/d" 2> /dev/null || ok=1
    # Each set-back must have taken: the yardstick and both access times are years old. Asked by age,
    # never by comparing with a file made a moment before, whose time can be equal on a fast machine
    # (2.0.37 CI, Linux).
    [ "$ok" -ne 0 ] || [ -n "$(find "$p/ref" -maxdepth 0 -mtime +1000 2> /dev/null)" ] || ok=1
    [ "$ok" -ne 0 ] || [ "$(find "$p/d/f" "$p/d" -maxdepth 0 -atime +1000 2> /dev/null | wc -l | tr -d ' ')" = 2 ] || ok=1
    if [ "$ok" -eq 0 ]; then
      cat "$p/d/f" > /dev/null 2>&1
      [ -n "$(find "$p/d/f" -maxdepth 0 -anewer "$p/ref" 2> /dev/null)" ] || ok=1
      ls "$p/d" > /dev/null 2>&1
      [ -n "$(find "$p/d" -maxdepth 0 -anewer "$p/ref" 2> /dev/null)" ] || ok=1
    fi
    # 64 KiB, so that the copy takes the way an ordinary file's would, not a tiny file's.
    [ "$ok" -ne 0 ] || head -c 65536 /dev/zero > "$p/d/g" 2> /dev/null || ok=1
    if [ "$ok" -eq 0 ]; then
      touch -a -t "$READS_OLD" "$p/d/g" 2> /dev/null && cp "$p/d/g" "$p/c1" 2> /dev/null \
        && [ -n "$(find "$p/d/g" -maxdepth 0 -anewer "$p/ref" 2> /dev/null)" ] || ok=2
    fi
    if [ "$ok" -eq 0 ]; then
      touch -a -t "$READS_OLD" "$p/d/g" 2> /dev/null && cat "$p/d/g" > "$p/c2" 2> /dev/null \
        && [ -n "$(find "$p/d/g" -maxdepth 0 -anewer "$p/ref" 2> /dev/null)" ] || ok=2
    fi
  fi
  [ -z "${p:-}" ] || { chmod -R u+rwx "$p" 2> /dev/null; rm -rf "$p"; }
  case "$ok" in
    0) return 0 ;;
    2) printf 'this file system does not record a copied file as read\n' >&2 ;;
    *) printf 'this file system does not record which files are read\n' >&2 ;;
  esac
  return 1
}

# reads_mark FILE SECONDS [NOW]: set FILE's modification time to SECONDS before NOW (now
# by default, in epoch seconds). The stamp is written and read in UTC: a local stamp in the
# hour a clock change repeats names two moments, and touch may take the wrong one, an hour
# early or late, so every read of a run would look older or newer than its mark.
reads_mark() {
  local e=$(( ${3:-$(date +%s)} - $2 )) stamp
  stamp=$(TZ=UTC0 date -r "$e" +%Y%m%d%H%M.%S 2> /dev/null || TZ=UTC0 date -d "@$e" +%Y%m%d%H%M.%S) || return 1
  TZ=UTC0 touch -t "$stamp" "$1"
}

# reads_touch LIST COPY: set back the access time of each path in LIST (NUL-
# separated, relative to COPY). Links themselves, never what they point to;
# a path that is gone is skipped.
reads_touch() {
  (cd "$2" && xargs -0 -r touch -h -a -t "$READS_OLD" -- < "$1") 2> /dev/null || true
}

# reads_subsecond DIR: whether the file system DIR is on tells the order of files made
# a moment apart (times finer than a second): three files made one after the other must
# come out in that order. A file system whose times are whole seconds cannot (it would
# take two second changes within a few milliseconds).
reads_subsecond() {
  local d=$1
  for _ in 1 2 3 4 5; do
    : > "$d/subsec.a" && : > "$d/subsec.b" && : > "$d/subsec.c" || break
    if [ -n "$(find "$d/subsec.b" -maxdepth 0 -newer "$d/subsec.a" 2> /dev/null)" ] \
      && [ -n "$(find "$d/subsec.c" -maxdepth 0 -newer "$d/subsec.b" 2> /dev/null)" ]; then
      rm -f "$d/subsec.a" "$d/subsec.b" "$d/subsec.c"
      return 0
    fi
  done
  rm -f "$d/subsec.a" "$d/subsec.b" "$d/subsec.c"
  return 1
}

# reads_built COPY: the files under a build folder (PROOFCOPY_BUILD_DIRS) in COPY,
# "./"-prefixed and NUL-separated, .git left out: called when the copy was just made,
# it names the build output the copy came with (tracked, or inside an ignored folder
# brought in whole, such as a virtual environment), which no run made.
reads_built() {
  local n a=()
  for n in $PROOFCOPY_BUILD_DIRS; do
    [ ${#a[@]} -eq 0 ] || a+=(-o)
    a+=(-path "*/$n/*")
  done
  [ ${#a[@]} -gt 0 ] || return 0
  (cd "$1" && find . -path ./.git -prune -o -type f \( ${a[@]+"${a[@]}"} \) -print0)
}

# reads_unbuild COPY STATE: remove from COPY the build output earlier runs wrote: each
# file of written.json under a build folder that the copy was not made with (built),
# then the folders that held only such files, deepest first. written.json forgets
# them, and every read list no remaining file carries. A run reading build output
# reads what it made itself, so no read list passes from run to run through it.
reads_unbuild() {
  local copy=$1 st=$2
  jq -j --rawfile b "$st/built" --arg names "$PROOFCOPY_BUILD_DIRS" '
    ($names | split(" ") | map(select(length > 0) | {key: ., value: true}) | from_entries) as $bn
    | [.files | keys[] | select(split("/")[:-1] | any(.[]; $bn[.]))] as $c
    | if ($c | length) == 0 then empty
      else ($b | split("\u0000") | map(select(length > 0) | sub("^\\./"; "") | {key: ., value: true}) | from_entries) as $made
        | $c[] | select($made[.] | not) | "./" + . + "\u0000" end' "$st/written.json" > "$st/unbuilt" || return 1
  [ -s "$st/unbuilt" ] || return 0
  (cd "$copy" && xargs -0 rm -f -- < "$st/unbuilt") || return 1
  # rmdir leaves every folder that still holds something.
  jq -Rs -j --arg names "$PROOFCOPY_BUILD_DIRS" '
    ($names | split(" ") | map(select(length > 0) | {key: ., value: true}) | from_entries) as $bn
    | [split("\u0000")[] | select(length > 0) | sub("^\\./"; "") | split("/") | . as $p
       | range(1; length) | $p[:.] | select(any(.[]; $bn[.])) | join("/")]
    | unique | sort_by(-(split("/") | length))[] | "./" + . + "\u0000"' "$st/unbuilt" \
    | (cd "$copy" && xargs -0 rmdir -- 2> /dev/null) || true
  jq -c --rawfile u "$st/unbuilt" '
    ($u | split("\u0000") | map(select(length > 0) | sub("^\\./"; "") | {key: ., value: true}) | from_entries) as $gone
    | .files |= with_entries(select($gone[.key] | not))
    | ([.files[][]] | map({key: ., value: true}) | from_entries) as $ids
    | .lists |= with_entries(select($ids[.key]))' "$st/written.json" > "$st/written.tmp" && mv "$st/written.tmp" "$st/written.json"
}

# reads_reset COPY STATE: before a run (STATE absolute). The first call also
# records the copy's tracked files and folders (they never change: the copy is
# a detached checkout) and the build output it was made with. Each call first
# removes the build output earlier runs wrote (reads_unbuild). "Written by
# the run" means newer than the mark: 2 seconds back (whole-second file
# systems), but never before the copy's first reset. A file the previous run
# wrote just before may be taken for this run's, and then carries both lists.
reads_reset() {
  local copy=$1 st=$2 slack=2 sec exact=true
  mkdir -p "$st" || return 1
  if [ ! -f "$st/ready" ]; then
    # The copy was just made. On a file system with whole-second times, wait for the next whole
    # second, so that no file of it can look written by the first run; with finer times the
    # marks below are exact and nothing waits.
    if ! reads_subsecond "$st"; then
      sec=$(date +%s)
      while [ "$(date +%s)" = "$sec" ]; do sleep 0.05; done
      exact=false
    fi
    slack=0
    : > "$st/mark0" || return 1
    [ "$exact" = true ] || reads_mark "$st/mark0" 0 || return 1
    # A worktree's .git is a file (gitrepository-layout): the collection's sign of git use.
    [ -f "$copy/.git" ] || return 1
    reads_tracked "$copy" > "$st/tracked" || return 1
    jq -Rs -j '
      (split("\u0000") | map(select(length > 0))) as $f
      | ($f[] | "./" + . + "\u0000")' "$st/tracked" > "$st/files" || return 1
    jq -Rs -j '
      (split("\u0000") | map(select(length > 0))) as $f
      | ([$f[] | split("/") | . as $p | range(1; length) | $p[:.] | join("/")] | unique | map("./" + .)) as $d
      | ("." , $d[]) + "\u0000"' "$st/tracked" > "$st/dirs" || return 1
    reads_kids "$st/files" > "$st/kids.json" || return 1
    reads_built "$copy" > "$st/built" || return 1
    : > "$st/ready" || return 1
  fi
  [ -f "$st/written.json" ] || printf '{"lists":{},"files":{}}\n' > "$st/written.json"
  reads_unbuild "$copy" "$st" || return 1
  : > "$st/ref" && touch -t "$READS_OLD_DAY" "$st/ref" || return 1
  : > "$st/mark" || return 1
  [ "$slack" -eq 0 ] && [ "$exact" = true ] || reads_mark "$st/mark" "$slack" || return 1
  # Never earlier than the first mark: nothing made with the copy is a write.
  [ ! "$st/mark0" -nt "$st/mark" ] || touch -r "$st/mark0" "$st/mark" || return 1
  # A run moves the access time of only what it read, and its collection left those paths
  # (moved: files read, folders listed, written files opened): the next reset sets back just
  # them. Without that list (the copy's first run, or a run that was never collected) every
  # tracked file and every written file is set back. The folders always are: the collection
  # itself lists them (find) after it took the list of those that moved.
  if [ -f "$st/moved" ]; then
    reads_touch "$st/moved" "$copy"
    rm -f "$st/moved"
  else
    jq -j '.files | keys[] | "./" + . + "\u0000"' "$st/written.json" > "$st/wlist" || return 1
    reads_touch "$st/files" "$copy"
    reads_touch "$st/wlist" "$copy"
  fi
  reads_touch "$st/dirs" "$copy"
  touch -a -t "$READS_OLD" "$copy/.git" 2> /dev/null || return 1
  reads_subgits "$copy" | xargs -0 -r touch -a -t "$READS_OLD" 2> /dev/null || return 1
}

# reads_tracked COPY: the copy's tracked paths, NUL-separated, each checked-out
# submodule's (vbw_subs, a worktree of its own in the copy, lib/proofcopy.sh)
# under its folder.
reads_tracked() {
  local p
  git -C "$1" ls-files -z || return 1
  while IFS= read -r -d '' p; do
    [ -e "$1/$p/.git" ] || continue
    git -C "$1/$p" ls-files -z | jq -Rj --arg p "$p" 'split("\u0000")[] | select(length > 0) | $p + "/" + . + "\u0000"' || return 1
  done < <(vbw_subs)
}

# reads_subgits COPY: the .git file of each submodule's worktree in the copy,
# NUL-separated: git used there is git use as much as in the copy itself.
reads_subgits() {
  local p
  while IFS= read -r -d '' p; do
    [ ! -f "$1/$p/.git" ] || vbw_out '%s\0' "$1/$p/.git"
  done < <(vbw_subs)
}

# reads_kids FILES: what a collection needs to know of the tracked paths in FILES (NUL-
# separated), as one JSON object {kids, files}: kids maps each folder (the empty text for
# the top) to the names directly in it, files holds every tracked file path.
reads_kids() {
  jq -Rs -c '
    def strip: if . == "." then "" else sub("^\\./"; "") end;
    (split("\u0000") | map(select(length > 0) | strip)) as $f
    | {kids: ([$f[] | split("/") as $p | range(0; $p | length) | {k: ($p[:.] | join("/")), v: $p[.]}]
        | group_by(.k) | map({key: .[0].k, value: (map(.v) | unique)}) | from_entries),
       files: ([$f[] | {key: ., value: true}] | from_entries)}' "$1"
}

# reads_program_dir COPY PROGRAM: the folder, relative to COPY ("." for the top), that
# holds PROGRAM when PROGRAM is a file inside COPY: resolved from the name by path
# (a name with a slash, from the copy, where a unit runs) or by PATH lookup. Nothing
# printed (and 1) for a program outside the copy or none. R226: the system notes the
# folder of a file as listed on the first exec of a new file by its path (measured on
# macOS, 2026-10-30; Linux notes nothing), which is no read of the test's.
reads_program_dir() {
  local copy=$1 prog=${2:-} f d root rel
  [ -n "$prog" ] || return 1
  case "$prog" in
    */*) f=$prog ;;
    *) f=$(cd "$copy" && command -v -- "$prog" 2> /dev/null) || return 1 ;;
  esac
  case "$f" in /*) ;; *) f=$copy/$f ;; esac
  [ -f "$f" ] || return 1
  d=$(cd "${f%/*}" 2> /dev/null && pwd -P) || return 1
  root=$(cd "$copy" 2> /dev/null && pwd -P) || return 1
  case "$d" in
    "$root") rel=. ;;
    "$root"/*) rel=${d#"$root"/} ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$rel"
}

# reads_collect COPY STATE [PROGRAM]: after a run; prints its read list as one JSON
# object {files, dirs: [{path, fp}], git}. The folder holding PROGRAM (the unit's
# first word, when it is a file inside COPY) is left out of the run's own listings:
# the system lists it on the first exec of that file, never the test. Limit: a test
# that both executes a script of the folder by its path and lists that folder itself
# loses that listing. fp fingerprints the names of the
# tracked files and folders directly in the listed folder: the SHA-256 of the
# compact JSON text [path, names]. A fixed number of processes whatever the
# number of tracked or listed paths: one find walks the copy once for every path
# whose access time moved, one jq sorts them into files read, folders listed and
# written files opened (by the tracked paths kept at the first reset), and builds
# every listing text from the parent-to-names map; bash writes one scratch file per
# text, one sha256 call hashes them all, one jq assembles the list. Reads the
# written files this run opened (set back by the reset) for their lists, and records
# the files it wrote with a single copy of this list (written.json: lists by run id,
# files by path).
reads_collect() {
  local copy=$1 st=$2 git=false line n=0 id skip=
  local -a names
  skip=$(reads_program_dir "$copy" "${3:-}") || skip=
  [ -z "$(find "$copy/.git" -maxdepth 0 -anewer "$st/ref" -print 2> /dev/null)" ] || git=true
  [ "$git" = true ] || [ -z "$(reads_subgits "$copy" | xargs -0 -r -I{} find {} -maxdepth 0 -anewer "$st/ref" -print 2> /dev/null)" ] || git=true
  (cd "$copy" && find . -path ./.git -prune -o -anewer "$st/ref" -print0) > "$st/moved" 2> /dev/null || true
  # The tracked paths never change (the copy is a detached checkout): sorted out once at the
  # first reset, here only when a state lacks it.
  [ -s "$st/kids.json" ] || reads_kids "$st/files" > "$st/kids.json" || return 1
  jq -nc --rawfile moved "$st/moved" --slurpfile k "$st/kids.json" --arg skip "$skip" '
    def strip: if . == "." then "" else sub("^\\./"; "") end;
    $k[0].kids as $kids
    | ($moved | split("\u0000") | map(select(length > 0) | strip))[]
    | . as $d
    | select($skip == "" or $d != ($skip | strip))
    | select($kids | has($d))
    | [(if $d == "" then "." else $d end), ($kids[$d] | unique)]' > "$st/listings"
  rm -rf "$st/fp"; mkdir -p "$st/fp"
  while IFS= read -r line; do
    printf '%s' "$line" > "$st/fp/$n"
    names[n]=$n
    n=$((n + 1))
  done < "$st/listings"
  : > "$st/hashes"
  if [ "$n" -gt 0 ]; then
    # One call; each line is "<hash>  <file>" with either sha256sum or shasum.
    (cd "$st/fp" && { if command -v sha256sum > /dev/null 2>&1; then sha256sum "${names[@]}"; else shasum -a 256 "${names[@]}"; fi; }) > "$st/hashes" || return 1
  fi
  jq -nc --rawfile moved "$st/moved" --slurpfile k "$st/kids.json" --rawfile l "$st/listings" --rawfile h "$st/hashes" --slurpfile w "$st/written.json" --argjson g "$git" '
    def strip: sub("^\\./"; "");
    ($moved | split("\u0000") | map(select(length > 0) | strip)) as $m
    | ($h | split("\n") | map(select(length > 0) | split("  ")[0])) as $fps
    | ($l | split("\n") | map(select(length > 0) | fromjson)) as $ls
    | {files: [$m[] | select($k[0].files[.])], dirs: [range(0; $ls | length) as $i | {path: $ls[$i][0], fp: $fps[$i]}], git: $g} as $own
    | ([$m[] as $p | ($w[0].files[$p] // [])[]] | unique) as $ids
    | reduce $ids[] as $id ($own; ($w[0].lists[$id]) as $l
        | {files: (.files + $l.files), dirs: (.dirs + $l.dirs), git: (.git or $l.git)})
    | {files: (.files | unique), dirs: (.dirs | unique_by(.path)), git}' > "$st/last.json" || return 1
  # What the run wrote (not in .git) now carries its read list, stored once.
  (cd "$copy" && find . -path ./.git -prune -o -type f -newer "$st/mark" -print0) > "$st/new" 2> /dev/null || true
  if [ -s "$st/new" ]; then
    id=$(( $(cat "$st/runid" 2> /dev/null || echo 0) + 1 ))
    printf '%s\n' "$id" > "$st/runid"
    jq -c --rawfile n "$st/new" --slurpfile r "$st/last.json" --arg id "$id" '
      def strip: sub("^\\./"; "");
      .lists[$id] = $r[0]
      | reduce ($n | split("\u0000") | map(select(length > 0) | strip))[] as $p (.; .files[$p] += [$id])' \
      "$st/written.json" > "$st/written.tmp" && mv "$st/written.tmp" "$st/written.json" || return 1
  fi
  cat "$st/last.json"
}
