#!/usr/bin/env bats
# R116 (docs/rigor.md, docs/next.md): a request that names one or two files and
# no risk path is offered the small-change path (one express phase, one plan
# and its check, approved once) before any planning workflow starts, also
# inside a milestone that already has other work: whether it is small is judged
# on the requirements that have no phase yet. vbw apply --add adds that one
# phase and leaves the rest of the milestone as it is. A larger or riskier
# request still goes to planning. L1: the kernel on fixtures and the router's
# text; the real app is tests/l3-smallchange-added.bats.

load helper
load rigor-helper

teardown() { vbw_teardown; }

# big_repo: a git project tracking more than 30 files, with existing code and a
# project test command; no requirements yet.
big_repo() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p many src tests
  local i
  for ((i = 1; i <= 40; i++)); do printf '%s\n' "$i" > "many/f$i.txt"; done
  printf 'x\n' > src/app.js
  git add many src && git commit -q -m "chore(test): a real-sized repository"
  edit_record '.commands.test = ["true"]'
}

# spec LINE...: the spec's requirements are exactly these lines; synced.
spec() {
  { printf '# Notes\n\n## Requirements\n\n'; printf -- '- %s\n' "$@"; } > .vbw/spec.md
  "$VBW" spec sync > /dev/null
}

# prior: R1 and R2 of the milestone are planned (phase P1, one plan each) and
# R1's plan is done; the request comes after them.
PRIOR1='R1 [auto] Visitors can read the first note'
PRIOR2='R2 [auto] Visitors can read the second note'
prior() {
  spec "$PRIOR1" "$PRIOR2" "$@"
  printf 'true\n' > tests/n1.sh
  printf 'true\n' > tests/n2.sh
  jq -nc '{phases: [{id: "P1", title: "Notes", reqs: ["R1", "R2"], goal: "Notes", criteria: ["notes"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "First", reqs: ["R1"], files: ["src/n1.txt"], after: [], tasks: ["first"]},
            {id: "P1.2", phase: "P1", title: "Second", reqs: ["R2"], files: ["src/n2.txt"], after: [], tasks: ["second"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/n1.sh"], files: ["tests/n1.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/n2.sh"], files: ["tests/n2.sh"]}],
    rules: [{req: "R1", text: "first", check: "C1"}, {req: "R2", text: "second", check: "C2"}]}' | "$VBW" apply > /dev/null
  edit_record '(.plans[] | select(.id == "P1.1")).status = "done" | (.requirements[] | select(.id == "R1")).status = "proven"'
}

# small: vbw next --json is the plan step; prints detail.small.
small() {
  run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf '%s' "$output" | jq -e '.action == "plan"' > /dev/null || { echo "$output"; return 1; }
  printf '%s' "$output" | jq -r '.detail.small'
}

# part EXPR: a part of the record in canonical form.
part() { jq -cS "$1" .vbw/record.json; }

@test "R116: one new [auto] requirement naming one file, added to a milestone with planned and proven requirements, is small" {
  big_repo
  prior 'R3 [auto] greet.sh prints HELLO, ANA! for --shout Ana'
  [ "$(small)" = true ] || { small; false; }
}

@test "R116: a [human] requirement already planned in the milestone does not make a new small request big" {
  big_repo
  prior 'R3 [auto] greet.sh prints HELLO, ANA! for --shout Ana'
  edit_record '(.requirements[] | select(.id == "R2")) |= (.proof = "human" | del(.rules)) | .checks |= map(select(.req != "R2"))'
  [ "$(small)" = true ] || { small; false; }
}

@test "R116: one or two new [auto] requirements naming one or two files and no risk are small" {
  big_repo
  spec 'R1 [auto] greet.sh prints HELLO, ANA! for --shout Ana'
  [ "$(small)" = true ]
  spec 'R1 [auto] src/total.js adds the tax' 'R2 [auto] src/total.js rounds to cents and README.md says how'
  [ "$(small)" = true ]
}

@test "R116: a request naming three or more files is not small" {
  big_repo
  spec 'R1 [auto] src/a.js, src/b.js and src/c.js show the total'
  [ "$(small)" = false ] || { small; false; }
  # Counted over the whole request: two requirements naming three files together.
  spec 'R1 [auto] src/a.js shows the total' 'R2 [auto] src/b.js and lib/c.py round it'
  [ "$(small)" = false ] || { small; false; }
  # The same file named twice is one file.
  spec 'R1 [auto] src/a.js shows the total' 'R2 [auto] src/a.js rounds it'
  [ "$(small)" = true ] || { small; false; }
}

@test "R116: a request naming a risk-path file or a risk category is not small" {
  big_repo
  local text
  for text in 'R1 [auto] .github/workflows/ci.yml runs on pull requests' 'R1 [auto] the app reads its port from .env' \
    'R1 [auto] Visitors can log in with a password' 'R1 [auto] app.js takes the payment' 'R1 [auto] Old notes are deleted after a year'; do
    spec "$text"
    [ "$(small)" = false ] || { echo "$text"; small; false; }
  done
}

@test "R116: three or more new requirements, or a new [human] one, are not small" {
  big_repo
  spec 'R1 [auto] a.js shows one' 'R2 [auto] a.js shows two' 'R3 [auto] a.js shows three'
  [ "$(small)" = false ] || { small; false; }
  spec 'R1 [auto] a.js shows one' 'R2 [human] a.js looks friendly'
  [ "$(small)" = false ] || { small; false; }
  big_repo
  prior 'R3 [auto] a.js shows one' 'R4 [auto] a.js shows two' 'R5 [auto] a.js shows three'
  [ "$(small)" = false ] || { small; false; }
}

@test "R116: rigor forced to standard or deep is never small; auto and express keep the rules" {
  big_repo
  spec 'R1 [auto] greet.sh prints HELLO, ANA! for --shout Ana'
  local mode
  for mode in standard deep; do
    "$VBW" config rigor "$mode" > /dev/null
    [ "$(small)" = false ] || { echo "$mode"; small; false; }
  done
  for mode in auto express; do
    "$VBW" config rigor "$mode" > /dev/null
    [ "$(small)" = true ] || { echo "$mode"; small; false; }
  done
  spec 'R1 [auto] src/a.js, src/b.js and src/c.js show the total'
  [ "$(small)" = false ] || { small; false; }
}

@test "R116: vbw apply --add adds one express phase to a milestone with started work; every other phase, plan, check and rule stays as it was" {
  big_repo
  prior 'R3 [auto] greet.sh prints HELLO, ANA! for --shout Ana'
  local phases plans checks rules
  phases=$(part '[.phases[] | select(.id != "P2")]'); plans=$(part '[.plans[] | select(.phase != "P2")]')
  checks=$(part '[.checks[] | select(.req != "R3")]'); rules=$(part '[.requirements[] | select(.id != "R3") | .rules]')
  printf 'true\n' > tests/shout.sh
  printf '%s' '{"phases": [{"id": "P2", "title": "Shout", "reqs": ["R3"], "tier": "express"}],
    "plans": [{"id": "P2.1", "phase": "P2", "title": "Shout", "reqs": ["R3"], "files": ["greet.sh"], "after": [], "tasks": ["--shout prints capitals"]}],
    "checks": [{"id": "C3", "req": "R3", "run": ["sh", "tests/shout.sh"], "files": ["tests/shout.sh"]}],
    "rules": [{"req": "R3", "text": "--shout Ana prints HELLO, ANA!", "check": "C3"}]}' | "$VBW" apply --add
  [ "$(part '[.phases[] | select(.id != "P2")]')" = "$phases" ]
  [ "$(part '[.plans[] | select(.phase != "P2")]')" = "$plans" ]
  [ "$(part '[.checks[] | select(.req != "R3")]')" = "$checks" ]
  [ "$(part '[.requirements[] | select(.id != "R3") | .rules]')" = "$rules" ]
  jq -e '(.phases[] | select(.id == "P2")).tier == "express" and ([.plans[] | select(.phase == "P2") | .id] == ["P2.1"])
    and any(.checks[]; .id == "C3") and ((.requirements[] | select(.id == "R3")).rules | length) == 1' .vbw/record.json
}

