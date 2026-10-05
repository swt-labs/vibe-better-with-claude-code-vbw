# Shared setup for the R61 tests (approval from a choice): a project with a
# contract that is ready to approve and not yet approved.

approve_choice_project() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1"]}],
   "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]}],
   "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}],
   "rules": [{"req": "R1", "text": "paid is written", "check": "C1"}]}' | "$VBW" apply > /dev/null
}

# fingerprint: the short fingerprint (12 characters) of the current contract.
fingerprint() { local h; h=$(vbw_contract_hash); printf '%s' "${h:0:12}"; }

# approved_count: how many "Contract approved" entries the decision log holds.
approved_count() {
  jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' .vbw/record.json
}

# contract_state: "approved" or "NOT APPROVED", as vbw show contract says.
contract_state() { "$VBW" show contract < /dev/null | sed -n '1s/^contract [0-9a-f]* (\(.*\))$/\1/p'; }

# answer_hook QUESTION ANSWER [TOOL [EXTRA_JSON]]: the PostToolUse hook of
# hooks.json, given what Claude Code sends after the user answers a question.
answer_hook() {
  jq -nc --arg q "$1" --arg a "$2" --arg t "${3:-AskUserQuestion}" --arg d "$PROJECT" --argjson x "${4:-\{\}}" \
    '{hook_event_name: "PostToolUse", session_id: "s1", cwd: $d, tool_name: $t,
      tool_input: {questions: [{question: $q, header: "Approval", multiSelect: false,
        options: [{label: "Approve", description: "approve it"}, {label: "Not yet", description: "change something"}]}]},
      tool_response: {answers: {($q): $a}}} + $x' | vbw_hook PostToolUse AskUserQuestion
}
