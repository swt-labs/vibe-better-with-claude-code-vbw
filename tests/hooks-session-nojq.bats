#!/usr/bin/env bats
# R141 (L1): on a machine without jq, the session-start hook ends quietly in
# every kind of folder: exit 0, nothing on stdout or stderr, and no kernel
# command run. The hook runs with a PATH that has bash, git and the few tools
# the hook uses, never jq, so the result does not depend on the host having jq.
# The kernel is a stand-in that leaves a mark when anything runs it.

load helper

# The SessionStart command exactly as hooks.json gives it (JSON-escaped quotes).
HOOK_CMD='bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"'

setup() {
  vbw_setup
  vbw_git_project
  STUB="$TEST_ROOT/plugin"
  MARK="$TEST_ROOT/kernel-ran"
  NOJQ="$TEST_ROOT/nojq-bin"
  export STUB MARK NOJQ
  mkdir -p "$STUB/hooks" "$STUB/bin" "$NOJQ"
  cp "$PLUGIN_ROOT/hooks/hooks.json" "$PLUGIN_ROOT/hooks/session-start.sh" "$STUB/hooks/"
  cat > "$STUB/bin/vbw" << EOF
#!/usr/bin/env bash
: > "$MARK"
echo "stand-in kernel ran: \$*" >&2
exit 1
EOF
  chmod +x "$STUB/bin/vbw"
  local t p
  for t in bash sh git awk head rm rmdir; do
    p=$(command -v "$t") || {
      echo "host has no $t"
      return 1
    }
    ln -s "$p" "$NOJQ/$t"
  done
  # Folders: a VBW project root, one made by a newer VBW, a VBW 1 plan, a
  # subfolder of a VBW project, and a folder that is not a VBW project.
  mkdir -p .vbw src
  printf '{"schema": 1}\n' > .vbw/record.json
  NEWER="$TEST_ROOT/newer"
  V1="$TEST_ROOT/v1 plan"
  PLAIN="$TEST_ROOT/plain"
  export NEWER V1 PLAIN
  mkdir -p "$NEWER/.vbw" "$V1/.vbw-planning" "$PLAIN"
  printf '{"schema": 99}\n' > "$NEWER/.vbw/record.json"
}

teardown() { vbw_teardown; }

# no_jq_start DIR: run the hooks.json SessionStart command for DIR the way Claude
# Code does (sh -c, hook input on stdin), with PATH holding no jq. Sets status,
# output (stdout) and ERR (stderr).
no_jq_start() {
  local err="$TEST_ROOT/stderr"
  status=0
  output=$(env PATH="$NOJQ" CLAUDE_PLUGIN_ROOT="$STUB" CLAUDE_PROJECT_DIR="$1" \
    "$NOJQ/sh" -c "$HOOK_CMD" 2> "$err" <<< '{"hook_event_name": "SessionStart", "source": "startup"}') || status=$?
  ERR=$(cat "$err")
}

# quiet DIR: the hook ends with exit 0, no stdout, no stderr and no kernel run.
quiet() {
  rm -f "$MARK"
  no_jq_start "$1"
  [ "$status" -eq 0 ] || {
    echo "$1: exit $status; stderr: $ERR"
    return 1
  }
  [ -z "$output" ] || {
    echo "$1: stdout: $output"
    return 1
  }
  [ -z "$ERR" ] || {
    echo "$1: stderr: $ERR"
    return 1
  }
  [ ! -e "$MARK" ] || {
    echo "$1: the hook ran a kernel command"
    return 1
  }
}

@test "R141: the test PATH has bash and git but no jq, and hooks.json runs session-start.sh" {
  [ -x "$NOJQ/bash" ] && [ -x "$NOJQ/git" ]
  [ ! -e "$NOJQ/jq" ]
  run env PATH="$NOJQ" "$NOJQ/sh" -c 'command -v jq'
  [ "$status" -ne 0 ]
  grep -qF 'bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"' "$PLUGIN_ROOT/hooks/hooks.json"
}

@test "R141: without jq, in a VBW project root the hook ends quietly and runs no kernel command" {
  quiet "$PROJECT"
}

@test "R141: without jq, in a project made by a newer VBW the hook ends quietly and runs no kernel command" {
  quiet "$NEWER"
}

@test "R141: without jq, in a folder holding only a VBW 1 plan the hook ends quietly" {
  quiet "$V1"
}

@test "R141: without jq, in a subfolder of a VBW project the hook ends quietly" {
  quiet "$PROJECT/src"
}

@test "R141: without jq, in a folder that is not a VBW project the hook ends quietly" {
  quiet "$PLAIN"
}

@test "R141: without jq, the hook stops early: five starts finish well within the hook time budget" {
  local d start
  start=$SECONDS
  for d in "$PROJECT" "$NEWER" "$V1" "$PROJECT/src" "$PLAIN"; do
    quiet "$d"
  done
  [ $((SECONDS - start)) -le 3 ] || {
    echo "five starts took $((SECONDS - start)) s"
    false
  }
}
