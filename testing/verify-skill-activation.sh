#!/usr/bin/env bash
set -euo pipefail

# verify-skill-activation.sh — Verify additive skill activation pipeline
#
# Checks:
# - vbw-dev.md references skills_used activation
# - vbw-lead.md references skill evaluation and wiring
# - orchestrator spawn contracts emit explicit activation OR explicit no-activation blocks
# - spawned-agent prompts treat orchestrator selection as a starting set, not a ceiling
# - command prompts select all materially helpful skills, including adjacent/domain skills
# - hooks.json does NOT contain skill-evaluation-gate.sh or skill-eval-prompt-gate.sh
# - All agents with explicit tools: allowlists include Skill
# - execute-protocol.md documents plan-driven approach

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

tracked_command_reference_files() {
  local rel
  git -C "$ROOT" ls-files -- 'commands/*.md' 'references/*.md' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

TRACKED_COMMAND_REFERENCE_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_COMMAND_REFERENCE_FILES+=("$file")
done < <(tracked_command_reference_files)

COMMAND_SKILL_CONTRACT_FILES=(
  "$ROOT/commands/vibe.md"
  "$ROOT/commands/research.md"
  "$ROOT/commands/map.md"
  "$ROOT/commands/fix.md"
  "$ROOT/commands/debug.md"
  "$ROOT/commands/qa.md"
  "$ROOT/references/execute-protocol.md"
)

AGENT_SKILL_CONTRACT_FILES=(
  "$ROOT/agents/vbw-lead.md"
  "$ROOT/agents/vbw-dev.md"
  "$ROOT/agents/vbw-qa.md"
  "$ROOT/agents/vbw-scout.md"
  "$ROOT/agents/vbw-debugger.md"
  "$ROOT/agents/vbw-architect.md"
  "$ROOT/agents/vbw-docs.md"
)

SKILL_FOLLOW_UP_SENTENCE=$(cat <<'EOF'
After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting — do not scan entire skill folders or read unrelated references.
EOF
)

SKILL_FOLLOW_UP_BLOCK_OPEN='<skill_follow_up_files>'

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

RUNTIME_HELPER_TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${RUNTIME_HELPER_TEST_ROOT:-}"' EXIT

write_runtime_skill_fixture() {
  local base_dir="$1"
  local skill_name="$2"
  local rel_name="$3"
  local body_text="$4"

  write_runtime_skill_fixture_with_body "$base_dir" "$skill_name" "$(cat <<EOF
Skill details: [${rel_name%.md}](references/${rel_name})
EOF
)" "references/$rel_name=$body_text"
}

write_runtime_skill_fixture_with_body() {
  local base_dir="$1"
  local skill_name="$2"
  local skill_body="$3"
  shift 3

  mkdir -p "$base_dir/$skill_name/references"
  printf '%s\n' "$skill_body" > "$base_dir/$skill_name/SKILL.md"

  while [ "$#" -gt 0 ]; do
    local fixture_spec="$1"
    shift

    case "$fixture_spec" in
      */)
        mkdir -p "$base_dir/$skill_name/$fixture_spec"
        continue
        ;;
    esac

    local rel_path="${fixture_spec%%=*}"
    local body_text="${fixture_spec#*=}"
    mkdir -p "$(dirname "$base_dir/$skill_name/$rel_path")"
    printf '%s\n' "$body_text" > "$base_dir/$skill_name/$rel_path"
  done
}

verify_runtime_skill_root_guard() {
  local temp_root="$RUNTIME_HELPER_TEST_ROOT"
  local project_dir="$temp_root/project"
  local home_dir="$temp_root/home"
  local helper="$ROOT/scripts/extract-skill-follow-up-files.sh"
  local global_project_dir="$temp_root/global-project"
  local outside_dir="$temp_root/outside"
  local traversal_project_output traversal_global_output mixed_output
  local confined_project_output confined_global_output no_links_output
  local project_symlink_output global_symlink_output

  rm -rf "$temp_root"
  mkdir -p "$project_dir/.claude/skills" "$global_project_dir" "$home_dir/.claude/skills" "$outside_dir"

  write_runtime_skill_fixture "$project_dir/.claude/skills" swiftdata local-good.md "Local good reference content"
  write_runtime_skill_fixture "$project_dir/.agents/skills" swiftdata agents-bad.md "Agents bad reference content"
  write_runtime_skill_fixture "$project_dir/.pi/skills" swiftdata pi-bad.md "Pi bad reference content"
  write_runtime_skill_fixture "$home_dir/.agents/skills" swiftdata home-agents-bad.md "Home agents bad reference content"

  write_runtime_skill_fixture_with_body "$project_dir/.claude/skills" confined-skill "$(cat <<'EOF'
Skill details: [safe](references/local-good.md)
Skill details: [normalized](docs/../references/normalized-good.md)
Skill details: [escape](../other-skill/references/secret.md)
EOF
)" \
    "references/local-good.md=Confined local reference" \
    "references/normalized-good.md=Normalized local reference" \
    "docs/" 
  write_runtime_skill_fixture "$project_dir/.claude/skills" other-skill secret.md "Project secret reference"

  write_runtime_skill_fixture_with_body "$home_dir/.claude/skills" global-skill "$(cat <<'EOF'
Skill details: [safe](references/global-good.md)
Skill details: [normalized](docs/../references/global-normalized.md)
Skill details: [escape](../other-skill/references/global-secret.md)
EOF
)" \
    "references/global-good.md=Global safe reference" \
    "references/global-normalized.md=Global normalized reference" \
    "docs/"
  write_runtime_skill_fixture "$home_dir/.claude/skills" other-skill global-secret.md "Global secret reference"

  write_runtime_skill_fixture_with_body "$project_dir/.claude/skills" no-links-skill "$(cat <<'EOF'
This skill has no markdown links.
EOF
)"

  write_runtime_skill_fixture_with_body "$project_dir/.claude/skills" symlink-skill "$(cat <<'EOF'
Skill details: [safe](references/local-good.md)
Skill details: [symlink](references/linked-outside.md)
EOF
)" \
    "references/local-good.md=Project symlink safe reference"
  printf '%s\n' 'Project symlink outside content' > "$outside_dir/project-secret.md"
  ln -s "$outside_dir/project-secret.md" "$project_dir/.claude/skills/symlink-skill/references/linked-outside.md"

  write_runtime_skill_fixture_with_body "$home_dir/.claude/skills" global-symlink-skill "$(cat <<'EOF'
