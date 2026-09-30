#!/usr/bin/env bats
# Consent (build plan K16) lives in the clone's git directory, where a
# repository cannot ship it; project commands are detected at init and recorded,
# but nothing runs them until consent is granted by content hash.

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

# The kernel libraries, loaded for this project.
kernel() { vbw_kernel "$1"; }

@test "the consent file lives in the git directory, never the working tree" {
  run kernel 'consent_file'
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd .git && pwd -P)/vbw/consent.json" ] || [ "$output" = "$(cd .git && pwd)/vbw/consent.json" ]
}

@test "linked worktrees share the clone's consent" {
  git worktree add -q "$TEST_ROOT/wt" -b other
  local main wt
  main=$(kernel 'consent_file')
  cd "$TEST_ROOT/wt"
  wt=$(kernel 'consent_file')
  [ "$main" = "$wt" ]
}

@test "grant then has; a different hash is not consented" {
  run kernel 'consent_grant command "$(vbw_sha256_argv npm test)" "[\"npm\",\"test\"]" && consent_has command "$(vbw_sha256_argv npm test)" && echo yes'
  [ "$output" = "yes" ]
  run kernel 'consent_has command "$(vbw_sha256_argv npm run evil)" || echo no'
  [ "$output" = "no" ]
}

@test "argv hashing is exact: spacing and quoting cannot collide" {
  local a b
  a=$(kernel 'vbw_sha256_argv "a b" c')
  b=$(kernel 'vbw_sha256_argv a "b c"')
  [ "$a" != "$b" ]
  [[ "$a" =~ ^[0-9a-f]{64}$ ]]
}

@test "a consent file committed in the repository is never read" {
  mkdir -p .vbw && printf '{"granted":[{"kind":"command","hash":"x"}]}' > .vbw/consent.json
  run kernel 'consent_has command x || echo no'
  [ "$output" = "no" ]
}

@test "vbw init records detected project commands without consenting to them" {
  printf '{"scripts":{"test":"jest","lint":"eslint .","build":"tsc","start":"node ."}}' > package.json
  vbw_run init
  [ "$status" -eq 0 ]
  jq -e '.commands == {"test":["npm","test"],"lint":["npm","run","lint"],"build":["npm","run","build"]}' .vbw/record.json
  [[ "$output" == *"npm test"* ]]
  [[ "$output" == *"not approved"* ]]
  [ ! -e .git/vbw/consent.json ]
}

# detected_in SETUP: init a fresh repo prepared by SETUP; print its commands.
detected_in() {
  local dir="$TEST_ROOT/eco-$RANDOM"
  mkdir -p "$dir" && cd "$dir" && git init -q && eval "$1" && "$VBW" init > /dev/null && jq -c .commands .vbw/record.json
}

@test "vbw init detects Go, Rust, Python and Make projects" {
  run detected_in 'printf "module x\n" > go.mod'
  [ "$output" = '{"test":["go","test","./..."],"lint":["go","vet","./..."],"build":["go","build","./..."]}' ]
  run detected_in 'printf "[package]\n" > Cargo.toml'
  [ "$output" = '{"test":["cargo","test"],"build":["cargo","build"]}' ]
  run detected_in 'printf "[tool.pytest.ini_options]\n" > pyproject.toml'
  [ "$output" = '{"test":["python","-m","pytest"]}' ]
  run detected_in 'printf "test:\n\ttrue\nlint:\n\ttrue\n" > Makefile'
  [ "$output" = '{"test":["make","test"],"lint":["make","lint"]}' ]
}

@test "the JavaScript package manager follows the lockfile" {
  run detected_in 'printf "{\"scripts\":{\"test\":\"x\"}}" > package.json && : > pnpm-lock.yaml'
  [ "$output" = '{"test":["pnpm","test"]}' ]
  run detected_in 'printf "{\"scripts\":{\"test\":\"x\"}}" > package.json && : > yarn.lock'
  [ "$output" = '{"test":["yarn","test"]}' ]
}

@test "a project with nothing detectable records no commands" {
  vbw_run init
  jq -e '.commands == {}' .vbw/record.json
}

@test "the record rejects malformed commands" {
  vbw_run init
  jq '.commands = {"test": []}' .vbw/record.json | jq -c -f "$PLUGIN_ROOT/lib/record.jq" | grep -q 'command test must be a non-empty argv array'
  jq '.commands = {"test": "npm test"}' .vbw/record.json | jq -c -f "$PLUGIN_ROOT/lib/record.jq" | grep -q 'command test must be a non-empty argv array'
}
