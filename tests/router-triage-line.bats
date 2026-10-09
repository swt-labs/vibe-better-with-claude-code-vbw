#!/usr/bin/env bats
# R135 (L1): the router's line that sends every new request to vbw:triage reads
# as a correct sentence whatever the user typed after /vbw:vibe: nothing, one
# word, a long sentence, or text with punctuation or parentheses. Claude Code
# puts the user's words where the skill says $ARGUMENTS; this renders the
# router with each and checks the triage paragraph. The router stays within
# its budget (1,400 words, about 2k tokens; decision D161).

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

# triage_paragraph ARGUMENTS: the router's paragraph that sends new requests to
# vbw:triage, with $ARGUMENTS replaced by ARGUMENTS as Claude Code does.
triage_paragraph() {
  awk -v a="$1" 'BEGIN { RS = "" } {
      out = ""; s = $0
      while ((i = index(s, "$ARGUMENTS")) > 0) { out = out substr(s, 1, i - 1) a; s = substr(s, i + 10) }
      out = out s
      if (index(out, "vbw:triage") && out ~ /new request/) { print out; exit }
    }' "$ROUTER" | tr '\n' ' ' | sed 's/ *$//'
}

# well_formed TEXT: no empty or padded parenthesis, no stray punctuation, the
# parentheses balanced, a capital first letter and a full stop at the end.
well_formed() {
  local t="$1" open close
  [ -n "$t" ] || { echo "no triage paragraph"; return 1; }
  case "$t" in
    *"()"* | *"( "* | *" )"* | *" ,"* | *",,"* | *" ;"* | *" ."* | *"  "*) echo "broken: $t"; return 1 ;;
  esac
  open=$(printf '%s' "$t" | tr -cd '(' | wc -c | tr -d ' ')
  close=$(printf '%s' "$t" | tr -cd ')' | wc -c | tr -d ' ')
  [ "$open" -eq "$close" ] || { echo "unbalanced parentheses: $t"; return 1; }
  printf '%s' "$t" | grep -qE '^[A-Z`*"]' || { echo "does not start a sentence: $t"; return 1; }
  printf '%s' "$t" | grep -qE '[.!?]$' || { echo "does not end a sentence: $t"; return 1; }
}

@test "R135: the triage line reads correctly when the user typed nothing after /vbw:vibe" {
  well_formed "$(triage_paragraph "")"
}

@test "R135: the triage line reads correctly after a single word" {
  well_formed "$(triage_paragraph "dark")"
}

@test "R135: the triage line reads correctly after a long sentence" {
  well_formed "$(triage_paragraph "please add a page where a customer can see every order they placed in the last two years and download each receipt as a PDF")"
}

@test "R135: the triage line reads correctly after text with punctuation or parentheses" {
  local a
  for a in "fix the login (it breaks on Safari)" "add search; then filters, sorting." "what's next?" "x)" "(" "a, b, and c!"; do
    well_formed "$(triage_paragraph "$a")" || { echo "for: $a"; false; }
  done
}

@test "R135: the router still sends every new request to vbw:triage and stays within its 1,400-word budget" {
  local p words
  p=$(triage_paragraph "dark")
  # shellcheck disable=SC2016 # the backticks are the router's literal text
  [[ "$p" == *'`vbw:triage`'* ]] || { echo "$p"; false; }
  words=$(wc -w < "$ROUTER" | tr -d ' ')
  [ "$words" -le 1400 ] || { echo "router: $words words"; false; }
}
