#!/usr/bin/env bats
# R65: the user documentation describes the review of an old VBW 1 folder and the
# choice after it: when it happens, what it reports, how the recommendation is
# reached, what each choice does, that it is asked once and can be run again, and
# that it only reads (L1: facts in the text).

load helper

DOC="$REPO_ROOT/docs/convert.md"
INTERVIEW="$REPO_ROOT/docs/interview.md"

@test "R65: docs/convert.md describes the review and says when it happens: in the interview, right after the level" {
  grep -qF 'vbw legacy review' "$DOC"
  grep -qiE 'review' "$DOC"
  grep -qiE 'interview' "$DOC"
  grep -qiE 'level' "$DOC"
}

@test "R65: it names the four things the review reports" {
  grep -qiE 'how much (was )?finished|finished' "$DOC"
  grep -qiE 'how recently|last used' "$DOC"
  grep -qiE 'still match|match the (current )?code' "$DOC"
  grep -qiE 'half[- ]done|half done' "$DOC"
}

@test "R65: it states the rule behind the recommendation, so the same folder always gets the same answer" {
  grep -qiE 'same (folder|answer|recommendation)' "$DOC"
  grep -qiE 'recommend' "$DOC"
  grep -qiE 'start fresh' "$DOC"
  grep -qiE 'a year|365' "$DOC"
}

@test "R65: it says what each choice does: convert runs /vbw:convert, start fresh converts nothing, the old folder is never changed" {
  grep -qF '/vbw:convert' "$DOC"
  grep -qF 'vbw legacy choose' "$DOC"
  grep -qiE 'untouched|never changes|stays' "$DOC"
}

@test "R65: it covers what the review does with a folder it cannot read, and that the review only reads" {
  grep -qiE 'could not (be )?read|cannot (be )?read|unreadable' "$DOC"
  grep -qiE 'only reads|reads files only|read-only|never runs' "$DOC"
}

@test "R65: it says the choice is asked once per project and the review can be run again on demand" {
  grep -qiE 'once' "$DOC"
  grep -qiE 'on demand|any time|whenever' "$DOC"
  grep -qF 'project.legacy' "$DOC"
}

@test "R65: docs/interview.md lists the old-folder step in the interview's order" {
  grep -qiE 'VBW 1' "$INTERVIEW"
  grep -qF 'docs/convert.md' "$INTERVIEW"
}

@test "R65: the README lists the review and links the page" {
  grep -qiE 'review' "$REPO_ROOT/README.md"
  grep -qF 'docs/convert.md' "$REPO_ROOT/README.md"
  grep -iE 'convert.*(review|fresh)|(review|fresh).*convert' "$REPO_ROOT/README.md" | grep -qF 'docs/convert.md'
}
