# PreToolUse gate on AskUserQuestion (R114): passes the hook input through when
# the user (no agent_type) is asked the approval menu (options Approve and Not
# yet) in a question that does not start with "Approve contract <fingerprint>?";
# prints nothing for any other call. approve-ask.sh then adds the fingerprint.
select(.tool_name == "AskUserQuestion" and ((.agent_type // "") == "")
  and any((.tool_input.questions // [])[]?;
    ((.options // []) | map(.label) | (index("Approve") != null and index("Not yet") != null))
    and ((.question // "") | test("^Approve contract [^\\s?]+\\?") | not)))
