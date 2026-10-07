#!/usr/bin/env bats
# tools/l3.sh wait: a session is idle when the screen above the prompt box stops
# changing. The status line under the box refreshes on its own every 5 seconds
# (statusLine.refreshInterval), so it must not count as a change.

load helper

screen_at() {
  printf '%s\n' "⏺ greet.sh is built." "" "  What I need from you: nothing" \
    "────────────────────" "❯ " "────────────────────" \
    "  [VBW] demo │ M1 ✓ │ 2/2 done" "  Sonnet 5.5 │ $1 (API 1m34s)" "  ⏵⏵ auto mode on"
}

@test "the settled view leaves out the prompt box and everything under it" {
  run bash -c 'printf "%s" "$1" | bash "$2" settled _' _ "$(screen_at 14m55s)" "$REPO_ROOT/tools/l3.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"What I need from you: nothing"* ]]
  [[ "$output" != *"14m55s"* ]]
  [[ "$output" != *"❯"* ]]
  a=$(screen_at 14m55s | bash "$REPO_ROOT/tools/l3.sh" settled _)
  b=$(screen_at 15m00s | bash "$REPO_ROOT/tools/l3.sh" settled _)
  [ "$a" = "$b" ]
}

@test "a screen with no prompt box is kept whole" {
  out=$(printf 'loading\nstill loading\n' | bash "$REPO_ROOT/tools/l3.sh" settled _)
  [ "$out" = "$(printf 'loading\nstill loading')" ]
}
