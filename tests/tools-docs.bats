#!/usr/bin/env bats
# R62: the user documentation explains the tools offer: the one-time question,
# what yes and no do, where the picks come from and what is warned about, that
# nothing is installed before the user approves, the project-or-all-projects
# choice, and that /vbw:skills runs it again any time (L1: facts in the text).

load helper

DOC="$REPO_ROOT/docs/tools.md"

@test "R62: docs/tools.md exists and says what the offer is, in plain words" {
  [ -f "$DOC" ]
  grep -qiE 'linter' "$DOC"
  grep -qiE 'formatter' "$DOC"
  grep -qiE 'scanner' "$DOC"
  grep -qiE 'test framework' "$DOC"
}

@test "R62: it says the question is asked once per project and what yes and no do" {
  grep -qiE 'once' "$DOC"
  grep -qiE '(^|[^a-z])yes([^a-z]|$)' "$DOC"
  grep -qiE '(^|[^a-z])no([^a-z]|$)' "$DOC"
  grep -qiE 'nothing is (searched|installed)|no scout' "$DOC"
}

@test "R62: it says where picks come from: trusted sources, open source as proposed picks, anything else with a warning" {
  grep -qiE 'trusted' "$DOC"
  grep -qiE 'open[- ]source' "$DOC"
  grep -qiE 'warning' "$DOC"
}

@test "R62: it says nothing is installed before approval, and that approving some installs only those" {
  grep -qiE 'nothing is installed' "$DOC"
  grep -qiE 'approve' "$DOC"
  grep -qiE 'only (the )?(ones|items|tools)? ?(you )?(approve|chose|pick)' "$DOC"
}

@test "R62: it says each approved tool goes into this project or all your projects, by your choice" {
  grep -qiE 'this project' "$DOC"
  grep -qiE 'all (of )?your projects' "$DOC"
}

@test "R62: it names /vbw:skills as the way to run it again any time and vbw tools as the stored answer" {
  grep -qF '/vbw:skills' "$DOC"
  grep -qF 'vbw tools' "$DOC"
  grep -qiE 'any time|at any time|whenever' "$DOC"
}

@test "R62: the README lists the offer and links the page" {
  grep -qF 'docs/tools.md' "$REPO_ROOT/README.md"
}
