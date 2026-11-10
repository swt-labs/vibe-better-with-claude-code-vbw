#!/usr/bin/env bats
# R185: a session that loads VBW from a working tree (claude --plugin-dir) runs
# that tree's kernel. Claude Code names such a plugin <name>@inline, so the
# hooks of the loaded copy get a CLAUDE_PLUGIN_DATA folder named vbw-inline;
# an installed copy gets vbw-vbw-marketplace. The SessionStart hook of a
# loaded copy writes to CLAUDE_ENV_FILE (the file Claude Code reads before each
# Bash tool command) what puts its own bin/ first on PATH, ahead of an
# installed release the session inherited; an installed copy writes nothing
# there, so a normal session keeps Claude Code's own order. In a VBW project
# the session's one line names the kernel in use, its path and version. When
# the file cannot be written, the session is told once, with the exact path.
# The hooks reach the kernel through their own plugin folder, never through
# PATH, so an approval is recorded by the loaded kernel even when an installed
# release that cannot read the record comes first on PATH.
# L1: the installed release is a stand-in kernel in a plugin cache under the
# test's Claude config folder; the Bash tool is a shell (sh, bash, zsh) that
# reads the env file, as Claude Code does.

load helper
load approve-choice-helper

setup() {
  vbw_setup
  INST="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.9"
  mkdir -p "$INST/bin"
  # The installed release: it says its version, and refuses every project
  # command the way an older kernel refuses a record holding a field it does not
  # know. Every call is logged.
  cat > "$INST/bin/vbw" << 'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$INSTALLED_LOG"
case "${1:-}" in
  version | --version) echo 9.9.9 ;;
  *) echo "vbw: .vbw/record.json is not a valid record: unknown key: newer_field" >&2; exit 1 ;;
esac
EOF
  chmod +x "$INST/bin/vbw"
  INSTALLED_LOG="$TEST_ROOT/installed.log"
  : > "$INSTALLED_LOG"
  export INSTALLED_LOG
  TREE_VERSION=$(jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json")
  mkdir -p "$TEST_ROOT/session"
  export CLAUDE_ENV_FILE="$TEST_ROOT/session/env.sh"
}

teardown() { vbw_teardown; }

