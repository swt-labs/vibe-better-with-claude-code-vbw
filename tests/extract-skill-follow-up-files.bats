#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

write_skill_fixture() {
  local base_dir="$1"
  local skill_name="$2"
  shift 2

  write_custom_skill_fixture "$base_dir" "$skill_name" "$(cat <<'EOF'
---
name: fixture-skill
description: Fixture skill
---

# Fixture Skill

## References

- [First](references/first.md)
- [Second](references/second.md)
- [Anchor](#local-anchor)
- [External](https://example.com/reference.md)
- [Missing](references/missing.md)
EOF
)" "$@"
}

write_custom_skill_fixture() {
  local base_dir="$1"
  local skill_name="$2"
  local skill_body="$3"
  shift 3

  mkdir -p "$base_dir/$skill_name/references"
  printf '%s\n' "$skill_body" > "$base_dir/$skill_name/SKILL.md"

  for rel_path in "$@"; do
    if [[ "$rel_path" == */ ]]; then
      mkdir -p "$base_dir/$skill_name/$rel_path"
      continue
    fi

    mkdir -p "$(dirname "$base_dir/$skill_name/$rel_path")"
    printf '# %s\n' "$rel_path" > "$base_dir/$skill_name/$rel_path"
  done
}

@test "extract-skill-follow-up-files: resolves project .claude skills to exact paths" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"
  write_skill_fixture "$project_dir/.claude/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" swiftdata

  [ "$status" -eq 0 ]
  [[ "$output" == *"<skill_follow_up_files>"* ]]
  [[ "$output" == *"Skill: swiftdata"* ]]
  [[ "$output" == *"$project_dir/.claude/skills/swiftdata/references/first.md"* ]]
  [[ "$output" == *"$project_dir/.claude/skills/swiftdata/references/second.md"* ]]
  [[ "$output" != *"https://example.com/reference.md"* ]]
  [[ "$output" != *"missing.md"* ]]
}

@test "extract-skill-follow-up-files: prefers project .claude skills over global copies" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"

  write_skill_fixture "$CLAUDE_CONFIG_DIR/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"
  write_skill_fixture "$project_dir/.claude/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" swiftdata

  [ "$status" -eq 0 ]
  [[ "$output" == *"$project_dir/.claude/skills/swiftdata/references/first.md"* ]]
  [[ "$output" != *"$CLAUDE_CONFIG_DIR/skills/swiftdata/references/first.md"* ]]
}

@test "extract-skill-follow-up-files: falls back to CLAUDE_CONFIG_DIR skills" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"

  write_skill_fixture "$CLAUDE_CONFIG_DIR/skills" "find-docs" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" find-docs

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill: find-docs"* ]]
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/skills/find-docs/references/first.md"* ]]
}

@test "extract-skill-follow-up-files: falls back to HOME/.config/claude-code skills when CLAUDE_CONFIG_DIR is unset" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"
  unset CLAUDE_CONFIG_DIR
  mkdir -p "$HOME/.config/claude-code/skills"

  write_skill_fixture "$HOME/.config/claude-code/skills" "find-docs" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" find-docs

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill: find-docs"* ]]
  [[ "$output" == *"$HOME/.config/claude-code/skills/find-docs/references/first.md"* ]]
}

@test "extract-skill-follow-up-files: falls back to HOME/.claude skills when newer config dir is absent" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"
  unset CLAUDE_CONFIG_DIR

  write_skill_fixture "$HOME/.claude/skills" "find-docs" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" find-docs

  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.claude/skills/find-docs/references/first.md"* ]]
}

