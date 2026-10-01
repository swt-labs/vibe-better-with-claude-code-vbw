#!/usr/bin/env bats
# The vbw CLI core: dispatch, init, the single validated writer, corruption.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "vbw version prints the plugin version" {
  vbw_run version
  [ "$status" -eq 0 ]
  [ "$output" = "$(jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json")" ]
}

@test "vbw without arguments prints usage and exits 2" {
  vbw_run
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: vbw"* ]]
}

@test "an unknown subcommand exits 2 and names it" {
  vbw_run frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: frobnicate"* ]]
}

@test "vbw init needs a git repository" {
  vbw_run init
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git repository"* ]]
  [ ! -e .vbw ]
}

@test "vbw init scaffolds .vbw with a valid record and ignores the runtime dir" {
  vbw_git_project
  vbw_run init
  [ "$status" -eq 0 ]
  [ -f .vbw/spec.md ]
  [ -d .vbw/runtime ]
  [ "$(jq -c -f "$PLUGIN_ROOT/lib/record.jq" .vbw/record.json)" = "[]" ]
  [ "$(jq -r .project.name .vbw/record.json)" = "project with space" ]
  [ "$(cat .vbw/.gitignore)" = "runtime/" ]
  [ ! -e .gitignore ]
  git check-ignore -q .vbw/runtime/x
}

@test "vbw init is idempotent and never overwrites existing state" {
  vbw_git_project
  vbw_run init
  printf 'my spec edits\n' >> .vbw/spec.md
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run init
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
  grep -q 'my spec edits' .vbw/spec.md
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  [ "$(cat .vbw/.gitignore)" = "runtime/" ]
}

@test "vbw init writes nothing outside the project" {
  vbw_git_project
  local before after
  before=$(cd "$TEST_ROOT" && find . -path './project with space' -prune -o -print | LC_ALL=C sort)
  vbw_run init
  [ "$status" -eq 0 ]
  after=$(cd "$TEST_ROOT" && find . -path './project with space' -prune -o -print | LC_ALL=C sort)
  [ "$before" = "$after" ]
}

@test "a corrupt record is reported, never repaired" {
  vbw_git_project
  vbw_run init
  jq '.requirements = [{"id":"R1"}]' .vbw/record.json > "$TEST_ROOT/bad.json"
  cp "$TEST_ROOT/bad.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  [[ "$output" == *"record is corrupt"* ]]
  cmp .vbw/record.json "$TEST_ROOT/bad.json"
}

@test "unparseable JSON is reported as corrupt" {
  vbw_git_project
  vbw_run init
  printf '{not json' > .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  [[ "$output" == *"record is corrupt"* ]]
}

@test "commands outside a VBW project say so" {
  vbw_git_project
  vbw_run status
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a VBW project"* ]]
}

@test "concurrent writers never lose an update" {
  vbw_git_project
  vbw_run init
  local i
  # 40 writers: 20 hid a lost-update race that CI found (2.0.2; see vbw_is_stale).
  for i in $(seq 1 40); do "$VBW" todo add "task $i" < /dev/null > /dev/null & done
  wait
  [ "$(jq '.todos | length' .vbw/record.json)" -eq 40 ]
  [ "$(jq '[.todos[].id] | unique | length' .vbw/record.json)" -eq 40 ]
  [ "$(jq -c -f "$PLUGIN_ROOT/lib/record.jq" .vbw/record.json)" = "[]" ]
  [ -z "$(find .vbw/runtime -name 'record.*' 2>/dev/null)" ]
}

@test "a write that would make the record invalid is refused and leaves it untouched" {
  vbw_git_project
  vbw_run init
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run todo add ""
  [ "$status" -ne 0 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "a stale lock older than 30 seconds is taken over" {
  vbw_git_project
  vbw_run init
  mkdir .vbw/runtime/lock
  touch -t "$(date -v-2M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-2 minutes' +%Y%m%d%H%M.%S)" .vbw/runtime/lock
  vbw_run todo add "after a crash"
  [ "$status" -eq 0 ]
  [ "$(jq '.todos | length' .vbw/record.json)" -eq 1 ]
}

@test "vbw works from a subdirectory of the project" {
  vbw_git_project
  vbw_run init
  mkdir -p src/deep
  cd src/deep
  vbw_run todo add "from below"
  [ "$status" -eq 0 ]
  cd "$PROJECT"
  [ "$(jq -r '.todos[0].text' .vbw/record.json)" = "from below" ]
}

@test "file ages are numbers on every platform's stat (Linux stat -f is not BSD stat -f)" {
  : > "$TEST_ROOT/f"
  run bash -c '. "$1/lib/core.sh"; vbw_mtime "$2"' _ "$PLUGIN_ROOT" "$TEST_ROOT/f"
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 1000000000 ]
  run bash -c '. "$1/lib/core.sh"; vbw_mtime "$2"' _ "$PLUGIN_ROOT" "$TEST_ROOT/missing"
  [ "$output" = 0 ]
}

@test "a lock whose age cannot be read is never stale (it may have just been taken)" {
  vbw_git_project
  vbw_run init
  mkdir .vbw/runtime/lock
  # The age read fails, as when the lock vanishes and reappears between two looks.
  run vbw_kernel '. "$VBW_LIB/record.sh"; vbw_mtime() { printf "0\n"; }; vbw_is_stale .vbw/runtime/lock && echo stale || echo fresh'
  [ "$output" = fresh ]
  # A readable old age is stale; a missing lock is not.
  run vbw_kernel '. "$VBW_LIB/record.sh"; vbw_mtime() { printf "1\n"; }; vbw_is_stale .vbw/runtime/lock && echo stale || echo fresh'
  [ "$output" = stale ]
  rmdir .vbw/runtime/lock
  run vbw_kernel '. "$VBW_LIB/record.sh"; vbw_is_stale .vbw/runtime/lock && echo stale || echo fresh'
  [ "$output" = fresh ]
}
