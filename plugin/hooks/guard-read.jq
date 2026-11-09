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
# the call wrote it), --arg abs (its absolute path), --arg cwd (the folder the call runs in),
# --arg mode and the script, --rawfile script FILE, or --arg missing 1 when read.sh found no
# readable file. In mode text the command names the path a second time: when it writes the
# file (a heredoc into it or through tee, an echo or printf) the text is taken from the
# command, and nothing is looked up. The text is judged by script_denials: a protected check
# file or a file outside the plan's files is refused by name, a target that cannot be read
# is refused as unreadable, and a path outside the project is refused as outside it.
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

# The files the commands write by name, with the text each gets: from a heredoc (its body,
# literal unless its delimiter is unquoted and the body expands something) or from an echo or
# printf (its words), else text null (a copy, an edit in place, a redirect from another command:
# what the file holds when it runs cannot be read before). A command already counted for a
# heredoc is not counted again for the file it writes.
def command_writers($cmds; $raw; $start):
  [$raw | select(test("<<")) | heredocs($start; resolve) | . as $h
   | $h.cwd as $w
   | ($h.line | commands(3)) as $x
   | $x | shell_writes
   | {file: ., cwd: $w, text: $h.text, literal: ($h.quoted or ($h.text | test("[$`]") | not)), line: $x.text}] as $hw
  | [$cmds[] | select(.cmd | test("^(echo|printf)$")) | . as $k | ($k.args | join("\n")) as $t | $k.out[]
     | {file: ., cwd: $k.cwd, text: $t, literal: ($t | test("[$`]") | not), line: $k.text}] as $lw
  | [$cmds[] | . as $k | select(($hw | map(.line) | index($k.text)) == null) | select(.cmd | test("^(echo|printf)$") | not)
     | shell_writes | {file: ., cwd: $k.cwd, text: null, literal: false}] as $uw
  | $hw + $lw + $uw;

# The text of the script the call runs: {text} from the command that writes it (mode text),
# {text} read from the file, or {unreadable} when neither is known.
def script_source($g):
  $ARGS.named as $a
  | ($g.hook.tool_input.command // "") as $c
  | session_dir($g) as $start
  | def wabs: . as $x | $x.file | abs_path($x.cwd);
    (if $a.mode == "text" then
       ([$c | commands(3)] | with_cwd($start; resolve)) as $cmds
       | [command_writers($cmds; $c; $start)[] | select(.file | (unresolved_path or test("[\t\n]")) | not) | select(wabs == $a.abs)]
     else [] end) as $m
  | if ($m | length) > 0 then
      if $m | any(.literal | not) then {unreadable: true} else {text: ([$m[].text] | join("\n"))} end
    elif $a.missing == "1" then {unreadable: true}
    else {text: $a.script} end;

guard_context(true) as $g
| select($g.project)
| if $ARGS.named.interp != null then
    select($g.lease != null)
    | script_source($g) as $src
    | (if $src.unreadable then script_unreadable($ARGS.named.written; $ARGS.named.interp)
       else first($src.text
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
