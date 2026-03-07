#!/usr/bin/env bash
set -euo pipefail

# muninn-setup.sh — Install MuninnDB and configure it for VBW.
#
# Usage:
#   bash scripts/muninn-setup.sh           # Interactive install + init + start
#   bash scripts/muninn-setup.sh --check   # Check MuninnDB status only
#   bash scripts/muninn-setup.sh --start   # Skip install, just start server
#   bash scripts/muninn-setup.sh --vault   # Create/verify project vault only
#
# This script:
#   1. Checks prerequisites (curl, jq)
#   2. Installs the MuninnDB binary (if not present)
#   3. Runs `muninn init` to configure Claude Code MCP
#   4. Starts the MuninnDB server
#   5. Creates a project vault (if in a git repo or project dir)
#   6. Verifies the full setup
#
# VBW principle: this script ASKS before doing anything. No silent installs.
# In non-interactive environments, the script aborts rather than auto-approving.

# --- Colors (if terminal supports them) ---
if [ -t 1 ]; then
  BOLD='\033[1m' DIM='\033[2m' GREEN='\033[32m' YELLOW='\033[33m' RED='\033[31m' RESET='\033[0m'
else
  BOLD='' DIM='' GREEN='' YELLOW='' RED='' RESET=''
fi

info()  { printf "${BOLD}%s${RESET}\n" "$*"; }
ok()    { printf "${GREEN}  ✓ %s${RESET}\n" "$*"; }
warn()  { printf "${YELLOW}  ⚠ %s${RESET}\n" "$*"; }
fail()  { printf "${RED}  ✗ %s${RESET}\n" "$*"; }
dim()   { printf "${DIM}  %s${RESET}\n" "$*"; }

# --- Resolve Claude config directory ---
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"

# --- Port defaults (read from config if available) ---
_MUNINN_MCP_PORT=8750
_MUNINN_REST_PORT=8475
if [ -f ".vbw-planning/config.json" ] && command -v jq &>/dev/null; then
  _MUNINN_MCP_PORT=$(jq -r '.muninndb_port_mcp // 8750' ".vbw-planning/config.json" 2>/dev/null) || _MUNINN_MCP_PORT=8750
  _MUNINN_REST_PORT=$(jq -r '.muninndb_port_rest // 8475' ".vbw-planning/config.json" 2>/dev/null) || _MUNINN_REST_PORT=8475
fi

# --- Check if MuninnDB MCP server is healthy ---
_health_ok() {
  curl -sf --max-time 3 "http://localhost:${_MUNINN_MCP_PORT}/health" >/dev/null 2>&1
}

# --- Check if REST API is responding ---
_rest_ok() {
  curl -sf --max-time 3 "http://localhost:${_MUNINN_REST_PORT}/api/vaults" >/dev/null 2>&1
}

# --- Read API token from Claude Code MCP config ---
_read_token() {
  local claude_dir="$CLAUDE_DIR"
  local token=""
  token=$(jq -r '.mcpServers.muninn.env.MUNINN_API_TOKEN // empty' "$claude_dir/mcp.json" 2>/dev/null || true)
  [ -z "$token" ] && token=$(jq -r '.mcpServers.muninn.env.MUNINN_API_TOKEN // empty' "$claude_dir/mcp_servers.json" 2>/dev/null || true)
  echo "$token"
}