Skill details: [safe](references/global-good.md)
Skill details: [symlink](references/linked-outside.md)
EOF
)" \
    "references/global-good.md=Global symlink safe reference"
  printf '%s\n' 'Global symlink outside content' > "$outside_dir/global-secret.md"
  ln -s "$outside_dir/global-secret.md" "$home_dir/.claude/skills/global-symlink-skill/references/linked-outside.md"

  traversal_project_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$project_dir" ../../.agents/skills/swiftdata ../../.pi/skills/swiftdata 2>/dev/null || true)
  if [ -z "$traversal_project_output" ]; then
    pass "scripts/extract-skill-follow-up-files.sh: rejects traversal into project lookalike roots at runtime"
  else
    fail "scripts/extract-skill-follow-up-files.sh: traversal into project lookalike roots still produces runtime output"
  fi

  traversal_global_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$project_dir" ../../.agents/skills/swiftdata 2>/dev/null || true)
  if [ -z "$traversal_global_output" ]; then
    pass "scripts/extract-skill-follow-up-files.sh: rejects traversal into HOME/.agents at runtime"
  else
    fail "scripts/extract-skill-follow-up-files.sh: traversal into HOME/.agents still produces runtime output"
  fi

  mixed_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$project_dir" "swiftdata ../../.agents/skills/swiftdata" 2>/dev/null || true)
  if [[ "$mixed_output" == *"$project_dir/.claude/skills/swiftdata/references/local-good.md"* ]]; then
    pass "scripts/extract-skill-follow-up-files.sh: preserves valid skills alongside invalid traversal tokens"
  else
    fail "scripts/extract-skill-follow-up-files.sh: mixed valid+invalid runtime input lost the valid skill"
  fi

  if [[ "$mixed_output" == *"agents-bad.md"* || "$mixed_output" == *"pi-bad.md"* || "$mixed_output" == *"home-agents-bad.md"* ]]; then
    fail "scripts/extract-skill-follow-up-files.sh: mixed valid+invalid runtime input still leaked a decoy root"
  else
    pass "scripts/extract-skill-follow-up-files.sh: mixed valid+invalid runtime input does not leak decoy roots"
  fi

  confined_project_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$project_dir" confined-skill 2>/dev/null || true)
  if [[ "$confined_project_output" == *"$project_dir/.claude/skills/confined-skill/references/local-good.md"* ]] \
    && [[ "$confined_project_output" == *"$project_dir/.claude/skills/confined-skill/references/normalized-good.md"* ]]; then
    pass "scripts/extract-skill-follow-up-files.sh: keeps normalized in-tree project follow-up links"
  else
    fail "scripts/extract-skill-follow-up-files.sh: lost a valid normalized in-tree project follow-up link"
  fi

  if [[ "$confined_project_output" == *"other-skill/references/secret.md"* ]]; then
    fail "scripts/extract-skill-follow-up-files.sh: project SKILL.md traversal escaped into a sibling skill"
  else
    pass "scripts/extract-skill-follow-up-files.sh: project SKILL.md traversal cannot escape into a sibling skill"
  fi

  confined_global_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$global_project_dir" global-skill 2>/dev/null || true)
  if [[ "$confined_global_output" == *"$home_dir/.claude/skills/global-skill/references/global-good.md"* ]] \
    && [[ "$confined_global_output" == *"$home_dir/.claude/skills/global-skill/references/global-normalized.md"* ]]; then
    pass "scripts/extract-skill-follow-up-files.sh: keeps normalized in-tree global follow-up links"
  else
    fail "scripts/extract-skill-follow-up-files.sh: lost a valid normalized in-tree global follow-up link"
  fi

  if [[ "$confined_global_output" == *"other-skill/references/global-secret.md"* ]]; then
    fail "scripts/extract-skill-follow-up-files.sh: global SKILL.md traversal escaped into a sibling skill"
  else
    pass "scripts/extract-skill-follow-up-files.sh: global SKILL.md traversal cannot escape into a sibling skill"
  fi

  no_links_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$project_dir" no-links-skill 2>/dev/null || true)
  if [ -z "$no_links_output" ]; then
    pass "scripts/extract-skill-follow-up-files.sh: skills with no markdown links exit cleanly with no output"
  else
    fail "scripts/extract-skill-follow-up-files.sh: no-link skills should emit no output"
  fi

  project_symlink_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$project_dir" symlink-skill 2>/dev/null || true)
  if [[ "$project_symlink_output" == *"symlink-skill/references/local-good.md"* ]]; then
    pass "scripts/extract-skill-follow-up-files.sh: project symlink fixture still emits safe in-tree files"
  else
    fail "scripts/extract-skill-follow-up-files.sh: project symlink fixture lost the safe in-tree file"
  fi

  if [[ "$project_symlink_output" == *"linked-outside.md"* ]]; then
    fail "scripts/extract-skill-follow-up-files.sh: project symlinked follow-up path escaped the active skill directory"
  else
    pass "scripts/extract-skill-follow-up-files.sh: project symlinked follow-up path is rejected"
  fi

  global_symlink_output=$(HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir/.claude" bash "$helper" --project-dir "$global_project_dir" global-symlink-skill 2>/dev/null || true)
  if [[ "$global_symlink_output" == *"global-symlink-skill/references/global-good.md"* ]]; then
    pass "scripts/extract-skill-follow-up-files.sh: global symlink fixture still emits safe in-tree files"
  else
    fail "scripts/extract-skill-follow-up-files.sh: global symlink fixture lost the safe in-tree file"
  fi

  if [[ "$global_symlink_output" == *"linked-outside.md"* ]]; then
    fail "scripts/extract-skill-follow-up-files.sh: global symlinked follow-up path escaped the active skill directory"
  else
    pass "scripts/extract-skill-follow-up-files.sh: global symlinked follow-up path is rejected"
  fi
}

expected_skill_contract_sites() {
  case "$(basename "$1")" in
    vibe.md) echo 10 ;;
    debug.md) echo 3 ;;
    qa.md) echo 2 ;;
    research.md|fix.md|execute-protocol.md) echo 1 ;;
    map.md) echo 2 ;;
    *) echo 0 ;;
  esac
}

collect_skill_contract_site_lines() {
  local file="$1"
  grep -nE 'evaluate installed skills visible in your system context|Skill activation for Dev/QA tasks' "$file" 2>/dev/null | cut -d: -f1 || true
}

extract_text_block_from_segment() {
  local file="$1"
  local start_line="$2"
  local end_line="$3"
  local wanted_block="$4"

  awk -v start="$start_line" -v end="$end_line" -v wanted="$wanted_block" '
    NR < start || NR > end { next }
    /^[[:space:]]*```text[[:space:]]*$/ { in_block=1; block_index++; next }
    in_block && /^[[:space:]]*```[[:space:]]*$/ {
      if (block_index == wanted) {
        exit
      }
      in_block=0
      next
    }
    in_block && block_index == wanted { print }
  ' "$file"
}

extract_execute_protocol_payload_block() {
  local file="$1"

  awk '
    /subject: "Execute \{NN-MM\}: \{plan-title\}"/ { in_example=1 }
    in_example && /^description: \|$/ { in_desc=1; next }
    in_desc && /^[^[:space:]]/ { exit }
    in_desc { print }
  ' "$file"
}

verify_payload_prefix_block() {
  local file_name="$1"
  local site_number="$2"
  local variant="$3"
  local block_content="$4"
  local open_tag="$5"
  local close_tag="$6"
  local close_line sentence_line follow_up_block_line

  if [ -n "$block_content" ] && grep -Fq "$open_tag" <<< "$block_content"; then
    pass "$file_name: site $site_number has payload-local $variant"
  else
    fail "$file_name: site $site_number missing payload-local $variant"
    return
  fi

  close_line=$(printf '%s\n' "$block_content" | awk -v tag="$close_tag" 'index($0, tag) { print NR; exit }')
  if [ -n "$close_line" ]; then
    sentence_line=$(printf '%s\n' "$block_content" | awk -v needle="$SKILL_FOLLOW_UP_SENTENCE" -v after="$close_line" 'NR > after && index($0, needle) { print NR; exit }')
  else
    sentence_line=""
  fi

  if [ -n "$close_line" ] && [ -n "$sentence_line" ] && [ "$sentence_line" -eq $((close_line + 1)) ]; then
    pass "$file_name: site $site_number places the follow-up sentence immediately after $variant"
  else
    fail "$file_name: site $site_number does not place the follow-up sentence immediately after $variant"
  fi

  if [ "$variant" = "activation payload block" ]; then
    follow_up_block_line=$(printf '%s\n' "$block_content" | awk -v needle="$SKILL_FOLLOW_UP_BLOCK_OPEN" -v after="$sentence_line" 'NR > after && index($0, needle) { print NR; exit }')
    if [ -n "$sentence_line" ] && [ -n "$follow_up_block_line" ] && [ "$follow_up_block_line" -eq $((sentence_line + 1)) ]; then
      pass "$file_name: site $site_number places the resolved follow-up file block immediately after the follow-up sentence"
    else
      fail "$file_name: site $site_number missing payload-local resolved follow-up file block"
    fi

    if grep -Fq 'extract-skill-follow-up-files.sh' <<< "$block_content"; then
      pass "$file_name: site $site_number activation payload names the follow-up file resolver"
    else
      fail "$file_name: site $site_number activation payload missing extract-skill-follow-up-files.sh guidance"
    fi
  fi
}

verify_payload_local_skill_contract_sites() {
  local file="$1"
  local file_name expected_count total_lines start_line end_line site_number
  local activation_block no_activation_block payload_block
  local site_lines=()

  file_name=$(basename "$file")
  expected_count=$(expected_skill_contract_sites "$file")
  total_lines=$(wc -l < "$file" | tr -d ' ')

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    site_lines+=("$line")
  done < <(collect_skill_contract_site_lines "$file")

  if [ "$file_name" = "execute-protocol.md" ]; then
    payload_block=$(extract_execute_protocol_payload_block "$file")
    verify_payload_prefix_block "$file_name" 1 "activation payload block" "$payload_block" '<skill_activation>' '</skill_activation>'
    verify_payload_prefix_block "$file_name" 1 "no-activation payload block" "$payload_block" '<skill_no_activation>' '</skill_no_activation>'
    return
  fi

  site_number=1
  while [ "$site_number" -le "$expected_count" ]; do
    start_line="${site_lines[$((site_number - 1))]}"
    if [ "$site_number" -lt "${#site_lines[@]}" ]; then
      end_line=$(( ${site_lines[$site_number]} - 1 ))
    else
      end_line="$total_lines"
    fi

    activation_block=$(extract_text_block_from_segment "$file" "$start_line" "$end_line" 1)
    no_activation_block=$(extract_text_block_from_segment "$file" "$start_line" "$end_line" 2)

    verify_payload_prefix_block "$file_name" "$site_number" "activation payload block" "$activation_block" '<skill_activation>' '</skill_activation>'
    verify_payload_prefix_block "$file_name" "$site_number" "no-activation payload block" "$no_activation_block" '<skill_no_activation>' '</skill_no_activation>'

    site_number=$((site_number + 1))
  done
}

