#!/usr/bin/env bash
# Runs when the PreToolUse gate (approve-ask.jq) found, in an AskUserQuestion
# call, a question with the options Approve and Not yet that does not start
# with "Approve contract <fingerprint>?" (the gate also skips subagents and
# every other question, so the common path costs one jq call). $1 is the hook
# input. When the user (no agent_type) is asked the approval menu (options
# Approve and Not yet) in a question that does not start with
# "Approve contract <fingerprint>?", and the contract waits for approval, it
# prints updatedInput with "Approve contract <12-char fingerprint>? " put in
# front of that question, so the user's Approve approves exactly that
# contract (approve-answer.jq reads it back). It asks, never allows: Claude
# Code reads "allow" with updatedInput on AskUserQuestion as the hook answering
# the question itself, so the menu would not be shown (R120). Anything else
# prints nothing.

in=$1
# shellcheck source-path=SCRIPTDIR source=project.sh
. "${0%/*}/project.sh"
vbw_project_of "${CLAUDE_PROJECT_DIR:-$PWD}"
vbw="${0%/*}/../bin/vbw"

[ -f "$root/.vbw/record.json" ] || exit 0
out=$(cd "$root" && "$vbw" show contract < /dev/null 2>&1)
rc=$?
if [ "$rc" -eq 4 ]; then
  # A record this VBW cannot read (written by a newer VBW): the menu could not record an answer.
  # Refuse it with the kernel's own line, to Claude and to the user; never allow (R272).
  line=$(printf '%s\n' "$out" | sed -n '1p')
  line=${line#vbw: }
  jq -nc --arg l "$line" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $l}, systemMessage: $l}'
  exit 0
fi
[ "$rc" -eq 0 ] || exit 0
head=$(printf '%s\n' "$out" | sed -n '1p')
fp=$(printf '%s' "$head" | sed -n 's/^contract \([0-9a-f]\{12\}\)[0-9a-f]* (NOT APPROVED)$/\1/p')
[ -n "$fp" ] || exit 0

jq -c --arg fp "$fp" '
  .tool_input
  | .questions |= map(
      if ((.options // []) | map(.label) | (index("Approve") != null and index("Not yet") != null))
         and ((.question // "") | test("^Approve contract [^\\s?]+\\?") | not)
      then .question = "Approve contract \($fp)? " + (.question // "") else . end)
  | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", updatedInput: .}}' <<< "$in"
