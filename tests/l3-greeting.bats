#!/usr/bin/env bats
# R59 (F34): the real-user script recognises the interview's new level question
# everywhere it looks for it, so the level options are checked in real runs.
# L1: the script's text; no Claude Code runs here.

load helper

SUITE="$BATS_TEST_DIRNAME/../tools/l3-suite.sh"

@test "R59: the real-user script no longer looks for the old level question" {
  ! grep -n 'How much software' "$SUITE"
}

@test "R59: the level options check is keyed on the greeting's question, with the four options in order" {
  grep -q '"What is your level of proficiency": \["never", "small scripts or no-code", "professionally", "senior engineer"\]' "$SUITE"
}

@test "R59: the interview counts as asked when the level question was asked" {
  grep -qF 'interview (set|keep)|level of proficiency' "$SUITE"
}
