#!/usr/bin/env bats
# F6 (R21): the contributor files name only vbw commands that exist: every
# backticked `vbw NAME ...` must be a command `plugin/bin/vbw help` lists.

load helper

CHECK="$BATS_TEST_DIRNAME/../tools/check-contributor-files.sh"

setup() {
  vbw_setup
  cd "$PROJECT"
  mkdir -p plugin/bin plugin/skills/vibe
  : > plugin/skills/vibe/SKILL.md
  # A kernel whose help lists two commands.
  printf '#!/usr/bin/env bash\nprintf "usage: vbw <command> [args]\\n\\n  next [--json]     the next step\\n  show VIEW [ID]    a view\\n"\n' > plugin/bin/vbw
  chmod +x plugin/bin/vbw
}

teardown() { vbw_teardown; }

@test "vbw commands the help lists pass" {
  printf 'Run `vbw next --json`, then `vbw show roadmap`.\n' > CONTRIBUTING.md
  run bash "$CHECK" "$PROJECT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a vbw command the help does not list fails and is named" {
  printf 'Run `vbw nonesuch --now`.\n' > AGENTS.md
  run bash "$CHECK" "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw nonesuch"* ]]
}

@test "a vbw command after a variable assignment is checked too" {
  printf 'Run `VBW_SESSION_ID=x vbw gone`.\n' > AGENTS.md
  run bash "$CHECK" "$PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vbw gone"* ]]
}
