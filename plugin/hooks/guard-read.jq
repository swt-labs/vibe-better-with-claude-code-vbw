# The second pass of a PreToolUse guard (docs/guards.md, "How a command is read"; R254, R255).
# hooks/read.sh runs it for what the guard of the call could not judge alone.
#
# Once for each project other than the hook's that a write lands in (R254): the guard of the
# call had asked, in a request, which projects hold its targets. It gets the project (--arg
# root), the project's record by the guards' own inputs (the hook input on stdin, the record,
# hooks/end.json; --rawfile glance, --arg open as there), and the absolute targets that lie in
# it (--args). Each is judged as the same write is from inside that project, with the same
# refusal text: another session's open run holds it off (foreign_denial); an agent is held to
# the run's files (lease_write_denial, shell_write_denial for shell text).
#
# Once for each script file the call runs by name that is not the project's own committed and
# unchanged one (R255): it gets --arg interp (the interpreter), --arg written (the path as
# the call wrote it), --arg cwd (the folder the call runs in) and the script, --rawfile script
# FILE, or --arg missing 1 when read.sh found no readable file. The script is judged as the
# guard judges the same text written in the call (script_denials), with the same refusals; a
# path it writes outside the project is refused as outside it, as the run's own rule says.
#
# It prints the first refusal as the hook's decision, or nothing. Includes holder, common and
# programs only: a small compile (D564).

include "holder" {search: "../lib"};
include "common" {search: "./"};
include "programs" {search: "./"};

# The absolute path of {path, cwd}, for with_cwd (programs.jq cannot call abs_path).
def resolve: . as $o | $o.path | abs_path($o.cwd);

# Why a script may not write PATH (as written) from folder $k's call: a path outside the
# project is outside, whatever else lies there (the project it lands in is not asked).
def script_target_denial($k):
  . as $o
  | if unresolved_path then shell_write_denial($k)
    elif $o | test("^/dev/(null|stdout|stderr|tty)$|[\t\n]") then empty
    elif ($o | project_path(session_dir($k); $root)) == null then $o | outside_denial($k.lease)
    else shell_write_denial($k) end;

guard_context(true) as $g
| select($g.project)
| if $ARGS.named.interp != null then
    select($g.lease != null)
    | (if $ARGS.named.missing == "1" then script_unreadable($ARGS.named.written; $ARGS.named.interp)
       else first($ARGS.named.script
              | script_denials($ARGS.named.written; $ARGS.named.interp; $ARGS.named.cwd; resolve;
                               . as $w | $w.target | script_target_denial($g | .hook.cwd = $w.cwd)), null) end)
    | select(. != null) | deny
  else
    (if $g.foreign == null then null else holder_name($g.foreign; foreign_stored_name($g.foreign); null) end) as $holder
    | ($g.hook.tool_name == "Bash") as $shell
    | first(
        $ARGS.positional[] as $t
        | ( (select($g.foreign != null) | $t | project_path(session_dir($g); $root) | foreign_denial($g.foreign; $holder)),
            (select($g.lease != null) | $t | if $shell then shell_write_denial($g) else run_write_denial($g) end) )
        | deny)
  end
