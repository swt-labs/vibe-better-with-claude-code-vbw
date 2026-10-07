#!/usr/bin/env bash
# Runs when approve-answer.jq found the user's answer to the approval question
# (hooks.json). $1 is its {fp, answer}. Only the exact answer "Approve"
# approves, and only the contract the question named (vbw approve --hash);
# every other answer and every failure changes nothing and says why in one
# sentence. Prints the PostToolUse output: systemMessage for the user,
# additionalContext for Claude.

fp=$(jq -r .fp <<< "$1")
answer=$(jq -r .answer <<< "$1")
root=${CLAUDE_PROJECT_DIR:-$PWD}
vbw="${0%/*}/../bin/vbw"

# say USER_SENTENCE CLAUDE_CONTEXT
say() {
  jq -nc --arg m "$1" --arg c "$2" \
    '{systemMessage: $m, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
  exit 0
}

[ -f "$root/.vbw/record.json" ] || exit 0

if [ "$answer" != "Approve" ]; then
  if [ "$answer" = "Not yet" ]; then
    say "Not approved. Tell VBW what to change." \
      "The user answered Not yet to approving contract $fp: it is not approved. Ask what to change, then change it and ask again."
  fi
  say "Not approved: your words were taken as what to change." \
    "The user did not choose Approve for contract $fp, so it is not approved. They wrote: $answer. Treat that as what to change, change it, and ask again."
fi

if out=$(cd "$root" && "$vbw" approve --hash "$fp" 2>&1 < /dev/null); then
  case "$out" in
    *"already approved"*) say "Contract $fp was already approved." "$out" ;;
    *) say "Approved contract $fp." "Contract $fp is approved by the user's answer. $out" ;;
  esac
fi
why=$(printf '%s' "$out" | sed 's/^vbw: //' | tr '\n' ' ' | sed 's/  */ /g; s/ $//; s/[.:;] *$//')
say "Nothing was approved: $why. Once that is fixed, VBW asks again with the approval menu." \
  "The user chose Approve for contract $fp but nothing was approved: $out. Tell the user why, then ask again with the approval menu (AskUserQuestion, the question vbw show contract prints) once it is fixed; vbw show contract shows what they approve."