@test "extract-skill-follow-up-files: ignores .agents, .pi, and HOME/.agents lookalike roots" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"

  write_skill_fixture "$project_dir/.agents/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"
  write_skill_fixture "$project_dir/.pi/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"
  write_skill_fixture "$HOME/.agents/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" swiftdata

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-skill-follow-up-files: ignores traversal tokens that would escape into project lookalike roots" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir/.claude/skills"

  write_skill_fixture "$project_dir/.agents/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"
  write_skill_fixture "$project_dir/.pi/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" ../../.agents/skills/swiftdata ../../.pi/skills/swiftdata

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-skill-follow-up-files: ignores traversal tokens that would escape into HOME/.agents through the global root" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"
  unset CLAUDE_CONFIG_DIR
  mkdir -p "$HOME/.claude/skills"

  write_skill_fixture "$HOME/.agents/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" ../../.agents/skills/swiftdata

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-skill-follow-up-files: skill with no markdown links exits 0 and emits nothing" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"

  write_custom_skill_fixture "$project_dir/.claude/skills" "swiftdata" "$(cat <<'EOF'
---
name: fixture-skill
description: Fixture skill
---

# Fixture Skill

This skill intentionally has no markdown links.
EOF
)"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" swiftdata

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-skill-follow-up-files: rejects project-local SKILL.md links that normalize outside the active skill directory" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"

  write_custom_skill_fixture "$project_dir/.claude/skills" "swiftdata" "$(cat <<'EOF'
---
name: fixture-skill
description: Fixture skill
---

# Fixture Skill

## References

- [Safe](references/first.md)
- [Normalized](docs/../references/second.md)
- [Escape](../other-skill/references/secret.md)
EOF
)" \
    "references/first.md" \
    "references/second.md" \
    "docs/"

  mkdir -p "$project_dir/.claude/skills/other-skill/references"
  printf '# secret\n' > "$project_dir/.claude/skills/other-skill/references/secret.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" swiftdata

  [ "$status" -eq 0 ]
  [[ "$output" == *"$project_dir/.claude/skills/swiftdata/references/first.md"* ]]
  [[ "$output" == *"$project_dir/.claude/skills/swiftdata/references/second.md"* ]]
  [[ "$output" != *"$project_dir/.claude/skills/other-skill/references/secret.md"* ]]
}

@test "extract-skill-follow-up-files: rejects global SKILL.md links that normalize outside the active skill directory" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"

  write_custom_skill_fixture "$CLAUDE_CONFIG_DIR/skills" "find-docs" "$(cat <<'EOF'
---
name: fixture-skill
description: Fixture skill
---

# Fixture Skill

## References

- [Safe](references/first.md)
- [Normalized](docs/../references/second.md)
- [Escape](../other-skill/references/secret.md)
EOF
)" \
    "references/first.md" \
    "references/second.md" \
    "docs/"

  mkdir -p "$CLAUDE_CONFIG_DIR/skills/other-skill/references"
  printf '# secret\n' > "$CLAUDE_CONFIG_DIR/skills/other-skill/references/secret.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" find-docs

  [ "$status" -eq 0 ]
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/skills/find-docs/references/first.md"* ]]
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/skills/find-docs/references/second.md"* ]]
  [[ "$output" != *"$CLAUDE_CONFIG_DIR/skills/other-skill/references/secret.md"* ]]
}

@test "extract-skill-follow-up-files: preserves normalized in-tree links and dedupes equivalent paths" {
  local project_dir="$TEST_TEMP_DIR/project"
  local project_dir_abs
  local first_path first_count
  mkdir -p "$project_dir"

  write_custom_skill_fixture "$project_dir/.claude/skills" "swiftdata" "$(cat <<'EOF'
---
name: fixture-skill
description: Fixture skill
---

# Fixture Skill

## References

- [First](references/first.md)
- [Duplicate First](./references/first.md)
- [Normalized](docs/../references/second.md)
EOF
)" \
    "references/first.md" \
    "references/second.md" \
    "docs/"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" swiftdata

  [ "$status" -eq 0 ]
  project_dir_abs=$(cd "$project_dir" && pwd -P)
  [[ "$output" == *"$project_dir_abs/.claude/skills/swiftdata/references/first.md"* ]]
  [[ "$output" == *"$project_dir_abs/.claude/skills/swiftdata/references/second.md"* ]]

  first_path="$project_dir_abs/.claude/skills/swiftdata/references/first.md"
  first_count=$(printf '%s\n' "$output" | awk -v needle="- $first_path" '$0 == needle { count++ } END { print count + 0 }')
  [ "$first_count" -eq 1 ]
}

