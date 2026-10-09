#!/usr/bin/env bash
# ci-scope.sh BASE HEAD: decide what a push (or pull request) must test.
# Reads the git repository of the current folder and prints three lines for
# GitHub's step outputs:
#   scope=full|some|none
#   files=<test files to run, sorted, space-separated; empty unless some>
#   reason=<why, in plain words>
# Changed files are those that differ between BASE and HEAD (every commit of
# the push). A renamed or copied file is sorted under its new path and its old
# path. Safe paths: .vbw/record.json and .vbw/spec.md; files inside a saved
# results folder named in .project.results of the record at BASE and at HEAD
# (CI guesses no folder, and a push cannot name a new folder to skip its own
# files); top-level tests/<name>.bats files (run unless deleted). Any other
# path means the full suite, as does an unknown BASE (empty, all zeros, not a
# commit here, or not an ancestor of HEAD).
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: ci-scope.sh BASE HEAD" >&2
  exit 2
fi
base=$1
head=$2

emit() { printf 'scope=%s\nfiles=%s\nreason=%s\n' "$1" "$2" "$3"; }
full() {
  emit full "" "$1"
  exit 0
}

# Empty or all zeros: GitHub's answer for a new branch.
[ -n "${base//0/}" ] || full "no previous tip to compare with (new branch)"
git cat-file -e "$base^{commit}" 2> /dev/null || full "the previous tip is not in this clone"
git cat-file -e "$head^{commit}" 2> /dev/null || full "the new tip is not in this clone"
git merge-base --is-ancestor "$base" "$head" 2> /dev/null || full "history was rewritten or the clone is shallow"

# Results folders: named by the record both before and after the push.
folders_at() {
  git show "$1:.vbw/record.json" 2> /dev/null \
    | jq -r '(.project.results // [])[] | select(type == "string") | select(length > 0) | select((startswith("/") or contains("..") or . == "." or . == "./") | not) | if endswith("/") then . else . + "/" end' 2> /dev/null || true
}
before=$(folders_at "$base")
after=$(folders_at "$head")
folders=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s\n' "$after" | grep -qxF -- "$f"; then
    folders="$folders
$f"
  fi
done << LIST
$before
LIST

in_results() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$1" in "$f"*) return 0 ;; esac
  done << LIST
$folders
LIST
  return 1
}

tests=""
# classify PATH DELETED(yes|no): returns for a safe path, ends the script via full otherwise.
classify() {
  local name
  case "$1" in
    .vbw/record.json | .vbw/spec.md) return 0 ;;
  esac
  if in_results "$1"; then return 0; fi
  case "$1" in
    tests/*/*) ;;
    tests/*.bats)
      name=${1#tests/}
      case "$name" in
        *[!A-Za-z0-9._-]*) ;;
        *)
          if [ "$2" = no ]; then
            tests="$tests
$1"
          fi
          return 0
          ;;
      esac
      ;;
  esac
  full "$1 is not a test file, the VBW record or a saved result"
}

status=""
while IFS= read -r -d '' item; do
  if [ -z "$status" ]; then
    status=$item
    continue
  fi
  case "$status" in
    D)
      classify "$item" yes
      status=""
      ;;
    R* | C*)
      # the old path first, then the new one
      classify "$item" yes
      IFS= read -r -d '' newp || true
      classify "$newp" no
      status=""
      ;;
    *)
      classify "$item" no
      status=""
      ;;
  esac
done < <(git diff --name-status -z -M "$base" "$head")

list=$(printf '%s\n' "$tests" | sed '/^$/d' | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')
if [ -n "$list" ]; then
  emit some "$list" "only test files changed: $list"
else
  emit none "" "only the VBW record or saved test results changed"
fi
