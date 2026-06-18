#!/usr/bin/env bash
set -euo pipefail

# verify-codex-agent-assets-contract.sh — Contract checks for Codex repo skills and custom agents

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

require_file() {
  local path="$1"
  local label="$2"

  if [ -f "$path" ]; then
    pass "$label exists"
  else
    fail "$label missing: $path"
  fi
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE "$pattern" "$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

reject_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE "$pattern" "$path"; then
    fail "$label"
  else
    pass "$label"
  fi
}

echo "=== Codex Agent Asset Contract Verification ==="

CODEX_AGENT_DIR="$ROOT/.codex/agents"
SKILL_DIR="$ROOT/.agents/skills"

expected_agents=(
  vbw-fix-planner
  vbw-qa-investigator
  vbw-contributor-pr-reviewer
)

for agent in "${expected_agents[@]}"; do
  agent_file="$CODEX_AGENT_DIR/$agent.toml"
  require_file "$agent_file" "Codex custom agent $agent"
  [ -f "$agent_file" ] || continue

  require_contains "$agent_file" '^name = "[^"]+"' "$agent has name"
  require_contains "$agent_file" '^description = "[^"]+"' "$agent has description"
  require_contains "$agent_file" '^developer_instructions = """' "$agent has developer instructions"
  reject_contains "$agent_file" '^(tools|agents|handoffs|argument-hint|user-invocable|disable-model-invocation):' "$agent has no Copilot agent frontmatter keys"
  reject_contains "$agent_file" 'GPT-5\.4 \(copilot\)|github/request_copilot_review|wait-review|copilot-pull-request-reviewer|vbw-qa-investigator-gpt-54|gpt-5\.4|GPT-5\.4|cross-model QA' "$agent has no legacy bot-review or cross-model QA workflow terms"
done

if [ -e "$CODEX_AGENT_DIR/vbw-qa-investigator-gpt-54.toml" ]; then
  fail "obsolete gpt-5.4 cross-model QA agent should be removed"
else
  pass "obsolete gpt-5.4 cross-model QA agent removed"
fi

require_contains "$CODEX_AGENT_DIR/vbw-qa-investigator.toml" '^model = "gpt-5\.5"$' "primary QA agent is pinned to latest GPT model"
require_contains "$CODEX_AGENT_DIR/vbw-qa-investigator.toml" '^model_reasoning_effort = "xhigh"$' "primary QA agent uses x-high reasoning"
require_contains "$CODEX_AGENT_DIR/vbw-qa-investigator.toml" '^sandbox_mode = "read-only"$' "primary QA agent is read-only"

expected_skills=(
  vbw-fix-issue
  vbw-review-contributor-pr
  vbw-qa-investigator
)

for skill in "${expected_skills[@]}"; do
  skill_file="$SKILL_DIR/$skill/SKILL.md"
  metadata_file="$SKILL_DIR/$skill/agents/openai.yaml"

  require_file "$skill_file" "skill $skill SKILL.md"
  require_file "$metadata_file" "skill $skill openai metadata"
  [ -f "$skill_file" ] || continue
  [ -f "$metadata_file" ] || continue

  require_contains "$skill_file" '^---$' "$skill has YAML frontmatter boundary"
  require_contains "$skill_file" "^name: $skill$" "$skill has matching skill name"
  require_contains "$skill_file" '^description: .+' "$skill has description"
  require_contains "$metadata_file" 'allow_implicit_invocation: false' "$skill requires explicit invocation"
  if grep -qF 'default_prompt:' "$metadata_file" && grep -qF "\$$skill" "$metadata_file"; then
    pass "$skill default prompt mentions explicit skill invocation"
  else
    fail "$skill default prompt mentions explicit skill invocation"
  fi
  reject_contains "$skill_file" '^(tools|agents|handoffs|argument-hint|user-invocable|disable-model-invocation):' "$skill does not embed Copilot agent frontmatter"
  reject_contains "$skill_file" 'vbw-qa-investigator-gpt-54|gpt-5\.4|GPT-5\.4|cross-model QA' "$skill has no stale cross-model QA references"
done

require_file "$SKILL_DIR/vbw-fix-issue/references/issue-intake.md" "fix issue intake reference"
require_file "$SKILL_DIR/vbw-fix-issue/references/worktree-and-branch.md" "fix issue worktree reference"
require_file "$SKILL_DIR/vbw-fix-issue/references/implementation-and-tests.md" "fix issue implementation reference"
require_file "$SKILL_DIR/vbw-fix-issue/references/qa-loop.md" "fix issue QA loop reference"
require_file "$SKILL_DIR/vbw-fix-issue/references/pr-ci-gate.md" "fix issue PR/CI gate reference"
require_file "$SKILL_DIR/vbw-fix-issue/references/recovery.md" "fix issue recovery reference"
require_file "$SKILL_DIR/vbw-review-contributor-pr/references/blind-baseline-review.md" "contributor PR blind baseline reference"
require_file "$SKILL_DIR/vbw-qa-investigator/references/qa-contract.md" "QA contract reference"

if [ -d "$ROOT/.github/agents" ] && find "$ROOT/.github/agents" -type f -name '*.agent.md' | grep -q .; then
  fail "legacy .github/agents/*.agent.md files should be removed"
else
  pass "legacy .github/agents/*.agent.md files removed"
fi

legacy_refs=$(grep -RInE '\.github/agents|GPT-5\.4 \(copilot\)|github/request_copilot_review|wait-review|copilot-pull-request-reviewer|fresh Copilot review|Copilot PR review' \
  "$ROOT/.agents" \
  "$ROOT/.codex" \
  "$ROOT/.github/hooks/fix-issue-stop-guard.sh" \
  "$ROOT/.github/scripts/wait-github.py" 2>/dev/null || true)
if [ -z "$legacy_refs" ]; then
  pass "Codex workflow assets contain no legacy bot-review or .github/agents references"
else
  fail "Codex workflow assets contain legacy references: $legacy_refs"
fi

stale_qa_refs=$(grep -RInE 'vbw-qa-investigator-gpt-54|gpt-5\.4|GPT-5\.4|cross-model QA' \
  "$ROOT/.agents" \
  "$ROOT/.codex" \
  "$ROOT/docs/vbw-agentic-workflow-presentation-source.md" 2>/dev/null || true)
if [ -z "$stale_qa_refs" ]; then
  pass "Codex QA workflow assets contain no stale cross-model QA references"
else
  fail "Codex QA workflow assets contain stale cross-model QA references: $stale_qa_refs"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All Codex agent asset contract checks passed."
