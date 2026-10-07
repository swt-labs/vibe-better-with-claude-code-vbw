# PostToolUse hook on AskUserQuestion: reads the hook input and prints one
# compact {fp, answer} when the user answered VBW's approval question
# ("Approve contract <fingerprint>?", optionally followed by a space or line break and any text Claude appended; the fingerprint stays at the start; a malformed one still passes through so the kernel can say why); prints nothing for any other call. Only the
# user's answer in Claude Code's own interface reaches a PostToolUse of
# AskUserQuestion, so nothing the model writes can match. Asked by a subagent
# (agent_type present) never counts. Answers come as a map from question to
# answer (Claude Code's tool_response.answers) or as a list in question order.
select(.tool_name == "AskUserQuestion" and ((.agent_type // "") == ""))
| (.tool_input // {}) as $in
| ([($in.questions // [])[]?.question] | if length > 0 then . else [$in.question // empty] end) as $qs
| (.tool_response.answers // null) as $a
| first(range($qs | length) as $i | $qs[$i] as $q
    | select(($q | type) == "string" and ($q | test("^Approve contract [^\\s?]+\\?(\\s|$)")))
    | ($a | if type == "object" then .[$q] elif type == "array" then .[$i] else null end) as $ans
    | select($ans | type == "string")
    | {fp: ($q | capture("^Approve contract (?<f>[^\\s?]+)\\?").f), answer: $ans})