is_uat_remediation_skill_site() {
  local file="$1"
  local start_line="$2"
  local uat_start uat_end

  [ "$(basename "$file")" = "vibe.md" ] || return 1

  uat_start=$(awk '/^### Mode: UAT Remediation[[:space:]]*$/ { print NR; exit }' "$file")
  uat_end=$(awk '/^### Mode: Milestone UAT Recovery[[:space:]]*$/ { print NR; exit }' "$file")

  [ -n "$uat_start" ] || return 1
  [ -n "$uat_end" ] || return 1
  [ "$start_line" -gt "$uat_start" ] && [ "$start_line" -lt "$uat_end" ]
}

verify_skill_contract_sites() {
  local file="$1"
  local file_name expected_count total_lines start_line end_line site_number
  local segment
  local site_lines=()

  file_name=$(basename "$file")
  expected_count=$(expected_skill_contract_sites "$file")
  total_lines=$(wc -l < "$file" | tr -d ' ')

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    site_lines+=("$line")
  done < <(collect_skill_contract_site_lines "$file")

  if [ "${#site_lines[@]}" -eq "$expected_count" ]; then
    pass "$file_name: found $expected_count explicit skill-evaluation site(s)"
  else
    fail "$file_name: expected $expected_count explicit skill-evaluation site(s), found ${#site_lines[@]}"
  fi

  site_number=1
  while [ "$site_number" -le "${#site_lines[@]}" ]; do
    start_line="${site_lines[$((site_number - 1))]}"
    if [ "$site_number" -lt "${#site_lines[@]}" ]; then
      end_line=$(( ${site_lines[$site_number]} - 1 ))
    else
      end_line="$total_lines"
    fi
    segment=$(sed -n "${start_line},${end_line}p" "$file")

    if grep -q '<skill_activation>' <<< "$segment" \
      && grep -q 'Call Skill(' <<< "$segment"; then
      pass "$file_name: site $site_number has local activation path"
    else
      fail "$file_name: site $site_number missing local activation path"
    fi

    if grep -q '<skill_no_activation>' <<< "$segment" \
      && grep -q 'No skills were preselected at orchestration time\. Reason:' <<< "$segment"; then
      pass "$file_name: site $site_number has local no-activation path"
    else
      fail "$file_name: site $site_number missing local no-activation path"
    fi

    if grep -q 'exactly one explicit' <<< "$segment"; then
      pass "$file_name: site $site_number states explicit one-of-two outcome contract"
    else
      fail "$file_name: site $site_number missing explicit one-of-two outcome wording"
    fi

    if grep -q 'omit the skill_activation block entirely\|omit the block entirely' <<< "$segment"; then
      fail "$file_name: site $site_number still allows silent omission"
    else
      pass "$file_name: site $site_number rejects silent omission"
    fi

    if grep -q 'state the skill outcome in your response\|states the skill evaluation outcome' <<< "$segment"; then
      pass "$file_name: site $site_number has visible-reporting instruction"
    else
      fail "$file_name: site $site_number missing visible-reporting instruction"
    fi

    if is_uat_remediation_skill_site "$file" "$start_line"; then
      if grep -q 'select only skills directly needed\|select the task-specific skills listed in the remediation plan' <<< "$segment"; then
        pass "$file_name: site $site_number uses UAT-scoped skill-selection wording"
      else
        fail "$file_name: site $site_number missing UAT-scoped skill-selection wording"
      fi
    elif grep -q 'materially helpful' <<< "$segment" \
      && grep -q 'single most direct skill' <<< "$segment"; then
      pass "$file_name: site $site_number uses additive-selection wording"
    else
      fail "$file_name: site $site_number missing additive-selection wording"
    fi

    if is_uat_remediation_skill_site "$file" "$start_line"; then
      pass "$file_name: site $site_number does not require adjacent-skill example for UAT remediation"
    elif grep -qi 'swiftdata' <<< "$segment"; then
      pass "$file_name: site $site_number includes the SwiftData-style adjacent-skill example"
    else
      fail "$file_name: site $site_number missing the SwiftData-style adjacent-skill example"
    fi

    if grep -q 'Only include skills whose description matches\|No installed skills apply' <<< "$segment"; then
      fail "$file_name: site $site_number still contains old narrowing/no-rescan wording"
    else
      pass "$file_name: site $site_number removed old narrowing/no-rescan wording"
    fi

    if grep -q 'do not scan entire skill folders or read unrelated references\|not entire skill folders or unrelated references' <<< "$segment"; then
      pass "$file_name: site $site_number has skill follow-up read nudge"
    else
      fail "$file_name: site $site_number missing skill follow-up read nudge"
    fi

    site_number=$((site_number + 1))
  done
}

echo "=== Skill Activation Pipeline Verification (plan-driven model) ==="

# --- vbw-dev.md checks ---

DEV_AGENT="$ROOT/agents/vbw-dev.md"
FIX_COMMAND="$ROOT/commands/fix.md"
VIBE_COMMAND="$ROOT/commands/vibe.md"
EXECUTE_PROTOCOL="$ROOT/references/execute-protocol.md"
DEV_TOOLS=$(sed -n '/^---$/,/^---$/p' "$DEV_AGENT" | grep '^tools:' || true)
DEV_DISALLOWED=$(sed -n '/^---$/,/^---$/p' "$DEV_AGENT" | grep '^disallowedTools:' || true)
DEV_MEMORY=$(sed -n '/^---$/,/^---$/p' "$DEV_AGENT" | grep '^memory:' || true)

dev_tools_has() {
  local target="$1"
  printf '%s' "$DEV_TOOLS" | sed 's/^tools:[[:space:]]*//' | awk -v RS=',' -v target="$target" '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 == target) found=1
    }
    END { exit(found ? 0 : 1) }
  '
}

if [ -n "$DEV_TOOLS" ]; then
  pass "vbw-dev.md: uses explicit tools allowlist"
else
  fail "vbw-dev.md: missing explicit tools allowlist"
fi

if [ -z "$DEV_DISALLOWED" ]; then
  pass "vbw-dev.md: no longer relies on disallowedTools inheritance"
else
  fail "vbw-dev.md: still relies on disallowedTools inheritance"
fi

if [ "$DEV_MEMORY" = "memory: project" ]; then
  pass "vbw-dev.md: preserves project memory"
else
  fail "vbw-dev.md: memory must remain project (found: ${DEV_MEMORY:-missing})"
fi

for required_dev_tool in Read Glob Grep Write Edit Bash WebFetch WebSearch LSP Skill SendMessage TaskGet; do
  if dev_tools_has "$required_dev_tool"; then
    pass "vbw-dev.md: explicit tools include $required_dev_tool"
  else
    fail "vbw-dev.md: explicit tools missing $required_dev_tool"
  fi
done

for forbidden_dev_tool in Task TaskCreate Agent TeamCreate TeamDelete AskUserQuestion; do
  if dev_tools_has "$forbidden_dev_tool"; then
    fail "vbw-dev.md: explicit tools expose forbidden $forbidden_dev_tool"
  else
    pass "vbw-dev.md: explicit tools omit forbidden $forbidden_dev_tool"
  fi
done

if grep -q 'Your frontmatter tool allowlist intentionally omits recursive delegation' "$DEV_AGENT" \
  && grep -q 'Use the listed implementation tools directly' "$DEV_AGENT"; then
  pass "vbw-dev.md: prompt explains explicit no-subagent tool boundary"
else
  fail "vbw-dev.md: missing explicit no-subagent tool-boundary guidance"
fi

if grep -q 'SendMessage' "$DEV_AGENT" && dev_tools_has SendMessage; then
  pass "vbw-dev.md: SendMessage guidance matches explicit tool availability"
else
  fail "vbw-dev.md: SendMessage guidance/tool availability mismatch"
fi

if grep -q 'TaskGet' "$DEV_AGENT" && dev_tools_has TaskGet; then
  pass "vbw-dev.md: TaskGet guidance matches explicit tool availability"
else
  fail "vbw-dev.md: TaskGet guidance/tool availability mismatch"
fi

if grep -q '## MCP-Derived Context' "$DEV_AGENT" \
  && grep -q 'explicit `tools:` allowlist' "$DEV_AGENT" \
  && grep -q 'Assume dynamic MCP server tools are unavailable' "$DEV_AGENT" \
  && grep -q 'MCP-derived facts, docs, command results, or paths' "$DEV_AGENT"; then
  pass "vbw-dev.md: MCP guidance matches explicit allowlist boundary"
else
  fail "vbw-dev.md: MCP guidance does not match explicit allowlist boundary"
fi