# --- Derive vault name from project ---
_derive_vault_name() {
  local name
  name=$(basename "$(git remote get-url origin 2>/dev/null || pwd)" | sed 's/\.git$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9_-')
  if [ -z "$name" ]; then
    name="vbw-$(date +%s)"
  fi
  # Multi-project isolation: if another project already uses this vault name
  # on the same MuninnDB instance, append a disambiguator based on the working
  # directory hash to prevent cross-project memory pollution.
  if _rest_ok 2>/dev/null; then
    local tok
    tok=$(_read_token)
    local -a curl_auth=( curl -sf )
    [ -n "$tok" ] && curl_auth+=( -H "Authorization: Bearer $tok" )
    if "${curl_auth[@]}" --max-time 3 http://localhost:${_MUNINN_REST_PORT}/api/vaults 2>/dev/null | jq -e --arg v "$name" '.[] | select(.name == $v)' >/dev/null 2>&1; then
      # Vault exists — check if it belongs to this project by comparing cwd
      local cwd_hash
      cwd_hash=$(printf '%s' "$(pwd)" | md5sum 2>/dev/null | cut -c1-6 || printf '%s' "$(pwd)" | md5 2>/dev/null | cut -c1-6 || echo "")
      local config_dir="${PWD}/.vbw-planning/config.json"
      if [ -f "$config_dir" ]; then
        local existing_vault
        existing_vault=$(jq -r '.muninndb_vault // ""' "$config_dir" 2>/dev/null || true)
        if [ "$existing_vault" = "$name" ]; then
          echo "$name"  # Same project, same vault
          return
        fi
      fi
      # Different project, same repo name — disambiguate
      if [ -n "$cwd_hash" ]; then
        name="${name}-${cwd_hash}"
      fi
    fi
  fi
  echo "$name"
}

