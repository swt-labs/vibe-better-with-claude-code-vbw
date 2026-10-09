#!/usr/bin/env bats
# R123 (L1): the what's-next step runs after vbw ship, the last command of a
# milestone, so nothing later would commit what it stores. vbw recommend
# commits the record itself, leaving the project clean, and never takes the
# user's own staged files with it (L3 greenfield, 2026-10-09: the record was
# left modified after the ship).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  "$VBW" todo add "Refunds" > /dev/null
  git add .vbw && git commit -q -m "chore(vbw): init"
}

teardown() { vbw_teardown; }

@test "R123: vbw recommend commits the record, so the project is left clean" {
  printf '%s' '{"top": {"text": "Refunds", "reason": "It is the only open item.", "size": "small", "source": "T1"}, "runners": []}' | "$VBW" recommend
  [ -z "$(git status --porcelain -- .vbw/record.json)" ] || { git status --porcelain; false; }
  git log -1 --format=%s | grep -q "what's next"
}

@test "R123: vbw recommend leaves the user's staged files staged and uncommitted" {
  printf 'mine\n' > notes.txt
  git add notes.txt
  printf '%s' '{"top": {"text": "Refunds", "reason": "It is the only open item.", "size": "small", "source": "T1"}, "runners": []}' | "$VBW" recommend
  [ "$(git diff --cached --name-only)" = "notes.txt" ]
  ! git show --name-only --format= HEAD | grep -qx notes.txt
}
