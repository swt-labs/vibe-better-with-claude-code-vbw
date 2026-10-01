#!/usr/bin/env bats
# Contract tests for the skills (the user's commands). Probe G9: in the default
# permission mode a skill whose `!` command is not pre-approved in
# allowed-tools aborts silently (zero turns, no output), and a failing `!`
# command aborts the skill too.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

skills() { find "$PLUGIN_ROOT/skills" -name SKILL.md | LC_ALL=C sort; }
front() { awk 'NR == 1 && /^---$/ { on = 1; next } on && /^---$/ { exit } on' "$1"; }

@test "the vibe, approve, init and status skills exist" {
  local s
  for s in vibe approve init status; do [ -f "$PLUGIN_ROOT/skills/$s/SKILL.md" ]; done
}

@test "each skill is named after its directory with a single-line description" {
  local f name
  while IFS= read -r f; do
    name=$(basename "$(dirname "$f")")
    front "$f" | grep -qx "name: $name" || { echo "name is not $name: $f"; false; }
    front "$f" | awk '/^description: / { d = substr($0, 14); n++ } END { exit !(n == 1 && length(d) >= 20 && length(d) <= 1536) }' \
      || { echo "missing, multi-line or over-long description: $f"; false; }
  done < <(skills)
}

@test "every shell block runs the kernel by its plugin path and can never abort the skill" {
  local f line n=0
  while IFS= read -r f; do
    while IFS= read -r line; do
      n=$((n + 1))
      [[ "$line" == '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" '* ]] || { echo "not the kernel by plugin path: $line ($f)"; false; }
      [[ "$line" == *' || true' ]] || { echo "a failure would abort the skill: $line ($f)"; false; }
    done < <(awk '/^```!$/ { on = 1; next } on && /^```$/ { on = 0 } on' "$f")
  done < <(skills)
  [ "$n" -ge 7 ] || { echo "only $n shell lines found: the scan is broken"; false; }
}

@test "every skill with shell blocks pre-approves them in allowed-tools (G9)" {
  local f
  while IFS= read -r f; do
    grep -q '^```!$' "$f" || continue
    front "$f" | grep -qF 'allowed-tools: Bash("${CLAUDE_PLUGIN_ROOT}/bin/vbw" ' \
      || { echo "shell blocks without allowed-tools: $f"; false; }
  done < <(skills)
}

@test "only the user can approve" {
  front "$PLUGIN_ROOT/skills/approve/SKILL.md" | grep -qx 'disable-model-invocation: true'
  local f
  while IFS= read -r f; do
    [ "$f" = "$PLUGIN_ROOT/skills/approve/SKILL.md" ] && continue
    ! grep -q 'bin/vbw" approve' "$f" || { echo "approves outside /vbw:approve: $f"; false; }
  done < <(skills)
}

@test "the router's Stop hook is the autonomy gate and can never block by accident" {
  local cmd
  cmd=$(front "$PLUGIN_ROOT/skills/vibe/SKILL.md" | sed -n 's/^ *command: //p')
  [ "$cmd" = '"\"${CLAUDE_PLUGIN_ROOT}/bin/vbw\" auto gate 2>/dev/null || true"' ]
  grep -qF 'vbw auto on ${CLAUDE_SESSION_ID}' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}

@test "skills only name vbw commands that exist" {
  local cmd n=0
  while IFS= read -r cmd; do
    n=$((n + 1))
    "$VBW" help | grep -qE "^  $cmd( |$)" || { echo "skills use unknown command: vbw $cmd"; false; }
  done < <(skills | while IFS= read -r f; do grep -oE '`vbw [a-z]+' "$f" || true; done | sed 's/^`vbw //' | sort -u)
  [ "$n" -ge 8 ] || { echo "only $n commands found: the scan is broken"; false; }
}

@test "the router stays within its budget (about 2k tokens)" {
  local words
  words=$(wc -w < "$PLUGIN_ROOT/skills/vibe/SKILL.md")
  echo "router: $words words"
  [ "$words" -le 1400 ]
}

@test "skills never build paths from \$HOME, caches or /tmp (K4)" {
  local f
  while IFS= read -r f; do
    ! grep -nE '\$HOME|~/\.claude|plugins/cache|/tmp/' "$f" || { echo "in $f"; false; }
  done < <(skills)
}
