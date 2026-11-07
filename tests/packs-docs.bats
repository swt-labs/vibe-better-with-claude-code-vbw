#!/usr/bin/env bats
# R261 (docs/packs.md): the user docs say what a stack pack is, how a plan gets one
# (by its files; the Lead by the project's tracked files, since plans do not exist yet
# at planning), what its folder holds (a manifest and one text per role), that it never
# touches the contract, and how to contribute one (manifest, role texts, the
# real-codebase evidence a pack needs before it ships, a decision-style review).
# CONTRIBUTING.md and README.md link to the page; docs/ideas.md's Stack packs entry
# points to it and keeps only what is still open. L1: wording pins.

load helper

DOC="$REPO_ROOT/docs/packs.md"

@test "R261 docs: docs/packs.md says what a pack is, how a plan gets one, and that the Lead's pack comes from the tracked files" {
  [ -f "$DOC" ] || { echo "no docs/packs.md"; false; }
  grep -qi 'stack pack' "$DOC"
  grep -qiE 'plan.*files|files.*plan' "$DOC"
  grep -qE 'Cargo\.toml' "$DOC" && grep -qE '\*\.rs' "$DOC"
  grep -qiE 'tracked files|git ls-files' "$DOC"
  grep -qiE 'Lead' "$DOC" && grep -qiE 'Dev' "$DOC" && grep -qiE 'QA' "$DOC"
}

@test "R261 docs: docs/packs.md names the folder's contents and says a pack never touches the contract or the record" {
  grep -qF 'pack.json' "$DOC"
  grep -qF 'lead.md' "$DOC" && grep -qF 'dev.md' "$DOC" && grep -qF 'qa.md' "$DOC"
  grep -qiE 'patterns' "$DOC"
  grep -qiE 'contract' "$DOC" && grep -qiE 'never|not|no ' "$DOC"
  grep -qiE 'un-?approv' "$DOC"
  grep -qiE 'record' "$DOC"
}

@test "R261 docs: docs/packs.md says how to contribute a pack: manifest, role texts, real-codebase evidence before it ships, review" {
  grep -qiE 'contribut' "$DOC"
  grep -qiE 'real (codebase|project)' "$DOC"
  grep -qiE 'review' "$DOC"
  grep -qiE 'one more folder|a folder' "$DOC"
}

@test "R261 docs: CONTRIBUTING.md and README.md link to docs/packs.md" {
  grep -q 'docs/packs\.md' "$REPO_ROOT/CONTRIBUTING.md" || { echo "CONTRIBUTING.md does not link docs/packs.md"; false; }
  grep -q 'docs/packs\.md' "$REPO_ROOT/README.md" || { echo "README.md does not link docs/packs.md"; false; }
}

@test "R261 docs: docs/ideas.md's Stack packs entry points to the shipped page and keeps only what is still open" {
  local ideas="$REPO_ROOT/docs/ideas.md" entry
  entry=$(awk '/^### Stack packs/{p=1; print; next} /^### /{p=0} p' "$ideas")
  [ -n "$entry" ] || { echo "no Stack packs entry in docs/ideas.md"; false; }
  printf '%s\n' "$entry" | grep -q 'docs/packs\.md' || { echo "the entry does not point to docs/packs.md"; false; }
  printf '%s\n' "$entry" | grep -qi 'init' || { echo "the entry no longer keeps the open init question"; false; }
  printf '%s\n' "$entry" | grep -qi 'check form' || { echo "the entry no longer keeps the open check forms"; false; }
  printf '%s\n' "$entry" | grep -qi 'mutation' || { echo "the entry no longer keeps the open mutation step"; false; }
  ! printf '%s\n' "$entry" | grep -q 'test = false' || { echo "the shipped first contents are still listed as ideas"; false; }
  ! printf '%s\n' "$entry" | grep -qi 'First contents' || { echo "the shipped first contents are still listed as ideas"; false; }
}

# R263: docs/packs.md's Rust pack section lists the parallel-plan and real-command
# points word for word with the pack texts: the sentence of each rule is taken from
# the pack file by its key phrase and must appear, whitespace folded, in the docs.
rust_section() { awk '/^## The Rust pack/ {p=1; next} p && /^## / {exit} p' "$DOC" | tr '\n' ' ' | tr -s ' '; }
# sentence FILE PHRASE: the sentence of FILE (folded) that holds PHRASE, without its list dash.
sentence() { tr '\n' ' ' < "$1" | tr -s ' ' | grep -oE "[^.]*$2[^.]*\." | head -n 1 | sed -E 's/^ *(- )?//'; }
# docs_holds FILE PHRASE: the docs section holds that sentence word for word.
docs_holds() {
  local s
  s=$(sentence "$1" "$2")
  [ -n "$s" ] || { echo "${1##*/} has no sentence with: $2"; return 1; }
  rust_section | grep -qF -- "$s" || { echo "docs/packs.md's Rust pack section does not hold word for word: $s"; return 1; }
}

@test "R263 docs: the Rust pack section holds, word for word, the Lead's disjoint-files, one-manifest-change and skeleton-or-split sentences, the waiting-on-the-adding-plan sentence, QA's compile-or-test sentence and the path-dependency sentence" {
  local packs="$REPO_ROOT/plugin/packs/rust"
  docs_holds "$packs/lead.md" 'no file in common'
  docs_holds "$packs/lead.md" 'one plan at a time'
  docs_holds "$packs/lead.md" 'skeleton'
  docs_holds "$packs/lead.md" '`after`'
  docs_holds "$packs/qa.md" 'only when'
  docs_holds "$packs/lead.md" 'path dependency'
  rust_section | grep -Eiq 'added or moved' || { echo "the section does not name a moved dependency"; false; }
}