# --- Prompt user for confirmation ---
confirm() {
  local prompt="$1"
  local default="${2:-y}"

  if ! { [ -t 0 ] || [ -e /dev/tty ]; }; then
    fail "Non-interactive environment detected. Cannot prompt for confirmation."
    dim "Run this script in an interactive terminal."
    return 1
  fi

  if [ "$default" = "y" ]; then
    printf "%s [Y/n] " "$prompt"
  else
    printf "%s [y/N] " "$prompt"
  fi

  read -r answer </dev/tty 2>/dev/null || {
    fail "Cannot read user input."
    return 1
  }
  answer="${answer:-$default}"

  case "$answer" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================
# Status check
# ============================================================
check_status() {
  local binary=false server=false rest=false token=false vault=""
  local version="" vault_name=""

  # Binary
  if command -v muninn &>/dev/null; then
    binary=true
    version=$(muninn --version 2>/dev/null | head -1 || echo "unknown")
  fi

  # MCP server (port ${_MUNINN_MCP_PORT})
  if _health_ok; then
    server=true
  fi

  # REST API (port ${_MUNINN_REST_PORT})
  if _rest_ok; then
    rest=true
  fi

  # MCP token
  local tok
  tok=$(_read_token)
  if [ -n "$tok" ]; then
    token=true
  fi

  # Vault (from config.json if present)
  if [ -f ".vbw-planning/config.json" ]; then
    vault_name=$(jq -r '.muninndb_vault // ""' .vbw-planning/config.json 2>/dev/null || true)
  fi

  info "MuninnDB Status"
  echo ""

  # Binary
  if [ "$binary" = true ]; then
    ok "Binary: installed (${version})"
  else
    fail "Binary: not found"
  fi

  # MCP server
  if [ "$server" = true ]; then
    ok "MCP server: running (port ${_MUNINN_MCP_PORT})"
  else
    fail "MCP server: not running"
  fi

  # REST API
  if [ "$rest" = true ]; then
    ok "REST API: responding (port ${_MUNINN_REST_PORT})"
  else
    if [ "$server" = true ]; then
      warn "REST API: not responding (port ${_MUNINN_REST_PORT})"
    else
      fail "REST API: not running"
    fi
  fi

  # MCP token
  if [ "$token" = true ]; then
    ok "MCP token: configured"
  else
    warn "MCP token: not found in mcp.json"
    dim "Run: muninn init"
  fi

  # Vault
  if [ -n "$vault_name" ]; then
    if [ "$rest" = true ]; then
      local -a curl_args=( curl -sf --max-time 3 )
      [ -n "$tok" ] && curl_args+=( -H "Authorization: Bearer $tok" )
      if "${curl_args[@]}" http://localhost:${_MUNINN_REST_PORT}/api/vaults 2>/dev/null | jq -e --arg v "$vault_name" '.[] | select(.name == $v)' >/dev/null 2>&1; then
        ok "Vault: ${vault_name} (exists)"
      else
        warn "Vault: ${vault_name} (not found on server)"
      fi
    else
      dim "Vault: ${vault_name} (configured, server not running)"
    fi
  else
    dim "Vault: not configured (run /vbw:init)"
  fi

  # Overall
  echo ""
  if [ "$binary" = true ] && [ "$server" = true ] && [ "$token" = true ]; then
    ok "MuninnDB is fully operational"
    return 0
  fi
  return 1
}

# ============================================================
# Install binary
# ============================================================
install_binary() {
  if command -v muninn &>/dev/null; then
    local ver
    ver=$(muninn --version 2>/dev/null | head -1 || echo "unknown")
    ok "MuninnDB already installed (${ver})"
    return 0
  fi

  if ! command -v curl &>/dev/null; then
    fail "curl is required to install MuninnDB"
    dim "Install curl first: brew install curl (macOS) or apt install curl (Linux)"
    return 1
  fi

  echo ""
  dim "Will run: curl -fsSL https://muninndb.com/install.sh | sh"
  echo ""

  if ! confirm "Install MuninnDB?"; then
    dim "Skipped install"
    return 1
  fi

  echo ""
  info "Installing MuninnDB..."
  if curl -fsSL https://muninndb.com/install.sh | sh; then
    # Ensure common install paths are in PATH for this session
    for bindir in "$HOME/.local/bin" "$HOME/.muninn/bin" "/usr/local/bin"; do
      if [ -f "$bindir/muninn" ] && ! command -v muninn &>/dev/null; then
        export PATH="$bindir:$PATH"
        warn "Added $bindir to PATH for this session"
        dim "Add to your shell profile: export PATH=\"$bindir:\$PATH\""
      fi
    done

    if command -v muninn &>/dev/null; then
      local ver
      ver=$(muninn --version 2>/dev/null | head -1 || echo "unknown")
      ok "MuninnDB installed (${ver})"
      return 0
    else
      fail "MuninnDB binary not found after install"
      dim "Check the install output above for the binary location"
      dim "Then add it to your PATH and re-run this script"
      return 1
    fi
  else
    fail "Install script failed"
    dim "Try installing manually: https://muninndb.com"
    return 1
  fi
}

# ============================================================
# Initialize MCP config
# ============================================================
init_mcp() {
  local tok
  tok=$(_read_token)

  if [ -n "$tok" ]; then
    ok "MCP already configured (token present)"
    return 0
  fi

  if ! command -v muninn &>/dev/null; then
    fail "MuninnDB binary not found — install first"
    return 1
  fi

  echo ""
  dim "Will run: muninn init"
  dim "This configures Claude Code to use MuninnDB's MCP server"
  echo ""

  if ! confirm "Configure Claude Code MCP integration?"; then
    dim "Skipped MCP init"
    dim "Run later: muninn init"
    return 1
  fi

  echo ""
  if muninn init; then
    ok "MCP integration configured"
    return 0
  else
    fail "muninn init failed"
    dim "Try running manually: muninn init"
    return 1
  fi
}

# ============================================================
# Start server
# ============================================================
start_server() {
  if _health_ok; then
    ok "MuninnDB server already running"
    return 0
  fi

  if ! command -v muninn &>/dev/null; then
    fail "MuninnDB binary not found — install first"
    return 1
  fi

  info "Starting MuninnDB server..."
  if muninn start; then
    # Wait briefly for server to come up
    local retries=0
    while [ $retries -lt 10 ]; do
      if _health_ok; then
        ok "MuninnDB server started (MCP on ${_MUNINN_MCP_PORT}, REST on ${_MUNINN_REST_PORT})"
        return 0
      fi
      sleep 0.5
      retries=$((retries + 1))
    done
    fail "Server started but health check failed after 5s"
    dim "Check: muninn status"
    return 1
  else
    fail "muninn start failed (exit code $?)"
    dim "Check: muninn status"
    return 1
  fi
}

# ============================================================
# Create project vault
# ============================================================
setup_vault() {
  if ! _rest_ok; then
    fail "REST API not responding — start MuninnDB first"
    return 1
  fi

  local vault_name
  vault_name=$(_derive_vault_name)
  local tok
  tok=$(_read_token)
  local -a curl_auth=( curl -sf )
  [ -n "$tok" ] && curl_auth+=( -H "Authorization: Bearer $tok" )

  # Check if vault exists
  if "${curl_auth[@]}" --max-time 3 http://localhost:${_MUNINN_REST_PORT}/api/vaults 2>/dev/null | jq -e --arg v "$vault_name" '.[] | select(.name == $v)' >/dev/null 2>&1; then
    ok "Vault '${vault_name}' already exists"
  else
    dim "Creating vault: ${vault_name}"
    if "${curl_auth[@]}" --max-time 5 -X POST http://localhost:${_MUNINN_REST_PORT}/api/vaults \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$vault_name\"}" >/dev/null 2>&1; then
      ok "Vault '${vault_name}' created"
    else
      warn "Vault creation failed — will be created during /vbw:init"
    fi
  fi

  # Update config.json if it exists
  if [ -f ".vbw-planning/config.json" ]; then
    local current_vault
    current_vault=$(jq -r '.muninndb_vault // ""' .vbw-planning/config.json 2>/dev/null || true)
    if [ "$current_vault" != "$vault_name" ]; then
      if command -v jq &>/dev/null; then
        jq --arg v "$vault_name" '.muninndb_vault = $v' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
          && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
        ok "Config updated: muninndb_vault = ${vault_name}"
      fi
    fi
  fi
}

# ============================================================
# Main
# ============================================================

MODE="${1:-install}"

echo ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "MuninnDB Setup — Cognitive memory for VBW"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

case "$MODE" in
  --check|-c)
    check_status
    exit $?
    ;;

  --start|-s)
    start_server
    exit $?
    ;;

  --vault|-v)
    setup_vault
    exit $?
    ;;

  --help|-h)
    echo "Usage: bash scripts/muninn-setup.sh [MODE]"
    echo ""
    echo "Modes:"
    echo "  (default)    Full interactive install: binary + init + start + vault"
    echo "  --check      Check MuninnDB status (no changes)"
    echo "  --start      Start server only (binary must be installed)"
    echo "  --vault      Create/verify project vault only (server must be running)"
    echo "  --help       Show this help"
    echo ""
    echo "Ports:"
    echo "  ${_MUNINN_MCP_PORT}   MCP server (Claude Code integration)"
    echo "  ${_MUNINN_REST_PORT}   REST API (engram management)"
    echo "  8476   Web UI"
    echo ""
    exit 0
    ;;

  install|*)
    # Prerequisites
    if ! command -v curl &>/dev/null; then
      fail "curl is required"
      dim "Install: brew install curl (macOS) or apt install curl (Linux)"
      exit 1
    fi
    if ! command -v jq &>/dev/null; then
      fail "jq is required"
      dim "Install: brew install jq (macOS) or apt install jq (Linux)"
      exit 1
    fi

    # Already fully set up?
    if check_status 2>/dev/null; then
      echo ""
      ok "Nothing to do — MuninnDB is already fully configured"
      exit 0
    fi

    echo ""

    # Step 1: Install binary
    install_binary || {
      echo ""
      fail "Cannot proceed without MuninnDB binary"
      exit 1
    }

    echo ""

    # Step 2: Initialize MCP
    init_mcp || true

    echo ""

    # Step 3: Start server
    start_server || {
      echo ""
      warn "Server not running — some features will be unavailable"
      dim "Start manually: muninn start"
    }

    echo ""

    # Step 4: Create vault (if in a project)
    if [ -d ".git" ] || [ -f ".vbw-planning/config.json" ]; then
      setup_vault || true
    else
      dim "Not in a git repo — skip vault setup (run /vbw:init for vault creation)"
    fi

    # Final status
    echo ""
    info "━━━ Setup Complete ━━━"
    echo ""
    check_status || true

    echo ""
    dim "Next: run /vbw:init to set up your project with MuninnDB"
    ;;
esac
