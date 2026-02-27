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
  [ "$output" -eq 4 ]
}

@test "checkpoint banner has no rule lines wider than 34" {
  run bash -c "grep -E '━{35,}' '$PROJECT_ROOT/commands/verify.md'"
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
  grep -q 'exceeds 30 characters' "$PROJECT_ROOT/commands/verify.md"
}

@test "question field uses test-id prefix instead of Expected prefix" {
  # New format: "{test-id}: {short expected result}" instead of "Expected: {expected result}"
  run bash -c "grep 'question:.*Expected:' '$PROJECT_ROOT/commands/verify.md'"
  [ "$status" -eq 1 ]
}

@test "question field uses test-id prefix pattern" {
  grep -q 'question:.*{test-id}:' "$PROJECT_ROOT/commands/verify.md"
}

# ── UAT summary banner format ──────────────────────────────────────────────
# The session-complete summary banner must match the same short format.

@test "UAT summary banner uses 34-char rule lines" {
  # The summary section ("Phase {NN}: {name} / UAT Complete") must also use short rules
  run bash -c "sed -n '/Session complete/,\$p' '$PROJECT_ROOT/commands/verify.md' | grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "UAT summary banner has no rule lines wider than 34" {
  run bash -c "sed -n '/Session complete/,\$p' '$PROJECT_ROOT/commands/verify.md' | grep -E '━{35,}'"
  [ "$status" -eq 1 ]
}

@test "UAT summary splits phase name and completion status onto separate lines" {
  # Old: "Phase {NN}: {name} — UAT Complete" on one line
  # New: "Phase {NN}: {name}" and "UAT Complete" on separate lines
  run bash -c "grep 'UAT Complete' '$PROJECT_ROOT/commands/verify.md' | grep -v 'Phase'"
  [ "$status" -eq 0 ]
}

@test "UAT summary old combined-line format is absent" {
  # Ensure old "Phase ... UAT Complete" single-line pattern cannot reappear
  run bash -c "grep -E 'Phase.*UAT Complete' '$PROJECT_ROOT/commands/verify.md'"
  [ "$status" -eq 1 ]
}

# ── Cross-file consistency ──────────────────────────────────────────────────
# execute-protocol.md and vbw-brand-essentials.md must use the same short format.

@test "execute-protocol.md uses 34-char checkpoint rule lines" {
  run bash -c "grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$' '$PROJECT_ROOT/references/execute-protocol.md'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 4 ]
}

@test "execute-protocol.md has no wide rule lines" {
  run bash -c "grep -E '━{35,}' '$PROJECT_ROOT/references/execute-protocol.md'"
  [ "$status" -eq 1 ]
}

@test "execute-protocol.md does not use old Expected question prefix" {
  run bash -c "grep 'question:.*Expected:' '$PROJECT_ROOT/references/execute-protocol.md'"
  [ "$status" -eq 1 ]
}

@test "brand-essentials.md uses 34-char checkpoint rule lines" {
  run bash -c "grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$' '$PROJECT_ROOT/references/vbw-brand-essentials.md'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
}

@test "brand-essentials.md has no wide rule lines" {
  run bash -c "grep -E '━{35,}' '$PROJECT_ROOT/references/vbw-brand-essentials.md'"
  [ "$status" -eq 1 ]
}

@test "brand-essentials.md splits counter and plan title" {
  # Old: "CHECKPOINT 1/3 — 01-01: Core Feature" on one line
  # New: counter and plan title on separate lines
  run bash -c "grep 'CHECKPOINT.*01-01' '$PROJECT_ROOT/references/vbw-brand-essentials.md'"
  [ "$status" -eq 1 ]
}

# ── 2-space content indent ──────────────────────────────────────────────────
# Content lines between rule pairs must use a 2-space indent.

@test "verify.md CHECKPOINT has 2-space indented content" {
  grep -q '  CHECKPOINT {NN}/{total}' "$PROJECT_ROOT/commands/verify.md"
  grep -q '  {plan-id}: {plan-title}' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify.md UAT summary has 2-space indented content" {
  grep -q '  Phase {NN}: {name}' "$PROJECT_ROOT/commands/verify.md"
  grep -q '  UAT Complete' "$PROJECT_ROOT/commands/verify.md"
}

@test "execute-protocol.md CHECKPOINT has 2-space indented content" {
  # Content lines inside CHECKPOINT banner must have 2-space indent
  grep -q '  CHECKPOINT {NN}/{total}' "$PROJECT_ROOT/references/execute-protocol.md"
  grep -q '  {plan-id}: {plan-title}' "$PROJECT_ROOT/references/execute-protocol.md"
}

@test "execute-protocol.md Phase Built has 2-space indented content" {
  grep -q '  Phase {NN}: {name}' "$PROJECT_ROOT/references/execute-protocol.md"
  grep -q '  Built' "$PROJECT_ROOT/references/execute-protocol.md"
}

@test "brand-essentials.md has 2-space indented content" {
  grep -q '  CHECKPOINT 1/3' "$PROJECT_ROOT/references/vbw-brand-essentials.md"
  grep -q '  01-01: Core Feature' "$PROJECT_ROOT/references/vbw-brand-essentials.md"
}

@test "debug.md has 2-space indented content" {
  grep -q '  Bug Investigation Complete' "$PROJECT_ROOT/commands/debug.md"
}

@test "qa.md has 2-space indented content" {
  grep -q '  Phase {NN}: {name} -- Verified' "$PROJECT_ROOT/commands/qa.md"
}

@test "status.md has 2-space indented content" {
  grep -q '  {project-name}' "$PROJECT_ROOT/commands/status.md"
}

@test "init.md has 2-space indented content" {
  grep -q '  VBW Initialization Complete' "$PROJECT_ROOT/commands/init.md"
}

# ── Other command files: 34-char rule lines ─────────────────────────────────

@test "debug.md uses 34-char rule lines" {
  run bash -c "grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$' '$PROJECT_ROOT/commands/debug.md'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "debug.md has no wide rule lines" {
  run bash -c "grep -E '━{35,}' '$PROJECT_ROOT/commands/debug.md'"
  [ "$status" -eq 1 ]
}

@test "qa.md uses 34-char rule lines" {
  run bash -c "grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$' '$PROJECT_ROOT/commands/qa.md'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "qa.md has no wide rule lines" {
  run bash -c "grep -E '━{35,}' '$PROJECT_ROOT/commands/qa.md'"
  [ "$status" -eq 1 ]
}

@test "status.md uses 34-char rule lines" {
  run bash -c "grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$' '$PROJECT_ROOT/commands/status.md'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "status.md has no wide rule lines" {
  run bash -c "grep -E '━{35,}' '$PROJECT_ROOT/commands/status.md'"
  [ "$status" -eq 1 ]
}

@test "init.md uses 34-char rule lines" {
  run bash -c "grep -c '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$' '$PROJECT_ROOT/commands/init.md'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "init.md has no wide rule lines" {
  run bash -c "grep -E '━{35,}' '$PROJECT_ROOT/commands/init.md'"
  [ "$status" -eq 1 ]
}