if grep -q 'When available MCP tools provide capabilities' "$DEV_AGENT" || grep -q 'use MCP tools' "$DEV_AGENT"; then
  fail "vbw-dev.md: stale direct MCP-use guidance remains"
else
  pass "vbw-dev.md: no stale direct MCP-use guidance"
fi

if grep -q 'pre-extract concise task-relevant facts, docs, command results, or paths for Dev' "$FIX_COMMAND" \
  && grep -q 'do not instruct `vbw-dev` to call MCP servers directly' "$FIX_COMMAND"; then
  pass "fix.md: Dev MCP guidance uses parent-side pre-extraction"
else
  fail "fix.md: Dev MCP guidance still assumes inherited MCP access"
fi

if [ "$(grep -c 'do not instruct `vbw-dev` to call MCP servers directly' "$VIBE_COMMAND")" -ge 2 ] \
  && grep -q 'Do not plan for Dev agents to call MCP servers directly' "$VIBE_COMMAND"; then
  pass "vibe.md: Dev MCP guidance uses parent-side pre-extraction"
else
  fail "vibe.md: Dev MCP guidance still assumes inherited MCP access"
fi

if grep -q 'pre-extract concise task-relevant facts, docs, command results, or paths for Dev' "$EXECUTE_PROTOCOL" \
  && grep -q 'do not instruct `vbw-dev` to call MCP servers directly' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol.md: Dev MCP guidance uses parent-side pre-extraction"
else
  fail "execute-protocol.md: Dev MCP guidance still assumes inherited MCP access"
fi

if grep -q 'note them in the Dev task description' "$FIX_COMMAND" \
  || grep -q "note them in the Dev's task context" "$VIBE_COMMAND" \
  || grep -q 'so the Dev agent knows which MCP tools to use' "$EXECUTE_PROTOCOL"; then
  fail "Dev spawn docs: stale inherited MCP instruction remains"
else
  pass "Dev spawn docs: no stale inherited MCP instruction remains"
fi

if grep -q 'skills_used' "$DEV_AGENT"; then
  pass "vbw-dev.md: references skills_used frontmatter"
else
  fail "vbw-dev.md: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$DEV_AGENT"; then
  pass "vbw-dev.md: references Skill() activation"
else
  fail "vbw-dev.md: missing Skill() reference"
fi

if ! grep -q 'protocol violation' "$DEV_AGENT"; then
  pass "vbw-dev.md: no enforcement language"
else
  fail "vbw-dev.md: still has 'protocol violation' enforcement language"
fi

if grep -q 'skill_activation' "$DEV_AGENT" && grep -q 'skill_no_activation' "$DEV_AGENT"; then
  pass "vbw-dev.md: has orchestrator-aware conditional in deeper protocol"
else
  fail "vbw-dev.md: missing orchestrator-aware conditional (must reference both skill_activation and skill_no_activation)"
fi

# --- vbw-lead.md checks ---

LEAD_AGENT="$ROOT/agents/vbw-lead.md"
LEAD_TOOLS=$(sed -n '/^---$/,/^---$/p' "$LEAD_AGENT" | grep '^tools:' || true)

if grep -q 'Skill' <<< "$LEAD_TOOLS"; then
  pass "vbw-lead.md: Skill in tools allowlist"
else
  fail "vbw-lead.md: Skill NOT in tools allowlist"
fi

if grep -q 'Wire relevant skills into plans' "$LEAD_AGENT"; then
  pass "vbw-lead.md: emphasizes wiring skills into plans"
else
  fail "vbw-lead.md: missing plan wiring language"
fi

if grep -q 'Skill completeness check' "$LEAD_AGENT"; then
  pass "vbw-lead.md: has skill completeness gate in self-review"
else
  fail "vbw-lead.md: missing skill completeness gate in self-review"
fi

if grep -q 'skill_no_activation' "$LEAD_AGENT"; then
  pass "vbw-lead.md: recognizes explicit no-activation block"
else
  fail "vbw-lead.md: missing explicit no-activation handling"
fi

if ! grep -q 'write YES or NO' "$LEAD_AGENT"; then
  pass "vbw-lead.md: no written YES/NO evaluation"
else
  fail "vbw-lead.md: still has written YES/NO evaluation"
fi

# --- hooks.json negative checks (enforcement gates removed) ---

HOOKS_FILE="$ROOT/hooks/hooks.json"

if ! grep -q 'skill-evaluation-gate.sh' "$HOOKS_FILE"; then
  pass "hooks.json: skill-evaluation-gate.sh removed"
else
  fail "hooks.json: skill-evaluation-gate.sh still present"
fi

if ! grep -q 'skill-eval-prompt-gate.sh' "$HOOKS_FILE"; then
  pass "hooks.json: skill-eval-prompt-gate.sh removed"
else
  fail "hooks.json: skill-eval-prompt-gate.sh still present"
fi

# --- hooks.json positive check (skill-hook-dispatch.sh preserved) ---

if grep -q 'skill-hook-dispatch.sh' "$HOOKS_FILE"; then
  pass "hooks.json: skill-hook-dispatch.sh preserved (runtime skill hooks)"
else
  fail "hooks.json: skill-hook-dispatch.sh missing (should be preserved)"
fi

# --- Skill in all agent tools: allowlists (or inherited via disallowedTools pattern) ---

for agent_file in vbw-qa.md vbw-scout.md vbw-debugger.md vbw-architect.md vbw-docs.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  AGENT_TOOLS=$(sed -n '/^---$/,/^---$/p' "$AGENT_PATH" | grep '^tools:' || true)
  AGENT_DISALLOWED=$(sed -n '/^---$/,/^---$/p' "$AGENT_PATH" | grep '^disallowedTools:' || true)
  if [ -n "$AGENT_TOOLS" ]; then
    # Agent uses tools: allowlist — Skill must be explicitly listed
    if grep -q 'Skill' <<< "$AGENT_TOOLS"; then
      pass "$agent_file: Skill in tools allowlist"
    else
      fail "$agent_file: Skill NOT in tools allowlist"
    fi
  elif [ -n "$AGENT_DISALLOWED" ]; then
    # Agent uses disallowedTools: denylist — Skill is inherited from parent
    if grep -q 'Skill' <<< "$AGENT_DISALLOWED"; then
      fail "$agent_file: Skill is in disallowedTools (should be inherited)"
    else
      pass "$agent_file: Skill inherited via disallowedTools pattern (not denied)"
    fi
  else
    fail "$agent_file: Neither tools: nor disallowedTools: found in frontmatter"
  fi
done

# --- Negative check: compile-context.sh no longer has emit_skill_directive ---

COMPILER="$ROOT/scripts/compile-context.sh"

if grep -q 'emit_skill_directive' "$COMPILER"; then
  fail "compile-context.sh: still has emit_skill_directive (should be removed)"
else
  pass "compile-context.sh: emit_skill_directive removed"
fi

# --- execute-protocol.md checks ---

PROTOCOL="$ROOT/references/execute-protocol.md"

if grep -q 'plan-driven' "$PROTOCOL"; then
  pass "execute-protocol.md: documents plan-driven architecture"
else
  fail "execute-protocol.md: missing plan-driven documentation"
fi

if grep -q 'skills_used' "$PROTOCOL"; then
  pass "execute-protocol.md: references skills_used frontmatter"
else
  fail "execute-protocol.md: missing skills_used reference"
fi

if grep -q 'skill-hook-dispatch.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: documents runtime skill hooks (separate concern)"
else
  fail "execute-protocol.md: missing skill-hook-dispatch.sh documentation"
fi

if grep -q 'skill_no_activation' "$PROTOCOL"; then
  pass "execute-protocol.md: documents explicit no-activation outcome"
else
  fail "execute-protocol.md: missing explicit no-activation outcome"
fi

if ! grep -q 'No written YES/NO evaluation required' "$PROTOCOL"; then
  pass "execute-protocol.md: legacy silent-decision wording removed"
else
  fail "execute-protocol.md: still says no written YES/NO evaluation is required"
fi

if ! grep -q 'three-layer' "$PROTOCOL"; then
  pass "execute-protocol.md: old three-layer documentation removed"
else
  fail "execute-protocol.md: still has three-layer documentation"
fi

if grep -q 'states the skill evaluation outcome' "$PROTOCOL"; then
  pass "execute-protocol.md: documents visible skill reporting contract"
else
  fail "execute-protocol.md: missing visible skill reporting documentation"
fi

# --- Agent activation instruction checks ---

QA_AGENT="$ROOT/agents/vbw-qa.md"

if grep -q 'skills_used' "$QA_AGENT"; then
  pass "vbw-qa.md: references skills_used for plan-driven activation"
else
  fail "vbw-qa.md: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$QA_AGENT"; then
  pass "vbw-qa.md: references Skill() activation"
else
  fail "vbw-qa.md: missing Skill() reference"
fi