@test "extract-skill-follow-up-files: rejects project-local symlinked follow-up files that resolve outside the active skill directory" {
  local project_dir="$TEST_TEMP_DIR/project"
  local project_dir_abs outside_file
  mkdir -p "$project_dir"

  write_custom_skill_fixture "$project_dir/.claude/skills" "swiftdata" "$(cat <<'EOF'
---
name: fixture-skill
description: Fixture skill
---

# Fixture Skill

## References

- [Safe](references/first.md)
- [Symlink Escape](references/linked-outside.md)
EOF
)" \
    "references/first.md"

  mkdir -p "$TEST_TEMP_DIR/outside"
  outside_file="$TEST_TEMP_DIR/outside/project-secret.md"
  printf '# secret\n' > "$outside_file"
  ln -s "$outside_file" "$project_dir/.claude/skills/swiftdata/references/linked-outside.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" swiftdata

  [ "$status" -eq 0 ]
  project_dir_abs=$(cd "$project_dir" && pwd -P)
  [[ "$output" == *"$project_dir_abs/.claude/skills/swiftdata/references/first.md"* ]]
  [[ "$output" != *"linked-outside.md"* ]]
}

@test "extract-skill-follow-up-files: rejects global symlinked follow-up files that resolve outside the active skill directory" {
  local project_dir="$TEST_TEMP_DIR/project"
  local claude_dir_abs outside_file
  mkdir -p "$project_dir"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"

  write_custom_skill_fixture "$CLAUDE_CONFIG_DIR/skills" "find-docs" "$(cat <<'EOF'
---
name: fixture-skill
description: Fixture skill
---

# Fixture Skill

## References

- [Safe](references/first.md)
- [Symlink Escape](references/linked-outside.md)
EOF
)" \
    "references/first.md"

  mkdir -p "$TEST_TEMP_DIR/outside"
  outside_file="$TEST_TEMP_DIR/outside/global-secret.md"
  printf '# secret\n' > "$outside_file"
  ln -s "$outside_file" "$CLAUDE_CONFIG_DIR/skills/find-docs/references/linked-outside.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" find-docs

  [ "$status" -eq 0 ]
  claude_dir_abs=$(cd "$CLAUDE_CONFIG_DIR" && pwd -P)
  [[ "$output" == *"$claude_dir_abs/skills/find-docs/references/first.md"* ]]
  [[ "$output" != *"linked-outside.md"* ]]
}

@test "extract-skill-follow-up-files: preserves valid skills when a whitespace-delimited list includes a traversal token" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir/.claude/skills"

  write_skill_fixture "$project_dir/.claude/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"
  write_skill_fixture "$project_dir/.agents/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" "swiftdata ../../.agents/skills/swiftdata"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill: swiftdata"* ]]
  [[ "$output" == *"$project_dir/.claude/skills/swiftdata/references/first.md"* ]]
  [[ "$output" != *"$project_dir/.agents/skills/swiftdata/references/first.md"* ]]
}

@test "extract-skill-follow-up-files: ignores dot-segment pseudo skill names" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" . ..

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract-skill-follow-up-files: splits whitespace-delimited skill lists passed as one argument" {
  local project_dir="$TEST_TEMP_DIR/project"
  mkdir -p "$project_dir"

  write_skill_fixture "$project_dir/.claude/skills" "swiftdata" \
    "references/first.md" \
    "references/second.md"
  write_skill_fixture "$project_dir/.claude/skills" "swift-testing" \
    "references/first.md" \
    "references/second.md"

  run bash "$SCRIPTS_DIR/extract-skill-follow-up-files.sh" --project-dir "$project_dir" "swiftdata swift-testing"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill: swiftdata"* ]]
  [[ "$output" == *"Skill: swift-testing"* ]]
}
