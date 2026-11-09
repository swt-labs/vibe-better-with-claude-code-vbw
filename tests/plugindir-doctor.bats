#!/usr/bin/env bats
# R185: vbw --version prints the version of the plugin the kernel belongs to,
# like vbw version. vbw doctor shows which vbw is on PATH (its path and
# version) and which plugin is loaded, and warns with the fix when they differ.
# The loaded plugin is the one the session's SessionStart hook recorded for
# its session (CLAUDE_CODE_SESSION_ID, as Claude Code sets it for the Bash
# tool), else the plugin of the kernel running doctor (/vbw:doctor runs the
# loaded plugin's own kernel). L1: the installed release is a stand-in kernel
# in a plugin cache under the test's Claude config folder; the loaded copy is
# the plugin under test, started the way claude --plugin-dir starts it.

load helper

setup() {
  vbw_setup
  vbw_git_project
  INST="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.9"
  mkdir -p "$INST/bin"
  cat > "$INST/bin/vbw" << 'EOF'
#!/bin/sh
case "${1:-}" in
  version | --version) echo 9.9.9 ;;
  *) echo "vbw: installed stand-in" >&2; exit 1 ;;
esac
EOF
  chmod +x "$INST/bin/vbw"
  mkdir -p "$INST/.claude-plugin"
  printf '{"name": "vbw", "version": "9.9.9"}\n' > "$INST/.claude-plugin/plugin.json"
  TREE_VERSION=$(jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  # The host may have VBW on PATH (a test run from inside a Claude Code
  # session): start from a PATH without any vbw.
  CLEAN_PATH=""
  local p
  while IFS= read -r p; do
    [ -n "$p" ] && [ ! -x "$p/vbw" ] && CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$p"
  done < <(printf '%s\n' "$PATH" | tr ':' '\n')
  export PATH="$CLEAN_PATH"
  unset CLAUDE_CODE_SESSION_ID
}

teardown() { vbw_teardown; }

# loaded_session SID: the plugin under test starts session SID as a copy
# loaded with --plugin-dir (Claude Code names it vbw@inline, so its hooks get a
# plugin data folder named vbw-inline).
loaded_session() {
  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json")
  mkdir -p "$TEST_ROOT/session"
  jq -nc --arg d "$PROJECT" --arg s "$1" '{hook_event_name: "SessionStart", source: "startup", session_id: $s, cwd: $d}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$PROJECT" CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugins/data/vbw-inline" \
      CLAUDE_ENV_FILE="$TEST_ROOT/session/env.sh" sh -c "$cmd" > /dev/null
}

# doctor_lines MARK: doctor's lines that start with MARK (✓ ok, ! warn), each
# followed by its fix line when it has one.
doctor_lines() {
  printf '%s\n' "$output" | awk -v m="$1" 'index($0, m " ") == 1 { keep = 1; print; next } /^    fix: / && keep { print; next } { keep = 0 }'
}

@test "R185: vbw --version prints the plugin's version, as vbw version does, in and outside a project" {
  run "$VBW" --version < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "$TREE_VERSION" ]
  cd "$TEST_ROOT"
  run "$VBW" --version < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "$TREE_VERSION" ]
  [ "$("$VBW" version)" = "$output" ]
}

@test "R185: vbw doctor says the vbw on PATH is the loaded plugin's, with its path and version" {
  loaded_session s1
  PATH="$PLUGIN_ROOT/bin:$PATH" CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  local ok
  ok=$(doctor_lines "✓")
  printf '%s\n' "$ok" | grep -F "$PLUGIN_ROOT/bin/vbw" | grep -qF "$TREE_VERSION" || {
    echo "no ok line names $PLUGIN_ROOT/bin/vbw and version $TREE_VERSION:"
    printf '%s\n' "$output"
    false
  }
  if printf '%s\n' "$output" | grep -E '^! ' | grep -qF "$INST"; then
    echo "a warning names the installed release:"
    printf '%s\n' "$output"
    false
  fi
}

@test "R185: in a session that loaded a working tree, an installed release first on PATH is a warning, with the fix naming the loaded kernel" {
  loaded_session s1
  PATH="$INST/bin:$PLUGIN_ROOT/bin:$PATH" CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  local warn
  warn=$(doctor_lines "!")
  printf '%s\n' "$warn" | grep -E '^! ' | grep -F "$INST/bin/vbw" | grep -qF "$PLUGIN_ROOT" || {
    echo "no warning names both the vbw on PATH ($INST/bin/vbw) and the loaded plugin ($PLUGIN_ROOT):"
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$warn" | grep -E '^    fix: ' | grep -qF "$PLUGIN_ROOT/bin/vbw" || {
    echo "no fix names $PLUGIN_ROOT/bin/vbw:"
    printf '%s\n' "$output"
    false
  }
  # The version of each is shown.
  printf '%s\n' "$warn" | grep -qF 9.9.9
}

@test "R185 (R285): outside a Claude Code session doctor names the vbw on PATH and compares it with nothing, never with the kernel it runs from" {
  PATH="$INST/bin:$PATH" run "$VBW" doctor < /dev/null
  printf '%s\n' "$output" | grep -F "$INST/bin/vbw" | grep -qF 'no Claude Code session to compare with' || {
    echo "no line names $INST/bin/vbw with no session to compare with:"
    printf '%s\n' "$output"
    false
  }
  ! doctor_lines "!" | grep -qF "$PLUGIN_ROOT" || { echo "doctor compared with the kernel it runs from:"; printf '%s\n' "$output"; false; }
}