if grep -q 'skill_no_activation' "$QA_AGENT"; then
  pass "vbw-qa.md: recognizes explicit no-activation block"
else
  fail "vbw-qa.md: missing explicit no-activation handling"
fi

if grep -q 'available_skills' "$QA_AGENT"; then
  pass "vbw-qa.md: references available_skills for ad-hoc fallback"
else
  fail "vbw-qa.md: missing available_skills reference for ad-hoc fallback"
fi

SCOUT_AGENT="$ROOT/agents/vbw-scout.md"

if grep -q 'skills_used' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: references skills_used for plan-driven path"
else
  fail "vbw-scout.md: missing skills_used reference"
fi

if grep -q 'available_skills' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: references available_skills for ad-hoc path"
else
  fail "vbw-scout.md: missing available_skills reference for ad-hoc path"
fi

if grep -q 'skill_no_activation' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: recognizes explicit no-activation block"
else
  fail "vbw-scout.md: missing explicit no-activation handling"
fi

if ! grep -q 'may still honor' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: no permissive may-still-honor wording on no-activation path"
else
  fail "vbw-scout.md: still uses permissive may-still-honor wording on no-activation path"
fi

if grep -Eq 'still honor( its| any)? `skills_used` frontmatter' "$SCOUT_AGENT"; then
  pass "vbw-scout.md: preserves plan-driven skills_used behavior on no-activation path"
else
  fail "vbw-scout.md: missing mandatory skills_used preservation on no-activation path"
fi

DEBUGGER_AGENT="$ROOT/agents/vbw-debugger.md"

if grep -q 'available_skills' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: references available_skills for ad-hoc activation"
else
  fail "vbw-debugger.md: missing available_skills reference"
fi

if grep -q 'bounded completeness pass' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: includes bounded additive completeness pass"
else
  fail "vbw-debugger.md: missing bounded additive completeness pass"
fi

if grep -q 'skill_no_activation' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: recognizes explicit no-activation block"
else
  fail "vbw-debugger.md: missing explicit no-activation handling"
fi

if grep -q 'starting set, not a ceiling' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: treats orchestrator selection as a starting set"
else
  fail "vbw-debugger.md: missing starting-set additive wording"
fi

ARCHITECT_AGENT="$ROOT/agents/vbw-architect.md"

if grep -q 'available_skills' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: references available_skills for ad-hoc activation"
else
  fail "vbw-architect.md: missing available_skills reference"
fi

if grep -q 'bounded completeness pass' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: includes bounded additive completeness pass"
else
  fail "vbw-architect.md: missing bounded additive completeness pass"
fi

if grep -q 'skill_no_activation' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: recognizes explicit no-activation block"
else
  fail "vbw-architect.md: missing explicit no-activation handling"
fi

if grep -q 'starting set, not a ceiling' "$ARCHITECT_AGENT"; then
  pass "vbw-architect.md: treats orchestrator selection as a starting set"
else
  fail "vbw-architect.md: missing starting-set additive wording"
fi

DOCS_AGENT="$ROOT/agents/vbw-docs.md"

if grep -q 'skills_used' "$DOCS_AGENT"; then
  pass "vbw-docs.md: references skills_used for plan-driven activation"
else
  fail "vbw-docs.md: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$DOCS_AGENT"; then
  pass "vbw-docs.md: references Skill() activation"
else
  fail "vbw-docs.md: missing Skill() reference"
fi

if grep -q 'skill_no_activation' "$DOCS_AGENT"; then
  pass "vbw-docs.md: recognizes explicit no-activation block"
else
  fail "vbw-docs.md: missing explicit no-activation handling"
fi

if grep -q 'available_skills' "$DOCS_AGENT"; then
  pass "vbw-docs.md: references available_skills for ad-hoc fallback"
else
  fail "vbw-docs.md: missing available_skills reference for ad-hoc fallback"
fi

# Dev ad-hoc fallback check
if grep -q 'available_skills' "$DEV_AGENT"; then
  pass "vbw-dev.md: references available_skills for ad-hoc fallback"
else
  fail "vbw-dev.md: missing available_skills reference for ad-hoc fallback"
fi

# Protocol updated role coverage checks
if grep -q 'Dev/QA/Scout/Docs' "$PROTOCOL"; then
  pass "execute-protocol.md: documents all execution-time agents (Dev/QA/Scout/Docs)"
else
  fail "execute-protocol.md: missing updated agent coverage"
fi

if grep -q 'Debugger/Dev/Scout' "$PROTOCOL"; then
  pass "execute-protocol.md: names Debugger explicitly in ad-hoc paths"
else
  fail "execute-protocol.md: ad-hoc paths missing Debugger"
fi

if grep -q 'vbw:debug' "$PROTOCOL"; then
  pass "execute-protocol.md: documents /vbw:debug ad-hoc path"
else
  fail "execute-protocol.md: missing /vbw:debug documentation"
fi

# --- Skill-hook dispatch field name checks ---

DISPATCHER="$ROOT/scripts/skill-hook-dispatch.sh"

if grep -q '\.tools // \..*\.matcher' "$DISPATCHER"; then
  pass "skill-hook-dispatch.sh: reads both tools and matcher (backward compat)"
else
  fail "skill-hook-dispatch.sh: missing backward compat for matcher field"
fi

CONFIG_CMD="$ROOT/commands/config.md"

if grep -q 'skill_hook <skill> <event> <tools>' "$CONFIG_CMD"; then
  pass "config.md: skill_hook signature uses tools (not matcher)"
else
  fail "config.md: skill_hook signature still uses matcher"
fi

if grep -q '"tools": "Write|Edit"' "$CONFIG_CMD"; then
  pass "config.md: example JSON uses tools field"
else
  fail "config.md: example JSON still uses matcher field"
fi

# --- Deleted scripts should not exist ---

if [ ! -f "$ROOT/scripts/skill-eval-prompt-gate.sh" ]; then
  pass "skill-eval-prompt-gate.sh: deleted"
else
  fail "skill-eval-prompt-gate.sh: still exists"
fi

if [ ! -f "$ROOT/scripts/skill-evaluation-gate.sh" ]; then
  pass "skill-evaluation-gate.sh: deleted"
else
  fail "skill-evaluation-gate.sh: still exists"
fi

# --- emit-skill-xml.sh deleted (skill visibility is native to Claude Code) ---

if [ ! -f "$ROOT/scripts/emit-skill-xml.sh" ]; then
  pass "emit-skill-xml.sh: deleted (native CC skill visibility)"
else
  fail "emit-skill-xml.sh: still exists (should be deleted)"
fi

# --- inject-subagent-skills.sh removed (skill visibility is native to Claude Code) ---

if [ ! -f "$ROOT/scripts/inject-subagent-skills.sh" ]; then
  pass "inject-subagent-skills.sh: deleted (additionalContext injection removed)"
else
  fail "inject-subagent-skills.sh: still exists (should be deleted)"
fi

if ! grep -q 'inject-subagent-skills.sh' "$HOOKS_FILE"; then
  pass "hooks.json: inject-subagent-skills.sh removed from SubagentStart"
else
  fail "hooks.json: inject-subagent-skills.sh still present in SubagentStart"
fi

# --- session-start.sh no longer injects skill names (native CC skill visibility) ---

if ! grep -q 'emit-skill-xml.sh' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: no longer calls emit-skill-xml.sh (additionalContext injection removed)"
else
  fail "session-start.sh: still calls emit-skill-xml.sh (should be removed)"
fi

if ! grep -q 'Installed skills:' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: no longer injects skill names into additionalContext"
else
  fail "session-start.sh: still injects skill names into additionalContext"
fi

# --- session-start.sh has GSD co-installation warning ---

if grep -q 'GSD_WARNING' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: has GSD co-installation warning"
else
  fail "session-start.sh: missing GSD co-installation warning"
fi

if grep -q 'gsd:\*' "$ROOT/scripts/session-start.sh" || grep -q '/gsd:' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: GSD warning references /gsd:* commands"
else
  fail "session-start.sh: GSD warning missing /gsd:* reference"
fi

# --- Agent YAML: no maxTurns in frontmatter ---

for agent_file in vbw-dev.md vbw-qa.md vbw-docs.md vbw-lead.md vbw-scout.md vbw-architect.md vbw-debugger.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$AGENT_PATH")
  if grep -q '^maxTurns:' <<< "$FRONTMATTER"; then
    fail "$agent_file: maxTurns still in YAML frontmatter (should be removed)"
  else
    pass "$agent_file: no maxTurns in YAML frontmatter"
  fi
done

# --- session-start.sh no longer calls emit-skill-xml.sh ---

if ! grep -q 'emit-skill-xml.sh' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: emit-skill-xml.sh call removed"
else
  fail "session-start.sh: still calls emit-skill-xml.sh (should be removed)"
