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

@test "a session started in a submodule with no record of its own is guarded as the VBW project above it, as the kernel finds it" {
  vbw_submodule "mod dir"
  mkdir -p "mod dir/deep"
  run bash_call 'git reset --hard' "$PROJECT/mod dir/deep"
  denied
  run file_call Write "$PROJECT/.vbw/record.json" "$PROJECT/mod dir"
  denied
  # The kernel works on the same project from there.
  (cd "$PROJECT/mod dir/deep" && "$VBW" status < /dev/null > /dev/null) || { echo "vbw status failed in the submodule"; false; }
}

@test "a linked worktree nested in a VBW project, with no record of its own, is its own project: guards inert, the kernel refuses" {
  # A branch with no record: an empty commit.
  local c wt="$PROJECT/.claude/worktrees/w t"
  c=$(git commit-tree -m empty "$(git mktree < /dev/null)")
  git worktree add -q -b wt "$wt" "$c"
  run bash_call 'git reset --hard' "$wt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run file_call Write "$wt/.vbw/record.json" "$wt"
  [ -z "$output" ]
  run bash -c 'cd "$1" && "$2" status < /dev/null' _ "$wt" "$VBW"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a VBW project"* ]] || { echo "$output"; false; }
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

@test "R250: during a run, vbw apply in any mode (plain, --patch, --add, --amend; by any path, after a cd, in a substitution) is refused to every run agent in two lines, the rule and the next step; the main session is never refused" {
  lease build '["src/pay.js"]'
  local c r
  for c in 'vbw apply < plan.json' 'vbw apply --patch < doc.json' 'vbw apply --add < phase.json' 'vbw apply --amend < doc.json' \
           '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" apply --amend < doc.json' 'cd src && vbw apply --amend < ../doc.json' 'echo "$(vbw apply --patch < doc.json)"' \
           'cat doc.json | vbw apply --amend' 'VBW_SESSION_ID=x vbw apply --amend < doc.json'; do
    r=$(why "$c")
    [ "${r#VBW guard: }" = $'vbw apply changes the plan of record: only the main session runs it, in every mode (--amend, --patch, --add included)\nNext: report it so the main session amends or patches the plan' ] \
      || { printf 'not refused as the main session'"'"'s command: %s\n  got: %s\n' "$c" "$r"; false; }
  done
  allowed_sh 'vbw status'
  allowed_sh 'vbw show contract'
  allowed_sh 'vbw plan done P1.1'
  for c in 'vbw apply < plan.json' 'vbw apply --amend < doc.json' 'vbw apply --patch < doc.json'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "the main session was refused: $c -> $output"; false; }
  done
  lease fix '["src/pay.js"]'
  [ "$(why 'vbw apply --amend < doc.json')" != allow ] || { echo "allowed under a fix run"; false; }
  lease qa '[]'
  [ "$(why 'vbw apply --patch < doc.json')" != allow ] || { echo "allowed under a qa run"; false; }
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

# R239 (T209, D557): no plain git history change bypasses vbw commit while VBW drives.
# An agent under a lease is refused git commit-tree as it is refused commit (in every form
# the guard reads: plain, -C, cd &&, a subshell, sh -c). VBW's own chat (a hook input with no
# agent_type) is refused the same commands while its own autonomous run is armed
# (.vbw/runtime/auto.SESSION.json, read for the session's own id only) or the record holds
# a loop that has not ended; with neither, the chat's commands are allowed as today, since
# the user's own commands are never checked.

# chat_call COMMAND [SESSION]: the guard's decision on a Bash call from the main session.
chat_call() {
  jq -nc --arg c "$1" --arg s "${2:-s1}" --arg d "$PROJECT" \
    '{hook_event_name: "PreToolUse", session_id: $s, tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash
}
chat_reason() { chat_call "$1" "${2:-s1}" | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow"'; }

R239_FORMS=('git commit-tree HEAD^{tree} -m wip' 'git -C . commit-tree HEAD^{tree} -m wip' 'cd sub && git commit-tree HEAD^{tree} -m wip'
  '(git commit-tree HEAD^{tree} -m wip)' "sh -c 'git commit-tree HEAD^{tree} -m wip'")

@test "R239: an agent under a lease is refused git commit-tree in its plain, -C, cd &&, subshell and sh -c forms, each naming vbw commit PLAN" {
  lease build '["src/pay.js"]'
  local c r
  for c in "${R239_FORMS[@]}"; do
    r=$(why "$c")
    [ "$r" != allow ] || { echo "not refused: $c"; false; }
    [[ "$r" == *"commit-tree"* && "$r" == *"vbw commit PLAN"* ]] || { echo "the refusal of '$c' does not name commit-tree and vbw commit PLAN: $r"; false; }
  done
}

@test "R239: while this session's autonomous run is armed, the chat is refused every git history change, naming the armed run and vbw commit" {
  "$VBW" auto on s1 > /dev/null
  local c r
  for c in 'git commit -m wip' 'git commit-tree HEAD^{tree} -m wip' 'git push' 'git rebase main' 'git merge feature' 'git pull' 'git cherry-pick abc' 'git revert HEAD' 'git am patch.mbox' \
           'git -C . commit -m wip' 'cd sub && git commit -m wip' '(git commit -m wip)' "sh -c 'git commit -m wip'"; do
    r=$(chat_reason "$c")
    [ "$r" != allow ] || { echo "not refused while armed: $c"; false; }
    [[ "$r" == *"armed"* && "$r" == *"vbw commit"* ]] || { echo "the refusal of '$c' names neither the armed run nor vbw commit: $r"; false; }
    [[ "$r" == *"Next:"* ]] || { echo "no next step: $r"; false; }
  done
}

@test "R239: while the record holds a loop that has not ended, the chat is refused the same commands, naming the loop" {
  jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.loop = {session: "s1", started_at: $at, items: []}' .vbw/record.json > "$TEST_ROOT/loop.json" && cp "$TEST_ROOT/loop.json" .vbw/record.json
  local c r
  for c in 'git commit -m wip' 'git commit-tree HEAD^{tree} -m wip' 'git rebase main' 'git cherry-pick abc'; do
    r=$(chat_reason "$c")
    [ "$r" != allow ] || { echo "not refused in a loop: $c"; false; }
    [[ "$r" == *"loop"* && "$r" == *"vbw commit"* ]] || { echo "the refusal of '$c' names neither the loop nor vbw commit: $r"; false; }
  done
  # An ended loop holds no one.
  jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.loop.ended = $at' .vbw/record.json > "$TEST_ROOT/loop.json" && cp "$TEST_ROOT/loop.json" .vbw/record.json
  [ "$(chat_reason 'git commit -m wip')" = allow ] || { echo "refused after the loop ended"; false; }
}

@test "R239: the hook reads the session's own arm file only: another session's armed run never holds this chat" {
  "$VBW" auto on other > /dev/null
  [ "$(chat_reason 'git commit -m wip' s1)" = allow ] || { echo "held by another session's arm file: $(chat_reason 'git commit -m wip' s1)"; false; }
  [ "$(chat_reason 'git commit -m wip' other)" != allow ] || { echo "the armed session itself is not held"; false; }
  # A hook input with no session id is nobody's armed run.
  run bash_call 'git commit -m wip'
  [ -z "$output" ] || { echo "held with no session id: $output"; false; }
}

@test "R239: with no arm file and no live loop, the chat's git commands are allowed as today, and vbw commit stays allowed from every caller" {
  local c
  for c in 'git commit -m wip' 'git commit-tree HEAD^{tree} -m wip' 'git push' 'git rebase main' 'git merge feature' 'git pull' 'git cherry-pick abc' 'git revert HEAD' 'git am patch.mbox'; do
    [ "$(chat_reason "$c")" = allow ] || { echo "the user's own chat was checked: $c -> $(chat_reason "$c")"; false; }
  done
  "$VBW" auto on s1 > /dev/null
  [ "$(chat_reason 'vbw commit P1.1 "feat(pay): card form"')" = allow ] || { echo "vbw commit refused while armed"; false; }
  [ "$(chat_reason 'git status && git log -3')" = allow ] || { echo "a read-only git command refused while armed"; false; }
  lease build '["src/pay.js"]'
  allowed_sh 'vbw commit P1.1 "feat(pay): card form"'
}

@test "R239 (T209): the chat's 'git commit -- sub && git status --short && vbw prove' after a failed proof is refused when armed and allowed when not" {
  local c='git commit -m "fix(sub): greet" -- sub && git status --short && vbw prove'
  [ "$(chat_reason "$c")" = allow ] || { echo "refused with no armed run: $(chat_reason "$c")"; false; }
  "$VBW" auto on s1 > /dev/null
  local r
  r=$(chat_reason "$c")
  [ "$r" != allow ] || { echo "T209's command was not refused while armed"; false; }
  [[ "$r" == *"git commit"* && "$r" == *"vbw commit"* ]] || { echo "$r"; false; }
}

# --- R276: the record guard refuses writes, never reads ---------------------------

# reason COMMAND: the first line of the guard's reason for the main session's COMMAND, or "allow".
reason() { bash_call "$1" | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow" | split("\n")[0]'; }

RECORD_LINE='VBW guard: .vbw/record.json is written only by vbw (vbw help lists the commands)'

@test "R276: a command that only reads the record, or looks for it, passes: find -path, ls, grep, wc, cat, head, tail, jq, awk, diff, stat, shasum, a copy to /dev/null and git log" {
  local c got
  mkdir -p .vbw/runtime && printf '{}' > .vbw/runtime/x.json
  for c in 'find . -path "*/.vbw/record.json"' 'find . -path "*/.vbw/record.json" -newer .vbw/runtime/x.json -print' 'find .vbw -name record.json' \
           'ls -la .vbw/record.json' 'grep -c plans .vbw/record.json' 'wc -c .vbw/record.json' 'cat .vbw/record.json' 'head -c 200 .vbw/record.json' \
           'tail -n 5 .vbw/record.json' 'jq .plans .vbw/record.json' 'jq -r .milestone.id .vbw/record.json > .vbw/runtime/scratch/id.txt' \
           'awk "{ print }" .vbw/record.json' 'diff .vbw/record.json .vbw/runtime/x.json' 'stat .vbw/record.json' 'shasum -a 256 .vbw/record.json' \
           'cp .vbw/record.json /dev/null' 'git log --oneline -- .vbw/record.json' 'git diff HEAD -- .vbw/record.json' 'true && cat .vbw/record.json | jq .plans'; do
    got=$(reason "$c")
    [ "$got" = allow ] || { printf 'a read was refused: %s\n  %s\n' "$c" "$got"; false; }
  done
}

@test "R276: every real write of the record is refused: a redirect anywhere in the command, a copy, move or install onto it, tee, an in-place edit, a delete, a truncation, dd of= and a link onto it" {
  local c got
  for c in 'echo x > .vbw/record.json' 'echo x >> .vbw/record.json' 'true && echo x > .vbw/record.json' 'jq . x.json 2> .vbw/record.json' \
           'cp x.json .vbw/record.json' 'mv x.json .vbw/record.json' 'install -m 644 x.json .vbw/record.json' 'tee .vbw/record.json < x.json' 'cat x.json | tee -a .vbw/record.json' \
           'sed -i "" s/open/proven/ .vbw/record.json' 'perl -i -pe s/open/proven/ .vbw/record.json' 'ed -s .vbw/record.json' \
           'rm -f .vbw/record.json' 'truncate -s 0 .vbw/record.json' 'shred -u .vbw/record.json' 'dd if=x.json of=.vbw/record.json' 'ln -sf x.json .vbw/record.json'; do
    got=$(reason "$c")
    [ "$got" = "$RECORD_LINE" ] || { printf 'a write was not refused as a write of the record: %s\n  %s\n' "$c" "$got"; false; }
  done
}

@test "R276: an inline program (-c, -e) that names the record is refused, and the reason says the guard cannot tell a read from a write" {
  local c got
  for c in 'python3 -c "open(\".vbw/record.json\", \"w\").write(\"{}\")"' 'python3 -c "print(open(\".vbw/record.json\").read())"' \
           'node -e "require(\"fs\").readFileSync(\".vbw/record.json\")"' 'perl -e "open(F, q(.vbw/record.json))"'; do
    got=$(bash_call "$c" | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow"')
    [[ "$got" == "VBW guard: "* ]] || { printf 'not refused: %s\n  %s\n' "$c" "$got"; false; }
    [[ "$got" == *"cannot tell a read from a write"* ]] || { printf 'the reason does not say the guard cannot tell a read from a write: %s\n  %s\n' "$c" "$got"; false; }
  done
}

@test "R276: the file tools' guard is unchanged: Write and Edit on the record are refused, Read passes" {
  run file_call Write "$PROJECT/.vbw/record.json"
  denied
  run file_call Edit "$PROJECT/.vbw/record.json"
  denied
  run file_call Read "$PROJECT/.vbw/record.json"
  [ -z "$output" ]
}
