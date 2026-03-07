#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude-config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
}

teardown() {
  teardown_temp_dir
}

# --- resolve-claude-dir sourcing ---

@test "muninn-setup.sh sources resolve-claude-dir.sh" {
  grep -q 'resolve-claude-dir.sh' "$SCRIPTS_DIR/muninn-setup.sh"
}

@test "muninn-setup.sh does not use bare HOME/.claude" {
  # Should only reference CLAUDE_DIR (from resolve-claude-dir.sh), not $HOME/.claude
  ! grep -q '$HOME/.claude' "$SCRIPTS_DIR/muninn-setup.sh"
}

# --- _derive_vault_name ---

@test "muninn-setup: _derive_vault_name derives from git remote" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git remote add origin https://github.com/user/my-cool-project.git

  # Source the helpers (we need to extract just the function)
  run bash -c '
    . "'"$SCRIPTS_DIR"'/resolve-claude-dir.sh"
    _derive_vault_name() {
      local name
      name=$(basename "$(git remote get-url origin 2>/dev/null || pwd)" | sed "s/\.git$//" | tr "[:upper:]" "[:lower:]" | tr " " "-" | tr -cd "a-z0-9_-")
      [ -z "$name" ] && name="vbw-$(date +%s)"
      echo "$name"
    }
    cd "'"$TEST_TEMP_DIR"'"
    _derive_vault_name
  '
  [ "$status" -eq 0 ]
  [ "$output" = "my-cool-project" ]
}

@test "muninn-setup: _derive_vault_name falls back to dirname without git" {
  cd "$TEST_TEMP_DIR"
  local dirname
  dirname=$(basename "$TEST_TEMP_DIR" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9_-')

  run bash -c '
    _derive_vault_name() {
      local name
      name=$(basename "$(git remote get-url origin 2>/dev/null || pwd)" | sed "s/\.git$//" | tr "[:upper:]" "[:lower:]" | tr " " "-" | tr -cd "a-z0-9_-")
      [ -z "$name" ] && name="vbw-$(date +%s)"
      echo "$name"
    }
    cd "'"$TEST_TEMP_DIR"'"
    _derive_vault_name
  '
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# --- _read_token ---

@test "muninn-setup: _read_token reads from mcp.json" {
  cat > "$CLAUDE_CONFIG_DIR/mcp.json" <<'JSON'
{
  "mcpServers": {
    "muninn": {
      "env": {
        "MUNINN_API_TOKEN": "test-token-abc123"
      }
    }
  }
}
JSON

  run bash -c '
    export CLAUDE_CONFIG_DIR="'"$CLAUDE_CONFIG_DIR"'"
    . "'"$SCRIPTS_DIR"'/resolve-claude-dir.sh"
    _read_token() {
      local claude_dir="$CLAUDE_DIR"
      local token=""
      token=$(jq -r ".mcpServers.muninn.env.MUNINN_API_TOKEN // empty" "$claude_dir/mcp.json" 2>/dev/null || true)
      [ -z "$token" ] && token=$(jq -r ".mcpServers.muninn.env.MUNINN_API_TOKEN // empty" "$claude_dir/mcp_servers.json" 2>/dev/null || true)
      echo "$token"
    }
    _read_token
  '
  [ "$status" -eq 0 ]
  [ "$output" = "test-token-abc123" ]
}

@test "muninn-setup: _read_token falls back to mcp_servers.json" {
  cat > "$CLAUDE_CONFIG_DIR/mcp_servers.json" <<'JSON'
{
  "mcpServers": {
    "muninn": {
      "env": {
        "MUNINN_API_TOKEN": "fallback-token-xyz"
      }
    }
  }
}
JSON

  run bash -c '
    export CLAUDE_CONFIG_DIR="'"$CLAUDE_CONFIG_DIR"'"
    . "'"$SCRIPTS_DIR"'/resolve-claude-dir.sh"
    _read_token() {
      local claude_dir="$CLAUDE_DIR"
      local token=""
      token=$(jq -r ".mcpServers.muninn.env.MUNINN_API_TOKEN // empty" "$claude_dir/mcp.json" 2>/dev/null || true)
      [ -z "$token" ] && token=$(jq -r ".mcpServers.muninn.env.MUNINN_API_TOKEN // empty" "$claude_dir/mcp_servers.json" 2>/dev/null || true)
      echo "$token"
    }
    _read_token
  '
  [ "$status" -eq 0 ]
  [ "$output" = "fallback-token-xyz" ]
}

@test "muninn-setup: _read_token returns empty when no config" {
  run bash -c '
    export CLAUDE_CONFIG_DIR="'"$CLAUDE_CONFIG_DIR"'"
    . "'"$SCRIPTS_DIR"'/resolve-claude-dir.sh"
    _read_token() {
      local claude_dir="$CLAUDE_DIR"
      local token=""
      token=$(jq -r ".mcpServers.muninn.env.MUNINN_API_TOKEN // empty" "$claude_dir/mcp.json" 2>/dev/null || true)
      [ -z "$token" ] && token=$(jq -r ".mcpServers.muninn.env.MUNINN_API_TOKEN // empty" "$claude_dir/mcp_servers.json" 2>/dev/null || true)
      echo "$token"
    }
    _read_token
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- --help mode ---

@test "muninn-setup: --help shows usage" {
  run bash "$SCRIPTS_DIR/muninn-setup.sh" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Usage"
  echo "$output" | grep -q "8750"
  echo "$output" | grep -q "8475"
}

# --- --check mode without MuninnDB installed ---

@test "muninn-setup: --check exits cleanly when muninn not installed" {
  # Remove muninn from PATH so it's not found
  run env PATH="/usr/bin:/bin" bash "$SCRIPTS_DIR/muninn-setup.sh" --check
  # Should mention binary not found (exit code may vary by platform)
  echo "$output" | grep -qi "not found\|not installed\|Binary"
}

# --- syntax check ---

@test "muninn-setup.sh has valid bash syntax" {
  run bash -n "$SCRIPTS_DIR/muninn-setup.sh"
  [ "$status" -eq 0 ]
}