fi

# --- All 7 agents reference <available_skills> ---

for agent_file in vbw-dev.md vbw-qa.md vbw-docs.md vbw-lead.md vbw-scout.md vbw-architect.md vbw-debugger.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  if grep -q 'available_skills' "$AGENT_PATH"; then
    pass "$agent_file: references <available_skills>"
  else
    fail "$agent_file: missing <available_skills> reference"
  fi
done

echo ""
echo "=== Additive Agent Skill Model ==="

for agent_file in vbw-dev.md vbw-qa.md vbw-docs.md vbw-lead.md vbw-scout.md vbw-architect.md vbw-debugger.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"

  if grep -q 'starting set, not a ceiling' "$AGENT_PATH"; then
    pass "$agent_file: treats orchestrator selection as a starting set"
  else
    fail "$agent_file: missing starting-set additive wording"
  fi

  if grep -q 'bounded completeness pass' "$AGENT_PATH"; then
    pass "$agent_file: includes bounded completeness pass"
  else
    fail "$agent_file: missing bounded completeness pass"
  fi

  if grep -q 'no skills were preselected for this spawned task' "$AGENT_PATH"; then
    pass "$agent_file: no-activation block is treated as no initial preselection"
  else
    fail "$agent_file: no-activation path still reads like a hard ban"
  fi

  if grep -Eq 'Do not additionally scan `<available_skills>`|Do not scan `<available_skills>`|do not rescan `<available_skills>`' "$AGENT_PATH"; then
    fail "$agent_file: still contains old no-rescan ceiling wording"
  else
    pass "$agent_file: old no-rescan ceiling wording removed"
  fi
done

echo ""
echo "=== Adjacent Skill Example Coverage ==="

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -qi 'swiftdata' "$contract_file"; then
    pass "$contract_name: includes adjacent-skill example"
  else
    fail "$contract_name: missing adjacent-skill example"
  fi
done

README_FILE="$ROOT/README.md"
if grep -q 'Additive runtime activation' "$README_FILE" \
  && grep -q 'visible `Skills:` line' "$README_FILE"; then
  pass "README.md: documents additive spawned-agent skill activation"
else
  fail "README.md: missing additive spawned-agent skill activation note"
fi

# --- execute-protocol.md no longer documents emit-skill-xml.sh ---

if ! grep -q 'emit-skill-xml.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: emit-skill-xml.sh references removed"
else
  fail "execute-protocol.md: still references emit-skill-xml.sh (should be removed)"
fi

if grep -q 'available_skills' "$PROTOCOL"; then
  pass "execute-protocol.md: references skills awareness"
else
  fail "execute-protocol.md: missing skills awareness reference"
fi

# --- Functional test: inject-subagent-skills.sh removed ---

# inject-subagent-skills.sh has been deleted; skill visibility is native to Claude Code.
# The functional tests for that script are no longer applicable.

# --- normalize_agent_role consistency: agent-start.sh role coverage ---

_AGENT_START="$ROOT/scripts/agent-start.sh"

# Extract role patterns from agent-start.sh
_ROLES_AGENT_START=$(sed -n '/normalize_agent_role/,/^}/p' "$_AGENT_START" | grep "printf '" | sed "s/.*printf '\\([^']*\\)'.*/\\1/" | sort)

# Verify all 7 roles are present in agent-start.sh
for _role in architect debugger dev docs lead qa scout; do
  if grep -q "^${_role}$" <<< "$_ROLES_AGENT_START"; then
    pass "agent-start.sh: normalize handles '$_role' role"
  else
    fail "agent-start.sh: normalize missing '$_role' role"
  fi
done

# --- maxTurns conditional omission: all commands that spawn agents ---

# Every command that references maxTurns: ${...} must also have "omit" or "do NOT include"
_MAX_TURNS_COMMANDS=$(grep -l 'maxTurns.*\${' "${TRACKED_COMMAND_REFERENCE_FILES[@]}" 2>/dev/null || true)
_MT_FAIL=0
for _cmd_file in $_MAX_TURNS_COMMANDS; do
  _cmd_name=$(basename "$_cmd_file")
  if grep -q 'omit\|do NOT include maxTurns' "$_cmd_file"; then
    pass "$_cmd_name: maxTurns has conditional omission logic"
  else
    fail "$_cmd_name: maxTurns passed unconditionally (missing zero check)"
    _MT_FAIL=1
  fi
done
if [ -z "$_MAX_TURNS_COMMANDS" ]; then
  pass "maxTurns: no commands reference maxTurns (nothing to check)"
fi

# --- 3-Layer skill activation pipeline checks ---

echo ""
echo "=== 3-Layer Skill Activation Pipeline ==="

echo ""
echo "=== Explicit Skill Outcome Contract ==="

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -q 'skill_no_activation' "$contract_file"; then
    pass "$contract_name: contains explicit no-activation outcome"
  else
    fail "$contract_name: missing explicit no-activation outcome"
  fi
done

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  verify_skill_contract_sites "$contract_file"
done

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  verify_payload_local_skill_contract_sites "$contract_file"
done

for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if grep -q 'skill_no_activation' "$agent_file"; then
    pass "$agent_name: handles explicit no-activation outcome"
  else
    fail "$agent_name: missing explicit no-activation handling"
  fi
done

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -q 'omit the skill_activation block entirely\|omit the block entirely' "$contract_file"; then
    fail "$contract_name: still allows silent omission of skill outcome blocks"
  else
    pass "$contract_name: bans silent omission wording"
  fi
done

if ! grep -q 'Same as Add Phase step 5' "$ROOT/commands/vibe.md"; then
  pass "vibe.md: insert-phase Scout contract is local, not shorthand"
else
  fail "vibe.md: insert-phase Scout contract still relies on Add Phase shorthand"
fi

# Layer 1: All 7 agents have conditional skill activation section
for agent_file in vbw-lead.md vbw-dev.md vbw-qa.md vbw-scout.md vbw-debugger.md vbw-architect.md vbw-docs.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  if grep -q '## Skill Activation' "$AGENT_PATH"; then
    pass "$agent_file: has ## Skill Activation section"
  else
    fail "$agent_file: missing ## Skill Activation section"
  fi
done

# Layer 1b: Agents using disallowedTools (denylist) must have MCP Tool Usage section
# Agents with disallowedTools inherit MCP tools from the parent session, so they need
# guidance on when/how to use them. Agents with tools allowlist block MCP inheritance.
echo ""
echo "=== MCP Tool Usage Section (disallowedTools agents) ==="
for agent_file in "$ROOT"/agents/vbw-*.md; do
  agent_name=$(basename "$agent_file")
  if grep -q '^disallowedTools:' "$agent_file"; then
    if grep -q '## MCP Tool Usage' "$agent_file"; then
      pass "$agent_name: has ## MCP Tool Usage section (uses disallowedTools denylist)"
    else
      fail "$agent_name: missing ## MCP Tool Usage section (uses disallowedTools but no MCP guidance)"
    fi
  fi
done

# Layer 2: Script-driven skill activation removed (replaced by orchestrator-composed intelligent selection)
if [ ! -f "$ROOT/scripts/generate-skill-activation.sh" ]; then
  pass "generate-skill-activation.sh: deleted (replaced by intelligent orchestrator selection)"
else
  fail "generate-skill-activation.sh: still exists (should be deleted)"
fi

# compile-context.sh should NOT call generate-skill-activation.sh or emit_skills_section
if ! grep -q 'generate-skill-activation.sh' "$COMPILER"; then
  pass "compile-context.sh: no longer calls generate-skill-activation.sh"
else
  fail "compile-context.sh: still calls generate-skill-activation.sh (should be removed)"
fi

if ! grep -q 'emit_skills_section' "$COMPILER"; then
  pass "compile-context.sh: emit_skills_section removed"
else
  fail "compile-context.sh: still has emit_skills_section (should be removed)"
fi

if ! grep -q 'Mandatory Skill Activation' "$COMPILER"; then
  pass "compile-context.sh: Mandatory Skill Activation section removed"
else
  fail "compile-context.sh: still has Mandatory Skill Activation (should be removed)"
fi

# execute-protocol.md should NOT reference .skill-activation-block.txt or SKILL_BLOCK
if ! grep -q 'skill-activation-block.txt' "$PROTOCOL"; then
  pass "execute-protocol.md: .skill-activation-block.txt references removed"
else
  fail "execute-protocol.md: still references .skill-activation-block.txt"
fi

if [ ! -f "$ROOT/scripts/emit-skill-prompt-line.sh" ]; then
  pass "emit-skill-prompt-line.sh: deleted (replaced by generate-skill-activation.sh)"
else
  fail "emit-skill-prompt-line.sh: still exists (should be deleted)"
fi

