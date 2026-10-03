#!/usr/bin/env bats
# Protected check files are approved byte for byte, so no formatter may change
# them later (a field report, Portfolium on 2.0.12: the Lead's unformatted Rust
# tests were rewritten by a Dev's `cargo fmt --all`, which voided the approved
# contract three times in one day).

load helper

AGENTS="$BATS_TEST_DIRNAME/../plugin/agents"

@test "the Lead runs the project's formatter and linter on every check file before vbw apply" {
  grep -qi 'formatter' "$AGENTS/lead.md"
  grep -qi 'linter' "$AGENTS/lead.md"
  grep -q 'cargo fmt' "$AGENTS/lead.md"
  # in the self-review too
  awk '/^## Stage 3/{on=1} /^## Stage 4/{on=0} on' "$AGENTS/lead.md" | grep -qi 'format'
}

@test "the Dev never lets a formatter rewrite a check file" {
  grep -qi 'formatter' "$AGENTS/dev.md"
  grep -qi 'check file' "$AGENTS/dev.md"
}
