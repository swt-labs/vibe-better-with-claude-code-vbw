#!/usr/bin/env bash
# Runs when the PreToolUse jq gate in hooks.json found, in an AskUserQuestion
# call, a question with the options Approve and Not yet that does not start
# with "Approve contract <fingerprint>?" (the gate also skips subagents and
# every other question, so the common path costs one jq call). $1 is the hook
# input. When the user (no agent_type) is asked the approval menu (options
# Approve and Not yet) in a question that does not start with
# "Approve contract <fingerprint>?", and the contract waits for approval, it
# prints updatedInput with "Approve contract <12-char fingerprint>? " put in
# front of that question, so the user's Approve approves exactly that
# contract (approve-answer.jq reads it back). Anything else prints nothing.

in=$1
root=${CLAUDE_PROJECT_DIR:-$PWD}
vbw="${0%/*}/../bin/vbw"

[ -f "$root/.vbw/record.json" ] || exit 0
head=$(cd "$root" && "$vbw" show contract < /dev/null 2>/dev/null | sed -n '1p') || exit 0
fp=$(printf '%s' "$head" | sed -n 's/^contract \([0-9a-f]\{12\}\)[0-9a-f]* (NOT APPROVED)$/\1/p')
[ -n "$fp" ] || exit 0

jq -c --arg fp "$fp" '
  .tool_input
  | .questions |= map(
      if ((.options // []) | map(.label) | (index("Approve") != null and index("Not yet") != null))
         and ((.question // "") | test("^Approve contract [^\\s?]+\\?") | not)
      then .question = "Approve contract \($fp)? " + (.question // "") else . end)
  | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: .}}' <<< "$in"