# Negative: SKILL_PROMPT_LINE should NOT appear in any command/reference
VIBE_CMD="$ROOT/commands/vibe.md"
RESEARCH_CMD="$ROOT/commands/research.md"
if ! grep -q 'SKILL_PROMPT_LINE' "$PROTOCOL"; then
  pass "execute-protocol.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "execute-protocol.md: still references SKILL_PROMPT_LINE"
fi

if ! grep -q 'SKILL_PROMPT_LINE' "$VIBE_CMD"; then
  pass "vibe.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "vibe.md: still references SKILL_PROMPT_LINE"
fi

if ! grep -q 'SKILL_PROMPT_LINE' "$RESEARCH_CMD"; then
  pass "research.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "research.md: still references SKILL_PROMPT_LINE"
fi

# Positive: orchestrator-composed intelligent skill selection in execute-protocol
if grep -q 'evaluate installed skills' "$PROTOCOL"; then
  pass "execute-protocol.md: intelligent skill selection documented"
else
  fail "execute-protocol.md: missing intelligent skill selection documentation"
fi

# Negative: old LLM-composed skill selection removed from execute-protocol
if ! grep -q 'select skills from installed skills visible in your system context' "$PROTOCOL"; then
  pass "execute-protocol.md: old LLM-composed skill selection removed"
else
  fail "execute-protocol.md: still has old LLM-composed skill selection instruction"
fi

# Negative: SKILL_BLOCK variable removed from execute-protocol
if ! grep -q 'SKILL_BLOCK' "$PROTOCOL"; then
  pass "execute-protocol.md: SKILL_BLOCK variable removed"
else
  fail "execute-protocol.md: SKILL_BLOCK still referenced (should be removed)"
fi

# Negative: generate-skill-activation.sh removed from execute-protocol
if ! grep -q 'generate-skill-activation.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: generate-skill-activation.sh references removed"
else
  fail "execute-protocol.md: still references generate-skill-activation.sh"
fi

# Positive: orchestrator-composed explicit skill outcomes in Scout/Lead spawn templates
if grep -q 'skill_activation' "$VIBE_CMD" && grep -q 'skill_no_activation' "$VIBE_CMD" && grep -q 'skill_activation' "$RESEARCH_CMD" && grep -q 'skill_no_activation' "$RESEARCH_CMD"; then
  pass "vibe.md + research.md: orchestrator-composed explicit positive and negative skill outcomes"
else
  fail "vibe.md or research.md: missing explicit positive or negative skill outcomes"
fi

# Positive: intelligent selection language in vibe.md
if grep -q 'evaluate installed skills' "$VIBE_CMD"; then
  pass "vibe.md: uses intelligent skill evaluation language"
else
  fail "vibe.md: missing intelligent skill evaluation language"
fi

# Negative: old "Do not skip any listed skill" removed
if ! grep -q 'Do not skip any listed skill' "$VIBE_CMD" && ! grep -q 'Do not skip any listed skill' "$RESEARCH_CMD"; then
  pass "vibe.md + research.md: 'Do not skip any listed skill' removed"
else
  fail "vibe.md or research.md: still has 'Do not skip any listed skill'"
fi

# Anti-LLM-composition directive removed (no longer using pre-computed blocks)
if ! grep -q 'Do NOT attempt to compose skill activation yourself' "$PROTOCOL"; then
  pass "execute-protocol.md: anti-LLM-composition directive removed (intelligent selection now)"
else
  fail "execute-protocol.md: anti-LLM-composition directive still present"
fi

if ! (grep -Ei 'skill_activation|Skill\(' "$PROTOCOL" "$VIBE_CMD" "$RESEARCH_CMD" | grep -qiE 'if you need|if relevant|clearly relevant'); then
  pass "skill activation prompts: no weak conditional phrasing in skill-instruction lines"
else
  fail "skill activation prompts: weak conditional phrasing present in skill-instruction lines"
fi

# Agent system prompts: no 'clearly relevant' in any agent file
if ! grep -rq 'clearly relevant' "$ROOT/agents/"; then
  pass "agent prompts: no 'clearly relevant' conditional phrasing"
else
  fail "agent prompts: 'clearly relevant' still present — use direct imperative language"
fi

# Negative: no STATE.md Installed fallback in agent skill activation sections
if ! grep -rq 'STATE.md.*Installed\|Installed.*STATE.md' "$ROOT/agents/"; then
  pass "agent prompts: no STATE.md Installed fallback (removed — skills surfaced via available_skills)"
else
  fail "agent prompts: STATE.md Installed fallback still present in agents"
fi

# Negative: .skill-names should NOT be in planning-git transient gitignore
if ! grep -q '\.skill-names' "$ROOT/scripts/planning-git.sh"; then
  pass "planning-git.sh: no .skill-names in transient gitignore (removed)"
else
  fail "planning-git.sh: still has .skill-names in transient gitignore"
fi

# Brownfield: session-start.sh should clean up stale .skill-names
if grep -q 'rm.*\.skill-names' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: has brownfield .skill-names cleanup"
else
  fail "session-start.sh: missing brownfield .skill-names cleanup"
fi

# Layer 3: SubagentStart hook removed (skill visibility is native to Claude Code)
if ! grep -q 'inject-subagent-skills.sh' "$HOOKS_FILE"; then
  pass "hooks.json: inject-subagent-skills.sh removed (Layer 3 — native CC skill visibility)"
else
  fail "hooks.json: inject-subagent-skills.sh still present (should be removed)"
fi

# Compaction durability: compile-context.sh should NOT call emit_skills_section for any role
COMPILER="$ROOT/scripts/compile-context.sh"
if ! grep -q 'emit_skills_section' "$COMPILER"; then
  pass "compile-context.sh: emit_skills_section fully removed (all roles)"
else
  fail "compile-context.sh: emit_skills_section still present"
fi

# Negative check: no file should use the old "is 0" / "is a positive integer" phrasing
for _cmd_file in $_MAX_TURNS_COMMANDS; do
  _cmd_name=$(basename "$_cmd_file")
  if grep -q 'MAX_TURNS.*is 0' "$_cmd_file" || grep -q 'MAX_TURNS.*is a positive integer' "$_cmd_file"; then
    fail "$_cmd_name: uses old 'is 0'/'is a positive integer' phrasing (should use non-empty/empty)"
  else
    pass "$_cmd_name: uses non-empty/empty phrasing for maxTurns"
  fi
done

# --- Subagent type specification: all spawn points must specify subagent_type ---

echo ""
echo "=== Subagent Type Verification ==="

