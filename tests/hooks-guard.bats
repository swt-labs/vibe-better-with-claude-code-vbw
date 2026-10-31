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

@test "a session started in a subfolder of a VBW project is guarded as at its root; the project is the git top, never a folder above it" {
  local sub="$PROJECT/Sub Folder With Spaces"
  mkdir -p "$sub"
  run bash_call 'git reset --hard' "$sub"
  denied
  run file_call Write ../.vbw/record.json "$sub"
  denied
  run file_call Read "$sub/.env" "$sub"
  denied
  # A git repository inside the project is a project of its own, as for the kernel
  # (git rev-parse --show-toplevel): the record above its git top is not its record.
  local inner="$PROJECT/inner repo"
  mkdir -p "$inner/deep dir" && git -C "$inner" init -q
  run bash_call 'git reset --hard' "$inner/deep dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
     | .requirements = [{id: "R1", text: "Pay", proof: "auto", status: "open", milestone: "M1"}]
     | {schema: 4, lease: {run: "r1", kind: $k, started_at: $at, files: $f},
        protected: ([.checks[].files // [] | .[]] | unique)} + del(.schema, .lease, .protected)' .vbw/record.json > "$TEST_ROOT/l.json"
  cp "$TEST_ROOT/l.json" .vbw/record.json
  # An open run, as vbw run start leaves it: a guard that fails then blocks, so allowed_sh cannot pass on a crash.
  mkdir -p .vbw/runtime && : > .vbw/runtime/run-open
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

# why COMMAND: the guard's reason for a subagent's Bash call, or "allow".
why() { as_agent Bash "$(jq -nc --arg c "$1" '{command: $c}')" | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow"'; }

# judged_as COMMAND PATH: COMMAND is refused with the very reason a redirect to PATH gets.
judged_as() {
  local got want
  got=$(why "$1") want=$(why "echo x > $2")
  [ "$want" != allow ] || { echo "the redirect to $2 is allowed"; return 1; }
  [ "$got" = "$want" ] || { printf 'not judged as a write of %s: %s\n  got:  %s\n  want: %s\n' "$2" "$1" "$got" "$want"; return 1; }
}
# allowed_sh COMMAND: the guard answers nothing and exits 0 (a crash under the open run exits 2 with a message).
allowed_sh() {
  run as_agent Bash "$(jq -nc --arg c "$1" '{command: $c}')"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { printf 'refused: %s\n  status %s: %s\n' "$1" "$status" "$output"; return 1; }
}

@test "#727: during a run, the files cp, rsync, install, ln, mv, tee, sed -i and rm write are judged like a redirect's" {
  lease build '["src/pay.js", "lib/"]'
  judged_as 'cp x.js src/other.js' src/other.js
  judged_as 'cp -f x.js src/other.js' src/other.js
  judged_as 'rsync -a x.js src/other.js' src/other.js
  judged_as 'install -m 644 x.js src/other.js' src/other.js
  judged_as 'ln -s x.js src/other.js' src/other.js
  judged_as 'ln -s lib/a/other.js' other.js
  judged_as 'cp lib/a.js lib/b.js src/' src/a.js
  judged_as 'cp -R lib/x src/' src/x
  judged_as 'cp -t src lib/a.js' src/a.js
  judged_as 'cp -rt src lib/a.js' src/a.js
  judged_as 'cp -tsrc lib/a.js' src/a.js
  judged_as 'cp --target-directory=src lib/a.js' src/a.js
  judged_as 'cp --target src lib/a.js' src/a.js
  judged_as 'install -Dt src lib/a.js' src/a.js
  # The first t takes the rest of the word as the folder, even a word that ends like -m.
  judged_as 'install -tfoo lib/a.js' foo/a.js
  # rsync's -t is --times, not a target folder.
  judged_as 'rsync -a -t x.js src/other.js' src/other.js
  judged_as 'rsync -a --remove-source-files src/other.js lib/' src/other.js
  judged_as 'mv src/pay.js src/other.js' src/other.js
  judged_as 'mv -f src/other.js src/pay.js' src/other.js
  judged_as 'rm src/other.js' src/other.js
  judged_as 'rm -f lib/a.js src/other.js' src/other.js
  judged_as 'sed -i s/a/b/ src/other.js' src/other.js
  judged_as "sed -i '' s/a/b/ src/other.js" src/other.js
  judged_as 'sed -i.bak -e s/a/b/ src/pay.js src/other.js' src/other.js
  # The script given by -f, -e glued or --expression is never judged; the file after it is.
  judged_as 'sed -f fix.sed -i src/other.js' src/other.js
  judged_as 'sed -es/a/b/ -i src/other.js' src/other.js
  judged_as 'sed --expression=s/a/b/ -i src/other.js' src/other.js
  judged_as 'sed --expression s/a/b/ -i src/other.js' src/other.js
  # After a bare -i, a dot word is BSD's suffix or GNU's file: it is judged as a file too.
  judged_as 'sed -e s/x/y/ -i .eslintrc' .eslintrc
  judged_as 'sed -i .eslintrc -e s/x/y/ src/pay.js' .eslintrc
  judged_as 'echo x | tee src/other.js' src/other.js
  judged_as 'tee -a src/other.js < x' src/other.js
  # Reading from a file outside the run's files, or from a protected one, writes nothing there.
  allowed_sh 'cp x.js src/pay.js'
  allowed_sh 'cp -f src/other.js src/pay.js'
  allowed_sh 'cp tests/pay.test.js lib/pay.test.js'
  allowed_sh 'cp -R src/other lib/'
  allowed_sh 'cp src/a.js src/b.js lib/'
  allowed_sh 'cp -t lib/ src/other.js'
  allowed_sh 'mv -f lib/a.js lib/b.js'
  allowed_sh 'rsync -a src/other.js lib/other.js'
  allowed_sh 'install -m 644 src/other.js src/pay.js'
  # A flag's value is not a file the command writes.
  allowed_sh 'install -m 644 x/pay.js src/'
  allowed_sh 'rsync -a --exclude node_modules x/pay.js src/'
  allowed_sh 'rsync -t src/other.js lib/other.js'
  allowed_sh 'rsync -a src/other.js lib/'
  allowed_sh 'cp -S .orig x/pay.js src/'
  allowed_sh 'rsync -e ssh x/pay.js src/'
  # A folder the run owns, named with a trailing / (#727 QA round 2).
  allowed_sh 'rsync -a assets/ lib/'
  allowed_sh 'cp -r assets/ lib/'
  allowed_sh 'rm -rf lib/'
  # . and .. are folders.
  judged_as 'cp lib/a.js .' a.js
  judged_as 'mv lib/a.js ..' ../a.js
  allowed_sh 'ln -s ../src/other.js lib/link.js'
  allowed_sh 'rm .vbw/runtime/scratch/x.log'
  allowed_sh 'rm -f lib/a.js'
  allowed_sh 'sed -i s/a/b/ src/pay.js'
  allowed_sh "sed -i '' s/a/b/ src/pay.js"
  allowed_sh 'sed -i.bak s/a/b/ src/pay.js'
  allowed_sh 'sed -i -e s/a/b/ -e s/c/d/ src/pay.js'
  allowed_sh 'echo x | tee src/pay.js lib/log'
  allowed_sh 'sed s/a/b/ src/other.js > lib/out.js'
}

@test "#727: during a run, a shell tool writing a protected check file, or a folder that holds one, is refused like a redirect" {
  lease build '["src/pay.js", "tests/pay.test.js"]'
  judged_as 'cp x.js tests/pay.test.js' tests/pay.test.js
  judged_as 'sed -i s/expect/skip/ tests/pay.test.js' tests/pay.test.js
  judged_as 'rm tests/pay.test.js' tests/pay.test.js
  judged_as 'mv tests/pay.test.js src/pay.js' tests/pay.test.js
  [[ "$(why 'cp x.js tests/pay.test.js')" == *"is a protected check file"* ]] || false
  allowed_sh 'cp tests/pay.test.js src/pay.js'
  # A folder named whole: the guard reads text and cannot tell a folder from a file, so a write that
  # may land on a protected file under it (rm -r, a copy into it) is refused.
  lease build 'null'
  [[ "$(why 'rm -rf tests')" == *"tests holds a protected check file (tests/pay.test.js)"* ]] || { why 'rm -rf tests'; false; }
  [[ "$(why 'cp x/pay.test.js tests')" == *"tests holds a protected check file"* ]] || false
  allowed_sh 'rm -rf build'
  allowed_sh 'cp x.js src'
  # A glob the shell expands is judged by the protected files it may match.
  [[ "$(why 'sed -i s/expect/skip/ tests/*.test.js')" == *"tests/*.test.js matches a protected check file (tests/pay.test.js)"* ]] || { why 'sed -i s/expect/skip/ tests/*.test.js'; false; }
  [[ "$(why 'rm -rf t*')" == *"matches a protected check file"* ]] || false
  [[ "$(why 'rm tests/pay.test.?s')" == *"matches a protected check file"* ]] || false
  [[ "$(why 'rm tests/pay.test.[!x]s')" == *"matches a protected check file"* ]] || false
  # A pattern the guard cannot read counts as matching.
  [[ "$(why 'rm tests/[z-a]*')" == *"matches a protected check file"* ]] || false
  allowed_sh 'rm -f build/*.js'
  allowed_sh 'rm -f tests/*.snap'
  allowed_sh 'rm tests/pay.test.[!j]s'
  # * may cross /, as zsh's ** does.
  [[ "$(why 'sed -i s/a/b/ tests/**/pay.test.js')" == *"matches a protected check file"* ]] || false
  [[ "$(why 'rm t*/pay.test.js')" == *"matches a protected check file"* ]] || false
  # Under a fix run that may add tests, a test folder holding a protected check file is still refused.
  jq '.lease.kind = "fix" | .lease.new_tests = true | .protected = ["tests/unit/pay.test.js"]' .vbw/record.json > "$TEST_ROOT/l.json" && cp "$TEST_ROOT/l.json" .vbw/record.json
  [[ "$(why 'rm -rf tests/unit')" == *"tests/unit holds a protected check file (tests/unit/pay.test.js)"* ]] || { why 'rm -rf tests/unit'; false; }
  allowed_sh 'cp x.js tests/unit/new.test.js'
  lease build 'null'
  # A file tool's path is taken as written, never as a pattern (D311).
  run as_agent Write "{\"file_path\": \"$PROJECT/t*\"}"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "#727: during planning, a shell copy onto product code is refused like a redirect" {
  lease plan '[".vbw/"]'
  judged_as 'cp x.js src/other.js' src/other.js
  judged_as 'mv tests/a.test.js src/a.js' src/a.js
  allowed_sh 'cp src/other.js tests/other.test.js'
  allowed_sh 'cp x.md .vbw/notes.md'
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

@test "during a run, builders never move HEAD or other builders' changes in the shared tree" {
  lease fix '["src/pay.js"]'
  local c
  for c in 'git stash' 'git stash push -m x' 'git stash pop' 'git switch main' 'git checkout main' 'git reset HEAD~1' 'git reset' \
           'git checkout -- src/other.js' 'git restore src/other.js' 'git cherry-pick abc' 'git pull'; do
    run as_agent Bash "$(jq -nc --arg c "$c" '{command: $c}')"
    denied || { echo "not denied: $c"; return 1; }
  done
  for c in 'git stash list' 'git status' 'git diff' 'git checkout -- src/pay.js' 'git restore src/pay.js' 'git restore --staged src/other.js' 'git log -3'; do
    run as_agent Bash "$(jq -nc --arg c "$c" '{command: $c}')"
    [ -z "$output" ] || { echo "denied: $c"; return 1; }
  done
  # The main session is never held to this.
  run bash_call 'git stash'
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

@test "during a QA or mapping run, agents write nothing" {
  lease qa '[]'
  run as_agent Write "{\"file_path\": \"$PROJECT/src/pay.js\"}"
  denied
  [[ "$output" == *"cannot be written during a qa run: its agents only read"* ]]
  run as_agent Bash '{"command": "echo x > notes.txt"}'
  denied
  run as_agent Bash '{"command": "vbw qa finding R1 \"no receipt\""}'
  [ -z "$output" ]
}
