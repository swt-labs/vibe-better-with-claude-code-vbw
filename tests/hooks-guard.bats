#!/usr/bin/env bats
# The PreToolUse guard (docs/guards.md): what the shell would execute is
# judged; heredoc bodies and quoted strings are data (ledger D281).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# bash_call COMMAND [PROJECT_DIR]: the guard's decision on a Bash tool call.
bash_call() {
  jq -nc --arg c "$1" --arg d "${2:-$PROJECT}" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | HOOK_PROJECT_DIR="${2:-$PROJECT}" vbw_hook PreToolUse Bash
}

# file_call TOOL PATH [PROJECT_DIR]
file_call() {
  jq -nc --arg t "$1" --arg p "$2" --arg d "${3:-$PROJECT}" '{hook_event_name: "PreToolUse", tool_name: $t, cwd: $d, tool_input: {file_path: $p}}' \
    | HOOK_PROJECT_DIR="${3:-$PROJECT}" vbw_hook PreToolUse "$1"
}

denied() {
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
}

@test "destructive commands at command position are denied" {
  local c
  for c in 'rm -rf /' 'rm -rf ~' 'rm -fr .' 'rm -r --force *' 'sudo rm -rf "$HOME"' 'rm -rf .git' \
           'git push --force' 'git push origin +main' 'git push -f origin main' 'git push origin --delete main' \
           'git reset --hard HEAD~3' 'git -C . reset --hard' 'git clean -fdx' 'git checkout -- .' 'git restore .' \
           'git branch -D feature' 'git stash clear' 'git filter-branch --tree-filter x' 'FOO=1 git reset --hard'; do
    run bash_call "$c"
    denied || { echo "not denied: $c"; false; }
  done
}

@test "ordinary work is allowed" {
  local c
  for c in 'rm -rf node_modules' 'rm -f build/out.js' 'git push' 'git push origin feature' 'git reset HEAD file' \
           'git clean -n' 'git checkout -- src/a.js' 'git restore --staged .' 'git branch -d merged' 'git stash pop' \
           'npm test 2>&1 | tail -20' 'ls -la .env' 'cat .env.example' 'jq . .vbw/record.json' 'git add .vbw/record.json' \
           'vbw status' 'vbw prove'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "denied: $c -> $output"; false; }
  done
}

@test "heredoc bodies and quoted strings are data" {
  run bash_call 'git commit -m "never rm -rf / or git push --force"'
  [ -z "$output" ]
  run bash_call "echo 'rm -rf ~' > notes.txt"
  [ -z "$output" ]
  run bash_call $'cat > notes.md <<\'EOF\'\nrm -rf /\ngit reset --hard\nEOF\necho done'
  [ -z "$output" ]
  run bash_call $'cat <<-EOF\n\trm -rf ~\n\tEOF'
  [ -z "$output" ]
}

@test "what the shell executes inside strings is judged" {
  run bash_call 'echo "$(rm -rf ~)"'
  denied
  run bash_call 'echo "`git reset --hard`"'
  denied
  run bash_call "bash -c 'git push --force'"
  denied
  run bash_call "sh -lc \"cd x && rm -rf .\""
  denied
  run bash_call "eval 'git clean -f'"
  denied
  run bash_call $'cat <<EOF\nok\nEOF\nrm -rf /'
  denied
}

@test "secrets are never read or written, by the shell or the file tools" {
  local c
  for c in 'cat .env' 'grep KEY .env.local' 'source .env' 'cp ~/.ssh/id_rsa x' 'base64 < server.pem' \
           'echo x >> .env' 'cat "config/.env.production"' 'docker run --env-file=.env img'; do
    run bash_call "$c"
    denied || { echo "not denied: $c"; false; }
  done
  run file_call Read "$PROJECT/.env"
  denied
  run file_call Write "$PROJECT/certs/tls.key"
  denied
  run file_call Read "$PROJECT/.env.example"
  [ -z "$output" ]
  run file_call Read "$PROJECT/src/env.js"
  [ -z "$output" ]
}

@test "the record is written only by vbw" {
  run file_call Write "$PROJECT/.vbw/record.json"
  denied
  run file_call Edit "$PROJECT/.vbw/record.json"
  denied
  run file_call Read "$PROJECT/.vbw/record.json"
  [ -z "$output" ]
  run bash_call 'jq ".plans = []" .vbw/record.json > /tmp/r && mv /tmp/r .vbw/record.json'
  denied
  run bash_call 'sed -i "" s/open/proven/ .vbw/record.json'
  denied
  run bash_call 'echo {} > .vbw/record.json'
  denied
}

@test "only the user approves: vbw approve and consent writes are denied everywhere" {
  local elsewhere="$TEST_ROOT/not-vbw"
  mkdir -p "$elsewhere"
  local c
  for c in 'vbw approve' '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" approve' '/plugins/vbw/bin/vbw approve' 'bash bin/vbw approve' \
           'cd x && vbw approve' 'echo "$(vbw approve)"' 'jq . x > .git/vbw/consent.json'; do
    run bash_call "$c" "$elsewhere"
    denied || { echo "not denied: $c"; false; }
    [[ "$output" == *"/vbw:approve"* ]]
  done
  run file_call Write "$PROJECT/.git/vbw/consent.json" "$elsewhere"
  denied
}

