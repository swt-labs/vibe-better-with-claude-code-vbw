#!/usr/bin/env bats
# Tests for emit-skill-xml.sh — <available_skills> XML generation

load test_helper

setup() {
  setup_temp_dir
  export ORIG_HOME="$HOME"
  export ORIG_CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}"
  export HOME="$TEST_TEMP_DIR"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
}

teardown() {
  export HOME="$ORIG_HOME"
  unset CLAUDE_CONFIG_DIR 2>/dev/null || true
  [ -n "$ORIG_CLAUDE_CONFIG_DIR" ] && export CLAUDE_CONFIG_DIR="$ORIG_CLAUDE_CONFIG_DIR"
  teardown_temp_dir
}

# Helper: create a skill directory with SKILL.md frontmatter
create_skill() {
  local base_dir="$1" skill_name="$2" name_val="${3:-}" desc_val="${4:-}"
  mkdir -p "$base_dir/$skill_name"
  {
    echo "---"
    [ -n "$name_val" ] && echo "name: $name_val"
    [ -n "$desc_val" ] && echo "description: $desc_val"
    echo "---"
    echo ""
    echo "# $skill_name"
  } > "$base_dir/$skill_name/SKILL.md"
}

# --- Test 1: No skill dirs → empty output ---

@test "emit-skill-xml: no skill dirs produces empty output" {
  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- Test 2: Single skill with valid frontmatter → correct XML ---

@test "emit-skill-xml: single skill produces correct XML" {
  create_skill "$CLAUDE_CONFIG_DIR/skills" "pdf-tool" "pdf-tool" "Extracts text from PDFs"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<available_skills>"* ]]
  [[ "$output" == *"<name>pdf-tool</name>"* ]]
  [[ "$output" == *"<description>Extracts text from PDFs</description>"* ]]
  [[ "$output" == *"<location>"* ]]
  [[ "$output" == *"</available_skills>"* ]]
}

# --- Test 3: Multiple skills → all present ---

@test "emit-skill-xml: multiple skills all present in output" {
  create_skill "$CLAUDE_CONFIG_DIR/skills" "skill-a" "Skill A" "Description A"
  create_skill "$CLAUDE_CONFIG_DIR/skills" "skill-b" "Skill B" "Description B"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>Skill A</name>"* ]]
  [[ "$output" == *"<name>Skill B</name>"* ]]
  [[ "$output" == *"<description>Description A</description>"* ]]
  [[ "$output" == *"<description>Description B</description>"* ]]
}

# --- Test 4: Skill dir without SKILL.md → skipped ---

@test "emit-skill-xml: skill dir without SKILL.md is skipped" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/no-skillmd"
  # No SKILL.md file created
  create_skill "$CLAUDE_CONFIG_DIR/skills" "has-skillmd" "Has It" "Present"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>Has It</name>"* ]]
  [[ "$output" != *"no-skillmd"* ]]
}

# --- Test 5: Missing name → falls back to folder name ---

@test "emit-skill-xml: missing name uses folder name" {
  local skill_dir="$CLAUDE_CONFIG_DIR/skills/my-folder-skill"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'YAML'
---
description: A skill without a name field
---
YAML

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>my-folder-skill</name>"* ]]
  [[ "$output" == *"<description>A skill without a name field</description>"* ]]
}

# --- Test 6: Missing description → "No description available" ---

@test "emit-skill-xml: missing description uses default" {
  local skill_dir="$CLAUDE_CONFIG_DIR/skills/nodesc-skill"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'YAML'
---
name: nodesc-skill
---
YAML

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>nodesc-skill</name>"* ]]
  [[ "$output" == *"<description>No description available</description>"* ]]
}

# --- Test 7: Dedup across dirs → project wins, listed once ---

@test "emit-skill-xml: dedup across dirs, project wins" {
  # Project skill
  create_skill "$TEST_TEMP_DIR/.claude/skills" "dup-skill" "Project Version" "From project"
  # Global skill (same folder name)
  create_skill "$CLAUDE_CONFIG_DIR/skills" "dup-skill" "Global Version" "From global"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>Project Version</name>"* ]]
  [[ "$output" != *"Global Version"* ]]
}

# --- Test 8: XML special chars escaped ---