# loaded / installed: the plugin data folder Claude Code gives the hooks of a
# copy loaded with --plugin-dir (vbw@inline), or of the installed one.
loaded() { export CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugins/data/vbw-inline"; }
installed() { export CLAUDE_PLUGIN_DATA="$TEST_ROOT/plugins/data/vbw-vbw-marketplace"; }

# session_start [ROOT]: the SessionStart hook of the plugin at ROOT (default
# the plugin under test), as Claude Code runs it at startup of session s1.
session_start() {
  local root="${1:-$PLUGIN_ROOT}" cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$root/hooks/hooks.json")
  jq -nc --arg d "$PROJECT" '{hook_event_name: "SessionStart", source: "startup", session_id: "s1", cwd: $d}' \
    | CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$PROJECT" sh -c "$cmd"
}

# bash_tool SHELL COMMAND: COMMAND as the Bash tool runs it: the session
# inherited a PATH with the installed release first, then the env file is read.
bash_tool() {
  local env_file=/dev/null
  [ ! -f "$CLAUDE_ENV_FILE" ] || env_file=$CLAUDE_ENV_FILE
  env PATH="$INST/bin:$PATH" "$1" -c '. "$1"; '"$2" bash_tool "$env_file"
}

# shells: the shells the Bash tool may use here (zsh only where installed).
shells() {
  printf 'sh\nbash\n'
  command -v zsh > /dev/null 2>&1 && printf 'zsh\n'
  return 0
}

context() { printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""'; }

# vbw_path_lines: the env file's PATH lines that put a VBW copy's bin folder first (a folder holding vbw).
vbw_path_lines() {
  local l d
  [ -f "$CLAUDE_ENV_FILE" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    case $l in
      "export PATH='"*) d=${l#"export PATH='"}; d=${d%%"'"*}; [ ! -x "$d/vbw" ] || printf '%s\n' "$l" ;;
    esac
  done < "$CLAUDE_ENV_FILE"
}

@test "R185: a session that loaded VBW from a working tree runs that tree's vbw, ahead of an installed release" {
  vbw_git_project
  "$VBW" init > /dev/null
  loaded
  run session_start
  [ "$status" -eq 0 ]
  local sh got
  while IFS= read -r sh; do
    got=$(bash_tool "$sh" 'command -v vbw')
    [ "$got" = "$PLUGIN_ROOT/bin/vbw" ] || {
      echo "$sh: vbw is $got, not $PLUGIN_ROOT/bin/vbw"
      echo "env file:"
      cat "$CLAUDE_ENV_FILE" 2> /dev/null || echo "(none written)"
      false
    }
    got=$(bash_tool "$sh" 'vbw version')
    [ "$got" = "$TREE_VERSION" ] || {
      echo "$sh: vbw version printed $got, not $TREE_VERSION"
      false
    }
  done < <(shells)
  [ ! -s "$INSTALLED_LOG" ] || {
    echo "the installed release ran:"
    cat "$INSTALLED_LOG"
    false
  }
}

@test "R185: the same holds outside a VBW project and with the installed VBW turned off for the project" {
  vbw_git_project
  mkdir -p .claude
  jq -n '{enabledPlugins: {"vbw@vbw-marketplace": false}}' > .claude/settings.json
  loaded
  run session_start
  [ "$status" -eq 0 ]
  [ "$(bash_tool bash 'command -v vbw')" = "$PLUGIN_ROOT/bin/vbw" ]
}

@test "R185: the env file keeps what it held, and a working tree whose path has a space and a quote is put first whole" {
  vbw_git_project
  local tree="$TEST_ROOT/it's my tree/plugin"
  mkdir -p "$(dirname "$tree")"
  cp -R "$PLUGIN_ROOT" "$tree"
  printf 'export OTHER_PLUGIN=1\n' > "$CLAUDE_ENV_FILE"
  loaded
  run session_start "$tree"
  [ "$status" -eq 0 ]
  grep -qx 'export OTHER_PLUGIN=1' "$CLAUDE_ENV_FILE"
  local sh
  while IFS= read -r sh; do
    [ "$(bash_tool "$sh" 'command -v vbw')" = "$tree/bin/vbw" ] || {
      echo "$sh: vbw is $(bash_tool "$sh" 'command -v vbw')"
      cat "$CLAUDE_ENV_FILE"
      false
    }
    [ "$(bash_tool "$sh" 'echo "$OTHER_PLUGIN"')" = 1 ]
  done < <(shells)
}

@test "R185 (R285): an installed session puts its own copy's bin first on PATH, one line in the env file" {
  vbw_git_project
  "$VBW" init > /dev/null
  installed
  run session_start
  [ "$status" -eq 0 ]
  [ "$(vbw_path_lines | wc -l | tr -d ' ')" = 1 ] && vbw_path_lines | grep -qF "$PLUGIN_ROOT/bin" || {
    echo "the installed copy did not write its one PATH line:"
    cat "$CLAUDE_ENV_FILE" 2> /dev/null
    false
  }
  # Its line keeps the words a normal session always had.
  [[ "$(context)" == *"Continue with /vbw:vibe"* ]]
}

@test "R185: in a VBW project the session's one line names the kernel in use, its path and its version" {
  vbw_git_project
  "$VBW" init > /dev/null
  loaded
  run session_start
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(context)
  [[ "$ctx" == *"$PLUGIN_ROOT/bin/vbw"* ]] || {
    echo "the line does not name $PLUGIN_ROOT/bin/vbw: $ctx"
    false
  }
  [[ "$ctx" == *"$TREE_VERSION"* ]] || {
    echo "the line does not name version $TREE_VERSION: $ctx"
    false
  }
  [[ "$ctx" == *"Continue with /vbw:vibe"* ]]
  [ "$(printf '%s' "$ctx" | wc -l | tr -d ' ')" -eq 0 ] || {
    echo "more than one line: $ctx"
    false
  }
}

@test "R185: when the env file cannot be written, the session is told once, naming the exact kernel path to use" {
  vbw_git_project
  "$VBW" init > /dev/null
  loaded
  local f
  for f in unset directory; do
    case "$f" in
      unset) unset CLAUDE_ENV_FILE ;;
      directory) export CLAUDE_ENV_FILE="$TEST_ROOT/session" ;;
    esac
    run session_start
    [ "$status" -eq 0 ]
    # One answer, one message for the user, both naming the path.
    [ "$(printf '%s\n' "$output" | jq -s 'length')" -eq 1 ]
    [[ "$(printf '%s' "$output" | jq -r '.systemMessage // ""')" == *"$PLUGIN_ROOT/bin/vbw"* ]] || {
      echo "$f: no message naming $PLUGIN_ROOT/bin/vbw: $output"
      false
    }
    [[ "$(context)" == *"$PLUGIN_ROOT/bin/vbw"* ]] || {
      echo "$f: Claude is not told $PLUGIN_ROOT/bin/vbw: $output"
      false
    }
  done
}

@test "R185: an approval answered in the menu is recorded by the loaded kernel, with an installed release that cannot read the record first on PATH" {
  approve_choice_project
  loaded
  run session_start
  local fp
  fp=$(fingerprint)
  [ "$(contract_state)" = "NOT APPROVED" ]
  PATH="$INST/bin:$PATH" run answer_hook "Approve contract $fp?" Approve
  [ "$status" -eq 0 ]
  [ "$(contract_state)" = approved ] || {
    echo "not approved: $output"
    false
  }
  [ ! -s "$INSTALLED_LOG" ] || {
    echo "the installed release ran:"
    cat "$INSTALLED_LOG"
    false
  }
}

@test "R185: with an installed release first on PATH, VBW's hooks (session start, approval menu, guards) never run it" {
  approve_choice_project
  loaded
  local fp q
  fp=$(fingerprint)
  PATH="$INST/bin:$PATH" run session_start
  [ "$status" -eq 0 ]
  [[ "$(context)" == *"Continue with /vbw:vibe"* ]] || {
    echo "the session start did not read the project: $output"
    false
  }
  # The approval menu: the hook names the contract waiting for approval.
  output=$(jq -nc --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "AskUserQuestion",
    tool_input: {questions: [{question: "Approve?", header: "Approval", multiSelect: false,
      options: [{label: "Approve", description: "x"}, {label: "Not yet", description: "x"}]}]}}' \
    | PATH="$INST/bin:$PATH" vbw_hook PreToolUse AskUserQuestion)
  q=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.questions[0].question // ""')
  [[ "$q" == "Approve contract $fp? "* ]] || {
    echo "the approval menu hook did not name contract $fp: $output"
    false
  }
  # The guards.
  jq -nc --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash", tool_input: {command: "git reset --hard"}}' \
    | PATH="$INST/bin:$PATH" vbw_hook PreToolUse Bash > /dev/null
  jq -nc --arg d "$PROJECT" --arg p "$PROJECT/src/pay.txt" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Edit", tool_input: {file_path: $p}}' \
    | PATH="$INST/bin:$PATH" vbw_hook PreToolUse Edit > /dev/null
  [ ! -s "$INSTALLED_LOG" ] || {
    echo "the installed release ran:"
    cat "$INSTALLED_LOG"
    false
  }
}

@test "R185: the unwritable-env-file warning survives a VBW 1 command copy removal and a project made by a newer VBW" {
  vbw_git_project
  "$VBW" init > /dev/null
  loaded
  unset CLAUDE_ENV_FILE
  # (1) a VBW 1 command copy in the Claude config folder is removed at start.
  mkdir -p "$CLAUDE_CONFIG_DIR/commands/vbw"
  printf -- '---\nname: vbw:old\n---\nold\n' > "$CLAUDE_CONFIG_DIR/commands/vbw/old.md"
  run session_start
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_CONFIG_DIR/commands/vbw/old.md" ]
  [[ "$(context)" == *"$PLUGIN_ROOT/bin/vbw"* ]] || { echo "context lost the kernel path: $output"; false; }
  [[ "$(printf '%s' "$output" | jq -r '.systemMessage // ""')" == *"$PLUGIN_ROOT/bin/vbw"* ]] || { echo "$output"; false; }
  # (2) a record newer than the kernel.
  jq '.schema = 99' .vbw/record.json > "$TEST_ROOT/newer.json" && cp "$TEST_ROOT/newer.json" .vbw/record.json
  run session_start
  [ "$status" -eq 0 ]
  [[ "$(context)" == *"$PLUGIN_ROOT/bin/vbw"* && "$(context)" == *"newer VBW"* ]] || { echo "$output"; false; }
  [[ "$(printf '%s' "$output" | jq -r '.systemMessage // ""')" == *"$PLUGIN_ROOT/bin/vbw"* ]] || { echo "$output"; false; }
  [[ "$(printf '%s' "$output" | jq -r '.systemMessage // ""')" == *"/vbw:update"* ]] || { echo "$output"; false; }
}

# R285 (seen 2026-11-09, D686): every session start, by a --plugin-dir copy or an
# installed one, leaves exactly one VBW PATH line in the session's env file, the loaded
# copy's bin folder: earlier VBW PATH lines of the file from any copy go (2.1.28 and older
# wrote them unmarked, in the form export PATH='<folder>/bin':"$PATH"), and every line VBW
# did not write stays byte for byte, in its place. The installed start keeps the session
# record too, so vbw doctor knows which copy Claude Code loaded either way.

# installed_copy: a full installed release (a copy of the plugin under test, version 9.9.8) in the plugin cache.
installed_copy() {
  REAL="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw/9.9.8"
  mkdir -p "$(dirname "$REAL")"
  cp -R "$PLUGIN_ROOT" "$REAL"
  jq '.version = "9.9.8"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" > "$REAL/.claude-plugin/plugin.json"
}
# others: the env file's lines VBW did not write, as the test put them there.
OTHERS=$'export OTHER_PLUGIN=1\nexport PATH=\'/opt/other/bin\':"$PATH"\n# a comment line'

@test "R285: 17 --plugin-dir starts and then an installed start leave one VBW PATH line, the installed copy's, and every other line byte for byte" {
  vbw_git_project
  "$VBW" init > /dev/null
  installed_copy
  local i
  # Three lines an older VBW wrote, unmarked, around the lines of others.
  { printf "export PATH=%s:\"\$PATH\"\n" "'$PLUGIN_ROOT/bin'"; printf '%s\n' "$OTHERS"; printf "export PATH=%s:\"\$PATH\"\n" "'$PLUGIN_ROOT/bin'" "'$PLUGIN_ROOT/bin'"; } > "$CLAUDE_ENV_FILE"
  loaded
  for ((i = 1; i <= 17; i++)); do session_start > /dev/null; done
  [ "$(vbw_path_lines | wc -l | tr -d ' ')" = 1 ] || { echo "after 17 --plugin-dir starts:"; cat "$CLAUDE_ENV_FILE"; false; }
  installed
  session_start "$REAL" > /dev/null
  [ "$(vbw_path_lines | wc -l | tr -d ' ')" = 1 ] && vbw_path_lines | grep -qF "$REAL/bin" || { echo "after the installed start:"; cat "$CLAUDE_ENV_FILE"; false; }
  # Every line VBW did not write, byte for byte and in order.
  diff <(printf '%s\n' "$OTHERS") <(grep -vF "$(vbw_path_lines)" "$CLAUDE_ENV_FILE") || { echo "the other lines changed:"; cat "$CLAUDE_ENV_FILE"; false; }
  [ "$(env PATH="$INST/bin:$PATH" bash -c '. "$1"; command -v vbw' _ "$CLAUDE_ENV_FILE")" = "$REAL/bin/vbw" ] || { cat "$CLAUDE_ENV_FILE"; false; }
}

@test "R285: a --plugin-dir start after an installed start leaves one line, the tree's" {
  vbw_git_project
  installed_copy
  installed
  session_start "$REAL" > /dev/null
  loaded
  session_start > /dev/null
  [ "$(vbw_path_lines | wc -l | tr -d ' ')" = 1 ] && vbw_path_lines | grep -qF "$PLUGIN_ROOT/bin" || { cat "$CLAUDE_ENV_FILE"; false; }
  [ "$(bash_tool bash 'command -v vbw')" = "$PLUGIN_ROOT/bin/vbw" ]
}

@test "R285: an installed start keeps the session record naming the copy Claude Code loaded for the session" {
  vbw_git_project
  installed_copy
  loaded
  session_start > /dev/null
  installed
  session_start "$REAL" > /dev/null
  [ "$(cat "$CLAUDE_CONFIG_DIR/vbw/sessions/s1" 2> /dev/null)" = "$REAL" ] || { echo "the session record holds: $(cat "$CLAUDE_CONFIG_DIR/vbw/sessions/s1" 2> /dev/null || echo nothing)"; false; }
}