@test "R185: no vbw on PATH at all is a warning too, with the fix naming the loaded kernel" {
  loaded_session s1
  CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  local warn
  warn=$(doctor_lines "!")
  printf '%s\n' "$warn" | grep -E '^! ' | grep -F 'PATH' | grep -qF 'vbw' || {
    echo "no warning about vbw missing from PATH:"
    printf '%s\n' "$output"
    false
  }
  printf '%s\n' "$warn" | grep -E '^    fix: ' | grep -qF "$PLUGIN_ROOT/bin/vbw"
}

@test "R185: a session id that is not a plain name finds no record: doctor ignores a file the id points at" {
  # The id "../rec" would name $CLAUDE_CONFIG_DIR/vbw/rec, a file that holds the installed release's folder.
  mkdir -p "$CLAUDE_CONFIG_DIR/vbw/sessions"
  printf '%s\n' "$INST" > "$CLAUDE_CONFIG_DIR/vbw/rec"
  PATH="$INST/bin:$PATH" CLAUDE_CODE_SESSION_ID="../rec" run "$VBW" doctor < /dev/null
  # R285: no record for the id, so doctor says it cannot tell which copy this session loaded.
  doctor_lines "!" | grep -E '^! ' | grep -qF 'cannot tell which copy this session loaded' && ! printf '%s\n' "$output" | grep -F "$INST" | grep -vqF 'vbw on PATH is' || {
    echo "doctor followed the id out of the sessions folder:"
    printf '%s\n' "$output"
    false
  }
}

@test "R185: the plain-name rule for a session id reads the same in the hook, the status line and the shared function" {
  local f
  for f in "$PLUGIN_ROOT/hooks/session-start.sh" "$PLUGIN_ROOT/scripts/vbw-statusline.sh" "$PLUGIN_ROOT/lib/sessions.sh"; do
    grep -qF '^[A-Za-z0-9_-]+$' "$f" || {
      echo "$f does not carry the rule ^[A-Za-z0-9_-]+\$"
      false
    }
  done
}

# R285 (D686): doctor compares the vbw on PATH with the copy Claude Code loaded for this
# session, which the session start records for an installed start too, never with the
# kernel doctor runs from. L1: an installed release that is a full copy of the plugin
# under test (version 9.9.8) starts session s1 as Claude Code starts an installed copy.
installed_session() {
  REAL="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.8"
  mkdir -p "$(dirname "$REAL")"
  cp -R "$PLUGIN_ROOT" "$REAL"
  jq '.version = "9.9.8"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" > "$REAL/.claude-plugin/plugin.json"
  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$REAL/hooks/hooks.json")
  mkdir -p "$TEST_ROOT/session"
  jq -nc --arg d "$PROJECT" --arg s "$1" '{hook_event_name: "SessionStart", source: "resume", session_id: $s, cwd: $d}' \
    | CLAUDE_PLUGIN_ROOT="$REAL" CLAUDE_PROJECT_DIR="$PROJECT" CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugins/data/vbw-vbw-marketplace" \
      CLAUDE_ENV_FILE="$TEST_ROOT/session/env.sh" sh -c "$cmd" > /dev/null
}

@test "R285 doctor: after an installed start, the installed copy's vbw first on PATH is ok, though doctor runs from another kernel" {
  installed_session s1
  PATH="$REAL/bin:$PATH" CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  doctor_lines "✓" | grep -F "$REAL/bin/vbw" | grep -qF 9.9.8 || { echo "no ok line for $REAL/bin/vbw:"; printf '%s\n' "$output"; false; }
  ! printf '%s\n' "$output" | grep -E '^! ' | grep -qF 'vbw on PATH' || { echo "a PATH warning:"; printf '%s\n' "$output"; false; }
}

@test "R285 doctor: after an installed start, a stale working tree first on PATH is a warning naming both folders and the fix: start or resume the session again" {
  installed_session s1
  PATH="$PLUGIN_ROOT/bin:$REAL/bin:$PATH" CLAUDE_CODE_SESSION_ID=s1 run "$VBW" doctor < /dev/null
  local warn
  warn=$(doctor_lines "!")
  printf '%s\n' "$warn" | grep -E '^! ' | grep -F "$PLUGIN_ROOT/bin/vbw" | grep -qF "$REAL" || { echo "no warning names both folders:"; printf '%s\n' "$output"; false; }
  printf '%s\n' "$warn" | grep -E '^    fix: ' | grep -qF 'start or resume the session again' || { echo "no fix to start or resume the session:"; printf '%s\n' "$output"; false; }
}

@test "R285 doctor: a session id with no record says doctor cannot tell which copy the session loaded, with the fix, instead of comparing with itself" {
  PATH="$INST/bin:$PATH" CLAUDE_CODE_SESSION_ID=s9 run "$VBW" doctor < /dev/null
  local warn
  warn=$(doctor_lines "!")
  printf '%s\n' "$warn" | grep -E '^! ' | grep -F "$INST/bin/vbw" | grep -qF 'cannot tell which copy this session loaded' || { printf '%s\n' "$output"; false; }
  printf '%s\n' "$warn" | grep -E '^    fix: ' | grep -qF 'start or resume the session again' || { printf '%s\n' "$output"; false; }
  ! printf '%s\n' "$warn" | grep -qF "$PLUGIN_ROOT" || { echo "doctor compared with the kernel it runs from:"; printf '%s\n' "$output"; false; }
}
