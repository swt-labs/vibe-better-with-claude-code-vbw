#!/usr/bin/env bats
# R21: contributor files name only commands, paths and tools that exist in VBW 2.
# tools/check-contributor-files.sh [ROOT] reads CONTRIBUTING.md, AGENTS.md,
# .github/PULL_REQUEST_TEMPLATE.md, .github/ISSUE_TEMPLATE/* and
# .github/copilot-instructions.md under ROOT and exits 0 only if every path,
# /vbw:command and tool they name exists under ROOT and none names .vbw-planning.

load helper

CHECK="$BATS_TEST_DIRNAME/../tools/check-contributor-files.sh"

setup() { vbw_setup; [ -f "$CHECK" ]; }
teardown() { vbw_teardown; }

# A minimal tree: one tool, one skill, and a clean CONTRIBUTING.md.
mini() {
  mkdir -p tools plugin/skills/vibe
  : > tools/ok.sh
  : > plugin/skills/vibe/SKILL.md
  printf 'Run `bash tools/ok.sh`, then `/vbw:vibe`.\n' > CONTRIBUTING.md
}

@test "the repository's contributor files name only what exists" {
  run bash "$CHECK" "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "no contributor file mentions .vbw-planning" {
  cd "$REPO_ROOT"
  run grep -rl -e '\.vbw-planning' CONTRIBUTING.md AGENTS.md .github/PULL_REQUEST_TEMPLATE.md \
    .github/ISSUE_TEMPLATE .github/copilot-instructions.md
  [ "$status" -eq 1 ]
}

@test "selftest: a clean tree passes" {
  mini
  run bash "$CHECK" "$PROJECT"
  [ "$status" -eq 0 ]
}

@test "selftest: a nonexistent path fails and is named" {
  mini
  printf 'See `tools/gone.sh`.\n' >> CONTRIBUTING.md
  run bash "$CHECK" "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *tools/gone.sh* ]]
}

@test "selftest: a nonexistent /vbw: command fails" {
  mini
  printf 'Try `/vbw:nonesuch`.\n' > AGENTS.md
  run bash "$CHECK" "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *nonesuch* ]]
}

@test "selftest: .vbw-planning fails" {
  mini
  mkdir -p .github
  printf 'Old: .vbw-planning/\n' > .github/PULL_REQUEST_TEMPLATE.md
  run bash "$CHECK" "$PROJECT"
  [ "$status" -ne 0 ]
}

@test "selftest: a bad path in an issue template fails" {
  mini
  mkdir -p .github/ISSUE_TEMPLATE
  printf 'Run `scripts/old.sh`.\n' > .github/ISSUE_TEMPLATE/bug.md
  run bash "$CHECK" "$PROJECT"
  [ "$status" -ne 0 ]
}
