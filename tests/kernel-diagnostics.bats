#!/usr/bin/env bats
# P2 / R3: vbw report and vbw rtk do what `vbw help` says, and docs/diagnostics.md
# says the same. Help claims:
#   rtk [status]  the state of RTK (command-output compression)
#   report        diagnostic facts for a bug report about VBW (no spec text or code)

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

@test "report: versions, doctor, and project state as counts and ids" {
  "$VBW" init > /dev/null
  vbw_run report
  [ "$status" -eq 0 ]
  [[ "$output" == *"- VBW $("$VBW" version)"* ]]
  [[ "$output" == *"### vbw doctor"* ]]
  [[ "$output" == *"milestone M1 active"* ]]
  [[ "$output" == *"checks: 0"* ]]
}

@test "report: an empty count says none, never a blank" {
  "$VBW" init > /dev/null
  vbw_run report
  [ "$status" -eq 0 ]
  [[ "$output" == *"plans: none"* ]]
  [[ "$output" == *"fixes: none"* ]]
}

@test "report: never the spec's text, check output or file contents" {
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] SECRETSPECTEXT checkout works\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'SECRETFILECONTENT\n' > app.txt
  vbw_run report
  [ "$status" -eq 0 ]
  [[ "$output" != *SECRETSPECTEXT* ]]
  [[ "$output" != *SECRETFILECONTENT* ]]
}

@test "report: a corrupt record is named as corrupt without echoing its content" {
  "$VBW" init > /dev/null
  printf '{"secret": "SECRETRECORDTEXT' > "$TEST_ROOT/bad.json"
  cp "$TEST_ROOT/bad.json" .vbw/record.json
  vbw_run report
  [ "$status" -eq 0 ]
  [[ "$output" != *SECRETRECORDTEXT* ]]
  [[ "$output" == *"corrupt"* ]]
}

@test "report: outside a git repository it still prints, and says so" {
  cd "$TEST_ROOT"
  vbw_run report
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Environment"* ]]
  [[ "$output" == *"not inside a git repository"* ]]
}

@test "report and rtk take no arguments beyond their usage" {
  vbw_run report extra
  [ "$status" -eq 2 ]
  vbw_run rtk bogus
  [ "$status" -eq 2 ]
}

@test "rtk: not installed, with the install command that matches the machine" {
  mkdir -p "$TEST_ROOT/empty"
  run env PATH="$TEST_ROOT/empty:/usr/bin:/bin" "$VBW" rtk status
  [ "$status" -eq 0 ]
  [[ "$output" == *"rtk: not installed"* ]]
  [[ "$output" == *"install with:"* ]]
  [[ "$output" == *"claude hook: off"* ]]
}

@test "rtk: installed shows its version and path; status equals no argument" {
  mkdir -p "$TEST_ROOT/bin"
  printf '#!/bin/sh\necho "rtk 9.9.9"\n' > "$TEST_ROOT/bin/rtk"
  chmod +x "$TEST_ROOT/bin/rtk"
  PATH="$TEST_ROOT/bin:$PATH" run "$VBW" rtk
  [ "$status" -eq 0 ]
  [[ "$output" == *"rtk: installed (rtk 9.9.9, $TEST_ROOT/bin/rtk)"* ]]
  local plain="$output"
  PATH="$TEST_ROOT/bin:$PATH" run "$VBW" rtk status
  [ "$output" = "$plain" ]
}

@test "rtk: the Claude hook is on only when RTK's hook is in the user's settings" {
  vbw_run rtk
  [[ "$output" == *"claude hook: off"* ]]
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
  vbw_run rtk
  [[ "$output" == *"claude hook: on"* ]]
}

@test "rtk and report write nothing: no file in the project or settings changes" {
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
  printf '{}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
  vbw_run rtk
  vbw_run report
  [ -z "$(git status --porcelain)" ]
  [ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = "{}" ]
}

@test "docs/diagnostics.md says what the help says about both commands" {
  [ -f "$REPO_ROOT/docs/diagnostics.md" ]
  local line
  for line in "$("$VBW" help | grep -E '^  rtk ')" "$("$VBW" help | grep -E '^  report ')"; do
    # the description is the help line after the command's own words
    local desc
    desc=$(printf '%s' "$line" | sed -E 's/^  (rtk \[status\]|report) +//')
    grep -qF "$desc" "$REPO_ROOT/docs/diagnostics.md"
  done
  grep -q 'vbw report' "$REPO_ROOT/docs/diagnostics.md"
  grep -q 'vbw rtk' "$REPO_ROOT/docs/diagnostics.md"
}
