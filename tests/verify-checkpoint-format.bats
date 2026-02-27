#!/usr/bin/env bats

load test_helper

# ── CHECKPOINT banner format (issue #166) ───────────────────────────────────
# The CHECKPOINT banner must use short rule lines and split the counter from
# the plan title to avoid wrapping in narrow terminals. A trailing blank line
# after scenario text prevents the AskUserQuestion prompt from clipping
# the preceding line (known Claude Code TUI bug).

@test "checkpoint banner rule line is 34 chars" {
  # The banner uses ━ (U+2501) rule characters — exactly 34 of them
  run bash -c "grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$' '$PROJECT_ROOT/commands/verify.md'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "checkpoint banner does not exceed 62-char rule" {
  # Ensure no 62-char rule lines remain (old format)
  run bash -c "grep -E '━{50,}' '$PROJECT_ROOT/commands/verify.md'"
  [ "$status" -eq 1 ]
}

@test "checkpoint counter and plan title are on separate lines" {
  # The old format had "CHECKPOINT {NN}/{total} — {plan-id}: {plan-title}" on one line
  # The new format splits these: counter on one line, plan-id on next
  run bash -c "grep -c 'CHECKPOINT {NN}/{total}$' '$PROJECT_ROOT/commands/verify.md'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "old single-line checkpoint format is gone" {
  # Must not contain the old combined format (counter + plan-id on same line)
  run bash -c "grep 'CHECKPOINT.*{plan-id}' '$PROJECT_ROOT/commands/verify.md'"
  [ "$status" -eq 1 ]
}

@test "scenario description block ends with trailing blank line" {
  # The code block showing the scenario must end with a blank line before ```
  # This buffers against Claude Code TUI clipping
  run bash -c "grep -A1 '{scenario description}' '$PROJECT_ROOT/commands/verify.md' | grep -c '^$'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "verify.md documents TUI wrapping/clipping workaround" {
  grep -q 'Claude Code TUI' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify.md caps question field length" {
  grep -q 'under 70 characters' "$PROJECT_ROOT/commands/verify.md"
}

@test "checkpoint banner includes plan-title truncation rule" {
  grep -q 'exceeds 60 characters' "$PROJECT_ROOT/commands/verify.md"
}

@test "question field uses test-id prefix instead of Expected prefix" {
  # New format: "{test-id}: {short expected result}" instead of "Expected: {expected result}"
  run bash -c "grep 'question:.*Expected:' '$PROJECT_ROOT/commands/verify.md'"
  [ "$status" -eq 1 ]
}

@test "question field uses test-id prefix pattern" {
  grep -q 'question:.*{test-id}:' "$PROJECT_ROOT/commands/verify.md"
}
