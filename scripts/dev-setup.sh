#!/usr/bin/env bash
set -euo pipefail

# VBW Local Development Setup
# Sets up (or tears down) the local dev environment for contributing to VBW.
#
# Usage:
#   bash scripts/dev-setup.sh              # set up local dev
#   bash scripts/dev-setup.sh --teardown   # revert to marketplace
#   bash scripts/dev-setup.sh --status     # check current state
#
# Setup must be run from the root of the VBW clone.
# --teardown and --status work from any directory.

# ---------- constants ----------

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CACHE_BASE="$CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw"
SYMLINK_PATH="$CACHE_BASE/local"
COMMANDS_CACHE="$CLAUDE_DIR/commands/vbw"
LOCAL_BIN="$HOME/.local/bin"
LAUNCHER_LINK="$LOCAL_BIN/claude-vbw"

# ---------- helpers ----------

info()  { echo "[info]  $*"; }
ok()    { echo "[ok]    $*"; }
warn()  { echo "[warn]  $*"; }
err()   { echo "[error] $*" >&2; }
step()  { printf '\n--- %s ---\n' "$*"; }

check_clone_root() {
  if [ ! -f "plugin.json" ] && [ ! -f ".claude-plugin/plugin.json" ]; then
    err "Not in the VBW repo root. Run this from the cloned directory."
    err "  cd /path/to/vibe-better-with-claude-code-vbw && bash scripts/dev-setup.sh"
    exit 1
  fi
}

# ---------- status ----------

do_status() {
  step "VBW dev environment status"

  # Symlink
  if [ -L "$SYMLINK_PATH" ]; then
    local target
    target=$(readlink "$SYMLINK_PATH")
    ok "Cache symlink exists: $SYMLINK_PATH -> $target"
  elif [ -e "$SYMLINK_PATH" ]; then
    warn "Cache path exists but is NOT a symlink: $SYMLINK_PATH"
  else
    info "No cache symlink at $SYMLINK_PATH (marketplace mode)"
  fi

  # Command cache
  if [ -d "$COMMANDS_CACHE" ]; then
    warn "Command cache exists at $COMMANDS_CACHE (may shadow local commands)"
  else
    ok "No stale command cache"
  fi

  # Glob check
  local glob_result
  glob_result=$(compgen -G "$CACHE_BASE/*/scripts/hook-wrapper.sh" || true)
  if [ -n "$glob_result" ]; then
    ok "Plugin root glob resolves: $glob_result"
  else
    warn "Plugin root glob does NOT resolve — hooks and scripts will fail at runtime"
  fi

  # Git hooks
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$repo_root" ] && [ -f "$repo_root/.git/hooks/pre-push" ] && grep -q "VBW pre-push hook" "$repo_root/.git/hooks/pre-push" 2>/dev/null; then
    ok "Git pre-push hook installed"
  else
    info "Git pre-push hook not installed (optional)"
  fi

  # Launcher
  if [ -L "$LAUNCHER_LINK" ]; then
    local launcher_target
    launcher_target=$(readlink "$LAUNCHER_LINK")
    ok "claude-vbw launcher installed: $LAUNCHER_LINK -> $launcher_target"
  elif [ -f "$LAUNCHER_LINK" ]; then
    warn "claude-vbw exists but is not a symlink: $LAUNCHER_LINK"
  else
    info "claude-vbw launcher not installed (optional)"
  fi

  echo ""
}

# ---------- setup ----------