@test "emit-skill-xml: XML special chars are escaped" {
  create_skill "$CLAUDE_CONFIG_DIR/skills" "esctest" "A & B" "Handles <tags> & more"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"A &amp; B"* ]]
  [[ "$output" == *"Handles &lt;tags&gt; &amp; more"* ]]
}

# --- Test 9: Format validation (wrapper and child elements) ---

@test "emit-skill-xml: output has correct XML structure" {
  create_skill "$CLAUDE_CONFIG_DIR/skills" "fmt-skill" "Formatter" "Tests format"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]

  # Starts with <available_skills>
  [[ "$output" == "<available_skills>"* ]]
  # Ends with </available_skills>
  [[ "$output" == *"</available_skills>" ]]
  # Contains child <skill> elements
  [[ "$output" == *"<skill>"* ]]
  [[ "$output" == *"</skill>"* ]]
  # Contains required child elements
  [[ "$output" == *"<name>"* ]]
  [[ "$output" == *"<description>"* ]]
  [[ "$output" == *"<location>"* ]]
}

# --- Test 10: Third scan directory ($HOME/.agents/skills) ---

@test "emit-skill-xml: discovers skills in agents ecosystem dir" {
  create_skill "$HOME/.agents/skills" "agents-skill" "Agents Ecosystem Skill" "From agents dir"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>Agents Ecosystem Skill</name>"* ]]
  [[ "$output" == *"<description>From agents dir</description>"* ]]
}

# --- Test 11: Dedup across all three dirs, project wins over agents ---

@test "emit-skill-xml: dedup across all three dirs, project wins" {
  create_skill "$TEST_TEMP_DIR/.claude/skills" "shared-skill" "Project Version" "From project"
  create_skill "$CLAUDE_CONFIG_DIR/skills" "shared-skill" "Global Version" "From global"
  create_skill "$HOME/.agents/skills" "shared-skill" "Agents Version" "From agents"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>Project Version</name>"* ]]
  [[ "$output" != *"Global Version"* ]]
  [[ "$output" != *"Agents Version"* ]]
}

# --- Test 12: CRLF line endings in SKILL.md don't corrupt values ---

@test "emit-skill-xml: CRLF line endings handled correctly" {
  local skill_dir="$CLAUDE_CONFIG_DIR/skills/crlf-skill"
  mkdir -p "$skill_dir"
  # Write SKILL.md with Windows line endings (\r\n)
  printf -- '---\r\nname: crlf-test\r\ndescription: Has CRLF endings\r\n---\r\n' > "$skill_dir/SKILL.md"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>crlf-test</name>"* ]]
  [[ "$output" == *"<description>Has CRLF endings</description>"* ]]
  # Ensure no \r leaked into output
  [[ "$output" != *$'\r'* ]]
}

# --- Test 13: Frontmatter boundary enforced (body content ignored) ---

@test "emit-skill-xml: body content with name:/description: is ignored" {
  local skill_dir="$CLAUDE_CONFIG_DIR/skills/body-leak"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'YAML'
---
name: real-name
description: real-description
---

name: leaked-body-name
description: leaked-body-description
YAML

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>real-name</name>"* ]]
  [[ "$output" == *"<description>real-description</description>"* ]]
  [[ "$output" != *"leaked-body-name"* ]]
  [[ "$output" != *"leaked-body-description"* ]]
}

# --- Test 14: Multiline YAML description is joined ---

@test "emit-skill-xml: multiline description joined into one line" {
  local skill_dir="$CLAUDE_CONFIG_DIR/skills/multiline-desc"
  mkdir -p "$skill_dir"
  cat > "$skill_dir/SKILL.md" <<'YAML'
---
name: multi-skill
description: First line of desc
  continued on second line
  and third line
---
YAML

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<name>multi-skill</name>"* ]]
  [[ "$output" == *"First line of desc continued on second line and third line"* ]]
}

# --- Test 15: Location uses absolute paths ---

@test "emit-skill-xml: location contains absolute path" {
  create_skill "$CLAUDE_CONFIG_DIR/skills" "abs-path-skill" "Abs Path" "Tests absolute"

  run bash "$SCRIPTS_DIR/emit-skill-xml.sh" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  # Location should start with / (absolute path)
  [[ "$output" == *"<location>/"* ]]
}