# Count subagent_type occurrences across commands and references
_SAT_TOTAL=$(grep -h 'subagent_type.*vbw:' "${TRACKED_COMMAND_REFERENCE_FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')

if [ "$_SAT_TOTAL" -ge 16 ]; then
  pass "subagent_type: ${_SAT_TOTAL} spawn points specify subagent_type (>= 16 expected)"
else
  fail "subagent_type: only ${_SAT_TOTAL} spawn points specify subagent_type (>= 16 expected)"
fi

# Each role that spawns agents must have subagent_type for that role
for _role_check in "vbw-scout:commands/vibe.md" "vbw-scout:commands/research.md" "vbw-scout:commands/map.md" "vbw-dev:commands/fix.md" "vbw-dev:references/execute-protocol.md" "vbw-debugger:commands/debug.md" "vbw-qa:commands/qa.md" "vbw-qa:references/execute-protocol.md" "vbw-lead:commands/vibe.md"; do
  _sat_role="${_role_check%%:*}"
  _sat_file="${_role_check#*:}"
  if grep -q "subagent_type.*${_sat_role}" "$ROOT/$_sat_file"; then
    pass "$_sat_file: specifies subagent_type for $_sat_role"
  else
    fail "$_sat_file: missing subagent_type for $_sat_role"
  fi
done

echo ""
echo "=== Skill Decision Logging Hook ==="

HOOKS_JSON="$ROOT/hooks/hooks.json"

# Validate structural wiring: PreToolUse event, Agent|TaskCreate matcher, timeout 3, correct script
if jq -e '
  .hooks.PreToolUse[]
  | select(.matcher == "Agent|TaskCreate")
  | .hooks[]
  | select(.command | contains("skill-decision-logger.sh"))
  | select(.timeout == 3)
' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks.json: skill-decision-logger.sh wired under PreToolUse Agent|TaskCreate (timeout=3)"
else
  fail "hooks.json: skill-decision-logger.sh not correctly wired (expected PreToolUse → Agent|TaskCreate → timeout=3)"
fi

if jq -e '
  .hooks.PreToolUse[]
  | select(.matcher == "Skill")
  | .hooks[]
  | select(.command | contains("skill-decision-logger.sh"))
  | select(.timeout == 3)
' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks.json: skill-decision-logger.sh wired under PreToolUse Skill (timeout=3)"
else
  fail "hooks.json: skill-decision-logger.sh missing runtime Skill hook wiring"
fi

if [ -f "$ROOT/scripts/skill-decision-logger.sh" ]; then
  pass "scripts/skill-decision-logger.sh: exists"
else
  fail "scripts/skill-decision-logger.sh: missing"
fi

if [ -f "$ROOT/scripts/extract-skill-follow-up-files.sh" ]; then
  pass "scripts/extract-skill-follow-up-files.sh: exists"
else
  fail "scripts/extract-skill-follow-up-files.sh: missing"
fi

if grep -q '\.claude/skills' "$ROOT/scripts/extract-skill-follow-up-files.sh" \
  && grep -q 'CLAUDE_DIR/skills' "$ROOT/scripts/extract-skill-follow-up-files.sh"; then
  pass "scripts/extract-skill-follow-up-files.sh: covers project-local and global Claude skill roots"
else
  fail "scripts/extract-skill-follow-up-files.sh: missing project-local or global Claude skill roots"
fi

if grep -q '\.agents/skills\|\.pi/skills\|\$HOME/.agents/skills' "$ROOT/scripts/extract-skill-follow-up-files.sh"; then
  fail "scripts/extract-skill-follow-up-files.sh: still references non-Claude lookalike skill roots"
else
  pass "scripts/extract-skill-follow-up-files.sh: rejects non-Claude lookalike skill roots"
fi

verify_runtime_skill_root_guard

if [ -x "$ROOT/scripts/skill-decision-logger.sh" ]; then
  pass "scripts/skill-decision-logger.sh: is executable"
else
  fail "scripts/skill-decision-logger.sh: not executable"
fi

# The logger must always exit 0 (fail-open, never block agent spawn)
if grep -q 'exit 0' "$ROOT/scripts/skill-decision-logger.sh"; then
  pass "scripts/skill-decision-logger.sh: exits 0 (fail-open)"
else
  fail "scripts/skill-decision-logger.sh: missing exit 0 (must be fail-open)"
fi

if grep -q '\.tool_name // ""' "$ROOT/scripts/skill-decision-logger.sh" \
  && grep -q '\.tool_input.skill' "$ROOT/scripts/skill-decision-logger.sh"; then
  pass "scripts/skill-decision-logger.sh: parses runtime Skill tool payloads"
else
  fail "scripts/skill-decision-logger.sh: missing runtime Skill payload parsing"
fi

if grep -q 'runtime_skill' "$ROOT/scripts/skill-decision-logger.sh" \
  && grep -q 'orchestrator_preselection' "$ROOT/scripts/skill-decision-logger.sh"; then
  pass "scripts/skill-decision-logger.sh: distinguishes orchestrator vs runtime entries"
else
  fail "scripts/skill-decision-logger.sh: missing orchestrator/runtime discriminator"
fi

if grep -q 'malformed skill_activation block exits 0 and writes no log' "$ROOT/tests/skill-decision-logger.bats" \
  && grep -q 'malformed skill_no_activation block exits 0 and writes no log' "$ROOT/tests/skill-decision-logger.bats"; then
  pass "tests/skill-decision-logger.bats: covers malformed prompt-block fail-open behavior"
else
  fail "tests/skill-decision-logger.bats: missing malformed prompt-block fail-open coverage"
fi

DEBUG_CMD="$ROOT/commands/debug.md"

if grep -Eq 'Pass 1:|\*\*Pass 1:\*\*' "$DEBUG_CMD" \
  && grep -Eq 'Pass 2:|\*\*Pass 2:\*\*' "$DEBUG_CMD"; then
  pass "debug.md: defines explicit two-pass skill-selection rubric"
else
  fail "debug.md: missing explicit two-pass skill-selection rubric"
fi

if grep -q 'bounded sparse-context enrichment' "$DEBUG_CMD" \
  && grep -Eq '1-3 likely files|1–3 likely files' "$DEBUG_CMD"; then
  pass "debug.md: documents bounded sparse-context enrichment"
else
  fail "debug.md: missing bounded sparse-context enrichment contract"
fi

if grep -q 'Treat `DETAIL_STATUS=ok` as “lookup succeeded,” not automatically as “detail is useful.”' "$DEBUG_CMD" \
  && grep -q 'non-empty `detail.context` or at least one related file' "$DEBUG_CMD"; then
  pass "debug.md: empty detail does not suppress enrichment"
else
  fail "debug.md: missing empty-detail enrichment guard"
fi

if grep -q 'ModelContext' "$DEBUG_CMD" \
  && grep -q 'VersionedSchema' "$DEBUG_CMD" \
  && grep -q 'core-data' "$DEBUG_CMD"; then
  pass "debug.md: includes explicit SwiftData positive cues and Core Data negative cue"
else
  fail "debug.md: missing SwiftData positive cues or Core Data negative cue"
fi

if grep -q 'concrete working files or framework markers' "$DEBUGGER_AGENT" \
  && grep -q 'activate `swiftdata` right away' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: adds immediate early-evidence fallback rule"
else
  fail "vbw-debugger.md: missing immediate early-evidence fallback rule"
fi

if grep -q 'bounded sparse-input enrichment' "$PROTOCOL" \
  && grep -q 'core-data' "$PROTOCOL"; then
  pass "execute-protocol.md: mirrors sparse-input enrichment and persistence-skill guardrails"
else
  fail "execute-protocol.md: missing mirrored sparse-input enrichment guardrails"
fi

echo ""
echo "=== Skill Follow-Up Read Nudge ==="

# execute-protocol.md: overview block (Spawned agents bullet) has the nudge
if grep -q 'do not scan entire skill folders or read unrelated references' "$PROTOCOL"; then
  pass "execute-protocol.md: has skill follow-up read nudge"
else
  fail "execute-protocol.md: missing skill follow-up read nudge"
fi

# execute-protocol.md: both loci covered (overview + Skill activation for Dev/QA tasks)
_EP_NUDGE_COUNT=$(grep -c 'scan entire skill folders or read unrelated references\|not entire skill folders or unrelated references' "$PROTOCOL")
if [ "$_EP_NUDGE_COUNT" -ge 2 ]; then
  pass "execute-protocol.md: follow-up read nudge in both loci ($_EP_NUDGE_COUNT sites)"
else
  fail "execute-protocol.md: follow-up read nudge in only $_EP_NUDGE_COUNT locus (expected 2)"
fi

# All command skill-contract files have the nudge
for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -q 'do not scan entire skill folders or read unrelated references' "$contract_file"; then
    pass "$contract_name: has skill follow-up read nudge"
  else
    fail "$contract_name: missing skill follow-up read nudge"
  fi
done

# All 7 agent files have the nudge in the top-level Skill Activation section
for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if grep -q 'do not scan entire skill folders or read unrelated references' "$agent_file"; then
    pass "$agent_name: has skill follow-up read nudge (top-level)"
  else
    fail "$agent_name: missing skill follow-up read nudge (top-level)"
  fi
done

for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if grep -q '<skill_follow_up_files>' "$agent_file"; then
    pass "$agent_name: understands payload-local resolved follow-up file block"
  else
    fail "$agent_name: missing payload-local resolved follow-up file block guidance"
  fi
done

# All 7 agent files have the runtime-local follow-up read line
# The fallback layer now uses the full exact sentence in both the top-level
# and runtime-local locations, so each agent file must contain the exact line
# at least twice.
for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if [ "$(grep -Fc "$SKILL_FOLLOW_UP_SENTENCE" "$agent_file")" -ge 2 ]; then
    pass "$agent_name: has runtime-local follow-up read nudge"
  else
    fail "$agent_name: missing runtime-local follow-up read nudge"
  fi
done

# debug.md: all 3 loci have the nudge
_DEBUG_NUDGE_COUNT=$(grep -c 'do not scan entire skill folders or read unrelated references' "$DEBUG_CMD")
if [ "$_DEBUG_NUDGE_COUNT" -ge 3 ]; then
  pass "debug.md: follow-up read nudge present across the 3 debug skill sites (raw occurrences: $_DEBUG_NUDGE_COUNT)"
else
  fail "debug.md: follow-up read nudge appears in only $_DEBUG_NUDGE_COUNT raw loci (expected at least 3)"
fi

# vbw-scout.md: has second surface near File Writing
# Use awk to extract content after "## File Writing" header up to the next "## " header
if awk '/^## File Writing/{found=1; next} found && /^## /{exit} found' "$SCOUT_AGENT" | grep -Fq "$SKILL_FOLLOW_UP_SENTENCE"; then
  pass "vbw-scout.md: has runtime-local follow-up read nudge near File Writing"
else
  fail "vbw-scout.md: missing runtime-local follow-up read nudge near File Writing"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All skill activation pipeline checks passed."
exit 0
