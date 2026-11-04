# The second pass of a PreToolUse guard (docs/guards.md, "How a command is read"; R254).
# hooks/read.sh runs it once for each project other than the hook's that a write lands in:
# the guard of the call had asked, in a request, which projects hold its targets. It gets the
# project (--arg root), the project's record by the guards' own inputs (the hook input on
# stdin, the record, hooks/end.json; --rawfile glance, --arg open as there), and the absolute
# targets that lie in it (--args). Each is judged as the same write is from inside that
# project, with the same refusal text: another session's open run holds it off (foreign_denial);
# an agent is held to the run's files (lease_write_denial, shell_write_denial for shell text).
# It prints the first refusal as the hook's decision, or nothing. Includes holder and common
# only: a small compile (D564).

include "holder" {search: "../lib"};
include "common" {search: "./"};

guard_context(true) as $g
| select($g.project)
| (if $g.foreign == null then null else holder_name($g.foreign; foreign_stored_name($g.foreign); null) end) as $holder
| ($g.hook.tool_name == "Bash") as $shell
| first(
    $ARGS.positional[] as $t
    | ( (select($g.foreign != null) | $t | project_path(session_dir($g); $root) | foreign_denial($g.foreign; $holder)),
        (select($g.lease != null) | $t | if $shell then shell_write_denial($g) else run_write_denial($g) end) )
    | deny)