@test "project rules apply only when the session's project is a VBW project" {
  local elsewhere="$TEST_ROOT/not-vbw"
  mkdir -p "$elsewhere"
  run bash_call 'git reset --hard' "$elsewhere"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run file_call Read "$elsewhere/.env" "$elsewhere"
  [ -z "$output" ]
  run bash_call 'git reset --hard' "$PROJECT"
  denied
}

@test "a corrupt record still counts as a VBW project" {
  printf '{"schema":' > .vbw/record.json
  run bash_call 'git reset --hard'
  denied
}

@test "a guard error allows the call and never exits non-zero (exit 2 would block it)" {
  local tool
  for tool in Bash Read; do
    run vbw_hook PreToolUse "$tool" < <(printf 'not json')
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run vbw_hook PreToolUse "$tool" < <(printf '{}')
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  run bash_call "echo 'unbalanced"
  [ "$status" -eq 0 ]
}

@test "a large heredoc is data, and the command around it is still judged" {
  local body
  body=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "rm -rf / and git push --force %d\n", i }')
  run bash_call "git add notes.md && cat > notes.md <<'EOF'
$body
EOF"
  [ -z "$output" ]
  run bash_call "cat > notes.md <<'EOF'
$body
EOF
git reset --hard"
  denied
}

# --- the run lease (docs/workflows.md) ------------------------------------------

# as_agent TOOL INPUT_JSON: a call from a workflow subagent, in the project.
as_agent() {
  jq -nc --arg t "$1" --argjson i "$2" --arg d "$PROJECT" \
    '{hook_event_name: "PreToolUse", tool_name: $t, cwd: $d, agent_id: "a1", agent_type: "workflow-subagent", tool_input: $i}' \
    | vbw_hook PreToolUse "$1"
}

lease() {
  jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg k "$1" --argjson f "$2" \
    '.checks = [{id: "C1", req: "R1", run: ["true"], files: ["tests/pay.test.js"]}]
     | .requirements = [{id: "R1", text: "Pay", proof: "auto", status: "open"}]
     | .lease = {run: "r1", kind: $k, started_at: $at, files: $f}' .vbw/record.json > "$TEST_ROOT/l.json"
  cp "$TEST_ROOT/l.json" .vbw/record.json
}

@test "during a build, a subagent writes only the run's files" {
  lease build '["src/pay.js"]'
  run as_agent Write "{\"file_path\": \"$PROJECT/src/pay.js\"}"
  [ -z "$output" ]
  run as_agent Edit "{\"file_path\": \"$PROJECT/src/other.js\"}"
  denied
  [[ "$output" == *"src/other.js is outside this run's files (src/pay.js)"* ]]
  run as_agent Write "{\"file_path\": \"$PROJECT/src/../src/other.js\"}"
  denied
  run as_agent Bash '{"command": "echo x > src/other.js"}'
  denied
  run as_agent Bash '{"command": "npm test > /dev/null 2>&1 && echo ok > src/pay.js"}'
  [ -z "$output" ]
  run as_agent Read "{\"file_path\": \"$PROJECT/src/other.js\"}"
  [ -z "$output" ]
}

@test "during a build, protected check files are read-only and commits go through vbw" {
  lease build '["src/pay.js", "tests/pay.test.js"]'
  run as_agent Edit "{\"file_path\": \"$PROJECT/tests/pay.test.js\"}"
  denied
  [[ "$output" == *"protected check file"* ]]
  run as_agent Bash '{"command": "git add -A && git commit -m wip"}'
  denied
  [[ "$output" == *"commits go through vbw commit"* ]]
  run as_agent Bash '{"command": "vbw commit P1.1 \"feat(pay): card form\""}'
  [ -z "$output" ]
}

@test "during planning, subagents may write test files (no file list, nothing protected yet)" {
  lease plan 'null'
  run as_agent Write "{\"file_path\": \"$PROJECT/tests/pay.test.js\"}"
  [ -z "$output" ]
}

@test "the main session is never held to a lease, and an old lease holds no one" {
  lease build '["src/pay.js"]'
  run file_call Write "$PROJECT/src/other.js"
  [ -z "$output" ]
  run bash_call 'git commit -m "user commit"'
  [ -z "$output" ]
  jq '.lease.started_at = "2020-01-01T00:00:00Z"' .vbw/record.json > "$TEST_ROOT/o.json" && cp "$TEST_ROOT/o.json" .vbw/record.json
  run as_agent Write "{\"file_path\": \"$PROJECT/src/other.js\"}"
  [ -z "$output" ]
}

@test "commands rewritten by RTK are judged like the originals" {
  run bash_call 'rtk git reset --hard'
  denied
  run bash_call 'rtk git status'
  [ -z "$output" ]
}