do_setup() {
  local clone
  clone=$(pwd -P)

  step "1/6  Checking prerequisites"
  check_clone_root

  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code CLI found"
  else
    warn "Claude Code CLI not found in PATH — install it before testing"
  fi

  step "2/6  Clearing stale command cache"
  if [ -d "$COMMANDS_CACHE" ]; then
    rm -rf "$COMMANDS_CACHE"
    ok "Removed $COMMANDS_CACHE"
  else
    ok "No stale command cache to clean"
  fi

  step "3/6  Setting up plugin cache symlink"
  mkdir -p "$CACHE_BASE"

  # Remove any versioned directories from prior marketplace installs.
  # Only targets direct children of the VBW-specific cache path, so this
  # is safe — the new "local" symlink replaces them.
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    rm -rf "$entry"
    ok "Removed old cache entry: $(basename "$entry")"
  done < <(find "$CACHE_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

  # Remove existing symlink (broken or pointing elsewhere)
  if [ -L "$SYMLINK_PATH" ]; then
    rm "$SYMLINK_PATH"
  fi

  ln -s "$clone" "$SYMLINK_PATH"
  ok "Symlink created: $SYMLINK_PATH -> $clone"

  step "4/6  Verifying setup"

  # Show symlink details (like the old manual ls -la check)
  info "Cache directory contents:"
  ls -la "$CACHE_BASE"/
  echo ""

  # Verify the glob resolves (like the old manual hook-wrapper.sh check)
  local glob_result
  glob_result=$(compgen -G "$CACHE_BASE/*/scripts/hook-wrapper.sh" || true)
  if [ -n "$glob_result" ]; then
    ok "Plugin root glob resolves: $glob_result"
  else
    err "Glob does NOT resolve — something went wrong with the symlink"
    exit 1
  fi

  step "5/6  Installing git pre-push hook"
  if [ -f "scripts/install-hooks.sh" ]; then
    bash scripts/install-hooks.sh
    ok "Git hooks installed"
  else
    warn "scripts/install-hooks.sh not found — skipping"
  fi

  step "6/6  claude-vbw launcher (optional)"
  local launcher_script="$clone/scripts/dev-launch.sh"
  if [ -f "$launcher_script" ]; then
    local install_launcher="n"
    printf 'Install claude-vbw command to launch Claude Code with local VBW from anywhere? [y/N] '
    read -r install_launcher
    if [ "$install_launcher" = "y" ] || [ "$install_launcher" = "Y" ]; then
      mkdir -p "$LOCAL_BIN"

      # Remove existing link (broken or pointing elsewhere)
      if [ -L "$LAUNCHER_LINK" ]; then
        rm "$LAUNCHER_LINK"
      fi

      ln -s "$launcher_script" "$LAUNCHER_LINK"
      ok "Installed: $LAUNCHER_LINK -> $launcher_script"

      # Check if ~/.local/bin is in PATH
      if ! echo "$PATH" | tr ':' '\n' | grep -qxF "$LOCAL_BIN"; then
        warn "$LOCAL_BIN is not in your PATH"
        info "Add it to your shell profile:"
        info "  bash/zsh: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        info "  fish:     fish_add_path ~/.local/bin"
      else
        ok "$LOCAL_BIN is in PATH — claude-vbw is ready to use"
      fi
    else
      ok "Skipped — you can always install it later with:"
      info "  ln -s $launcher_script $LAUNCHER_LINK"
    fi
  else
    warn "scripts/dev-launch.sh not found — skipping launcher install"
  fi

  # ---------- summary ----------

  echo ""
  echo "Local dev environment ready."
  echo ""
  echo "Launch Claude Code with your local VBW:"
  echo ""
  if [ -L "$LAUNCHER_LINK" ]; then
    echo "  claude-vbw                             # from anywhere (uses local VBW)"
  fi
  echo "  claude --plugin-dir .                  # from this repo"
  echo "  claude --plugin-dir $clone   # explicit absolute path"
  echo ""
  echo "All /vbw:* commands will load from your local copy."
  echo "Restart Claude Code to pick up changes after editing VBW files."
  echo ""
  echo "To revert:  bash scripts/dev-setup.sh --teardown"
  echo ""
}

# ---------- teardown ----------

do_teardown() {
  step "1/4  Removing plugin cache symlink"
  if [ -L "$SYMLINK_PATH" ]; then
    rm "$SYMLINK_PATH"
    ok "Removed symlink: $SYMLINK_PATH"
  elif [ -e "$SYMLINK_PATH" ]; then
    warn "$SYMLINK_PATH exists but is not a symlink — removing anyway"
    rm -rf "$SYMLINK_PATH"
    ok "Removed $SYMLINK_PATH"
  else
    ok "No symlink to remove"
  fi

  step "2/4  Clearing command cache"
  if [ -d "$COMMANDS_CACHE" ]; then
    rm -rf "$COMMANDS_CACHE"
    ok "Removed $COMMANDS_CACHE"
  else
    ok "No command cache to clean"
  fi

  step "3/4  Removing git pre-push hook"
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$repo_root" ] && [ -f "$repo_root/.git/hooks/pre-push" ] && grep -q "VBW pre-push hook" "$repo_root/.git/hooks/pre-push" 2>/dev/null; then
    rm "$repo_root/.git/hooks/pre-push"
    ok "Removed VBW pre-push hook"
  else
    ok "No VBW pre-push hook to remove"
  fi

  step "4/4  Removing claude-vbw launcher"
  if [ -L "$LAUNCHER_LINK" ] || [ -f "$LAUNCHER_LINK" ]; then
    rm -f "$LAUNCHER_LINK"
    ok "Removed $LAUNCHER_LINK"
  else
    ok "No claude-vbw launcher to remove"
  fi

  # ---------- summary ----------

  echo ""
  echo "Local dev environment removed."
  echo ""
  echo "To reinstall VBW from the marketplace, start Claude Code and run:"
  echo ""
  echo "  /plugin marketplace add yidakee/vibe-better-with-claude-code-vbw"
  echo "  /plugin install vbw@vbw-marketplace"
  echo ""
}

# ---------- main ----------

case "${1:-}" in
  --teardown) do_teardown ;;
  --status)   do_status ;;
  -h|--help)
    echo "Usage: bash scripts/dev-setup.sh [--teardown|--status|--help]"
    echo ""
    echo "  (no args)    Set up local dev environment"
    echo "  --teardown   Revert to marketplace VBW"
    echo "  --status     Check current environment state"
    echo "  --help       Show this help"
    ;;
  "")         do_setup ;;
  *)
    err "Unknown option: $1"
    echo "Usage: bash scripts/dev-setup.sh [--teardown|--status|--help]"
    exit 1
    ;;
esac