@test "R116: vbw apply --add refuses a phase that exists, a requirement that already has a phase, and changes nothing" {
  big_repo
  prior 'R3 [auto] greet.sh prints HELLO, ANA! for --shout Ana'
  local before
  before=$(cksum < .vbw/record.json)
  run bash -c 'printf "%s" "{\"phases\": [{\"id\": \"P1\", \"title\": \"Shout\", \"reqs\": [\"R3\"]}], \"plans\": [{\"id\": \"P1.9\", \"phase\": \"P1\", \"title\": \"x\", \"reqs\": [\"R3\"], \"files\": [\"greet.sh\"], \"after\": []}], \"checks\": [], \"rules\": []}" | "$1" apply --add' _ "$VBW"
  [ "$status" -ne 0 ]
  [[ "$output" == *P1* ]] || { echo "$output"; false; }
  run bash -c 'printf "%s" "{\"phases\": [{\"id\": \"P2\", \"title\": \"Again\", \"reqs\": [\"R2\"]}], \"plans\": [{\"id\": \"P2.1\", \"phase\": \"P2\", \"title\": \"x\", \"reqs\": [\"R2\"], \"files\": [\"src/x.txt\"], \"after\": []}], \"checks\": [], \"rules\": []}" | "$1" apply --add' _ "$VBW"
  [ "$status" -ne 0 ]
  [[ "$output" == *R2* || "$output" == *P2* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R116: in a repository tracking more than 30 files, an express phase over more than two files is refused, through --add as through a full apply" {
  big_repo
  prior 'R3 [auto] greet.sh prints HELLO, ANA! for --shout Ana'
  local before
  before=$(cksum < .vbw/record.json)
  printf 'true\n' > tests/shout.sh
  run bash -c 'printf "%s" "{\"phases\": [{\"id\": \"P2\", \"title\": \"Shout\", \"reqs\": [\"R3\"], \"tier\": \"express\"}], \"plans\": [{\"id\": \"P2.1\", \"phase\": \"P2\", \"title\": \"Shout\", \"reqs\": [\"R3\"], \"files\": [\"greet.sh\", \"src/a.js\", \"src/b.js\"], \"after\": []}], \"checks\": [{\"id\": \"C3\", \"req\": \"R3\", \"run\": [\"sh\", \"tests/shout.sh\"], \"files\": [\"tests/shout.sh\"]}], \"rules\": [{\"req\": \"R3\", \"text\": \"shouts\", \"check\": \"C3\"}]}" | "$1" apply --add' _ "$VBW"
  [ "$status" -ne 0 ]
  [[ "$output" == *"floor at standard"* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R116: vbw apply --add judges only the phases it brings: a finished express phase whose floor is now standard keeps its tier, plans and status" {
  # P1 is express over three files while the repository is small; once it
  # tracks more than 30 files those three files set P1's floor at standard.
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  edit_record '.commands.test = ["true"]'
  spec 'R1 [auto] Visitors can read the notes'
  mkdir -p tests
  printf 'true\n' > tests/n1.sh
  printf 'true\n' > tests/n2.sh
  jq -nc '{phases: [{id: "P1", title: "Notes", reqs: ["R1"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Notes", reqs: ["R1"], files: ["src/a.js", "src/b.js", "src/c.js"], after: [], tasks: ["notes"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/n1.sh"], files: ["tests/n1.sh"]}],
    rules: [{req: "R1", text: "notes", check: "C1"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  edit_record '(.plans[] | select(.id == "P1.1")).status = "done" | (.requirements[] | select(.id == "R1")).status = "proven"'
  mkdir -p many src
  local i
  for ((i = 1; i <= 40; i++)); do printf '%s\n' "$i" > "many/f$i.txt"; done
  printf 'one\n' > src/a.js
  git add many src && git commit -q -m "chore(test): the repository grows"
  "$VBW" spec add auto "src/a.js says two" > /dev/null
  local phase plans
  phase=$(part '.phases[] | select(.id == "P1")'); plans=$(part '[.plans[] | select(.phase == "P1")]')
  # The new express phase shares src/a.js with P1.
  run bash -c 'printf "%s" "{\"phases\": [{\"id\": \"P2\", \"title\": \"Two\", \"reqs\": [\"R2\"], \"tier\": \"express\"}], \"plans\": [{\"id\": \"P2.1\", \"phase\": \"P2\", \"title\": \"Two\", \"reqs\": [\"R2\"], \"files\": [\"src/a.js\"], \"after\": [], \"tasks\": [\"two\"]}], \"checks\": [{\"id\": \"C2\", \"req\": \"R2\", \"run\": [\"sh\", \"tests/n2.sh\"], \"files\": [\"tests/n2.sh\"]}], \"rules\": [{\"req\": \"R2\", \"text\": \"two\", \"check\": \"C2\"}]}" | "$1" apply --add' _ "$VBW"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(part '.phases[] | select(.id == "P1")')" = "$phase" ]
  [ "$(part '[.plans[] | select(.phase == "P1")]')" = "$plans" ]
  jq -e '(.phases[] | select(.id == "P2")).tier == "express" and ([.plans[] | select(.phase == "P2") | .id] == ["P2.1"])' .vbw/record.json
}

@test "R116: a small request added mid-milestone goes from plan to done with one approval" {
  big_repo
  spec "$PRIOR1"
  printf 'grep -qx one src/n1.txt\n' > tests/n1.sh
  printf 'start\n' > src/n1.txt
  git add tests src && git commit -q -m "chore(test): note"
  printf '%s' '{"phases": [{"id": "P1", "title": "Note", "reqs": ["R1"], "tier": "express"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Note", "reqs": ["R1"], "files": ["src/n1.txt"], "after": [], "tasks": ["one"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/n1.sh"], "files": ["tests/n1.sh"]}],
    "rules": [{"req": "R1", "text": "the note says one", "check": "C1"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'one\n' > src/n1.txt
  "$VBW" commit P1.1 "feat(note): one" > /dev/null
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null
  jq -e '(.requirements[] | select(.id == "R1")).status == "proven"' .vbw/record.json
  # The request: one more requirement, naming one file.
  "$VBW" spec add auto "src/n2.txt says two" > /dev/null
  local approvals
  approvals=$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' .vbw/record.json)
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "plan" and .detail.small == true and .next_phase == 2' || { echo "$output"; false; }
  printf 'grep -qx two src/n2.txt\n' > tests/n2.sh
  printf '%s' '{"phases": [{"id": "P2", "title": "Second note", "reqs": ["R2"], "tier": "express"}],
    "plans": [{"id": "P2.1", "phase": "P2", "title": "Second note", "reqs": ["R2"], "files": ["src/n2.txt"], "after": [], "tasks": ["two"]}],
    "checks": [{"id": "C2", "req": "R2", "run": ["sh", "tests/n2.sh"], "files": ["tests/n2.sh"]}],
    "rules": [{"req": "R2", "text": "the second note says two", "check": "C2"}]}' | "$VBW" apply --add > /dev/null
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "approve"' || { echo "$output"; false; }
  "$VBW" approve > /dev/null
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "build" and .detail.plans == ["P2.1"]' || { echo "$output"; false; }
  printf 'two\n' > src/n2.txt
  "$VBW" commit P2.1 "feat(note): two" > /dev/null
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P2.1 > /dev/null
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "ship"' || { echo "$output"; false; }
  [ "$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' .vbw/record.json)" -eq $((approvals + 1)) ]
}

@test "R116: the router takes the small path with vbw apply --add numbered from next_phase and no planning workflow; anything else plans as before" {
  local r="$PLUGIN_ROOT/skills/vibe/SKILL.md" small
  small=$(sed -n '/^\*\*plan\*\* with `detail.tier` express or `detail.small`/,/^\*\*plan\*\*: /p' "$r")
  [ -n "$small" ]
  printf '%s' "$small" | grep -q 'no planning workflow'
  printf '%s' "$small" | grep -q 'vbw apply --add'
  printf '%s' "$small" | grep -q 'next_phase'
  printf '%s' "$small" | grep -qi 'approve'
  printf '%s' "$small" | grep -qiE 'over two files|risk path'
  grep -q 'Workflow `vbw:planning`' "$r"
  grep -q 'apply --add' "$REPO_ROOT/docs/workflows.md"
  grep -qiE 'no phase yet|not in any phase|without a phase' "$REPO_ROOT/docs/rigor.md"
  grep -qiE 'names? (one or two|at most two) files' "$REPO_ROOT/docs/rigor.md"
  grep -qiE 'no phase yet|not in any phase|without a phase' "$REPO_ROOT/docs/next.md"
}
