#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*vbw-zsh-*' -exec rm -f {} + 2>/dev/null || true
  teardown_temp_dir
}

@test "plugin root resolver is zsh-safe when the exact session link is absent" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

  local zsh_script
  zsh_script=$(cat <<'EOF'
setopt nomatch
SESSION_KEY="vbw-zsh-no-match-$$"
SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
rm -f "$SESSION_LINK"
R=""
if [ -z "$R" ] && [ -f "${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then
  R="${SESSION_LINK}"
fi
if [ -z "$R" ]; then
  ANY_LINK=$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "$link/scripts/hook-wrapper.sh" ]; then printf '%s\n' "$link"; break; fi; done || true)
  if [ -n "$ANY_LINK" ] && [ -f "$ANY_LINK/scripts/hook-wrapper.sh" ]; then
    R="$ANY_LINK"
  fi
fi
print -r -- "$R"
EOF
)

  run zsh -fc "$zsh_script"

  [ "$status" -eq 0 ]
  [[ "$output" != *"no matches found"* ]]
}

@test "plugin root resolver prefers the exact session link under zsh" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

  local plugin_root="$TEST_TEMP_DIR/plugin-root"
  local session_key="vbw-zsh-exact-$$"
  local session_link="/tmp/.vbw-plugin-root-link-${session_key}"
  mkdir -p "$plugin_root/scripts"
  : > "$plugin_root/scripts/hook-wrapper.sh"
  ln -sf "$plugin_root" "$session_link"

  local zsh_script
  zsh_script=$(cat <<EOF
setopt nomatch
SESSION_KEY="${session_key}"
SESSION_LINK="${session_link}"
R=""
if [ -z "\$R" ] && [ -f "\${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then
  R="\${SESSION_LINK}"
fi
if [ -z "\$R" ]; then
  ANY_LINK=\$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "\$link/scripts/hook-wrapper.sh" ]; then printf '%s\\n' "\$link"; break; fi; done || true)
  if [ -n "\$ANY_LINK" ] && [ -f "\$ANY_LINK/scripts/hook-wrapper.sh" ]; then
    R="\$ANY_LINK"
  fi
fi
print -r -- "\$R"
EOF
)

  run zsh -fc "$zsh_script"

  [ "$status" -eq 0 ]
  [ "$output" = "$session_link" ]
}

@test "plugin root resolver skips stale symlinks before choosing a valid fallback under zsh" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"

  local stale_link="/tmp/.vbw-plugin-root-link-+000-vbw-zsh-stale-$$"
  local valid_root="$TEST_TEMP_DIR/fallback-root"
  local valid_link="/tmp/.vbw-plugin-root-link-+001-vbw-zsh-valid-$$"
  mkdir -p "$valid_root/scripts"
  : > "$valid_root/scripts/hook-wrapper.sh"
  ln -sf "/nonexistent/vbw-zsh-stale-$$" "$stale_link"
  ln -sf "$valid_root" "$valid_link"

  local zsh_script
  zsh_script=$(cat <<EOF
setopt nomatch
SESSION_KEY="vbw-zsh-scan-$$"
SESSION_LINK="/tmp/.vbw-plugin-root-link-\${SESSION_KEY}"
R=""
if [ -z "\$R" ] && [ -f "\${SESSION_LINK}/scripts/hook-wrapper.sh" ]; then
  R="\${SESSION_LINK}"
fi
if [ -z "\$R" ]; then
  ANY_LINK=\$(command find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*' -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r link; do if [ -f "\$link/scripts/hook-wrapper.sh" ]; then printf '%s\\n' "\$link"; break; fi; done || true)
  if [ -n "\$ANY_LINK" ]; then
    R="\$ANY_LINK"
  fi
fi
print -r -- "\$R"
EOF
)

  run zsh -fc "$zsh_script"

  [ "$status" -eq 0 ]
  [ "$output" = "$valid_link" ]
}