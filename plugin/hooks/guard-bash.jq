# PreToolUse guard for Bash (docs/guards.md; inputs in common.jq).
#
# Only what the shell would execute is judged. Heredoc bodies and quoted
# strings are data (ledger D281), except where the shell runs them: $(...) and
# `...` inside double quotes, and sh -c / eval strings.
#
# The files a command writes by name are read from its redirects and from the
# shell tools that write (shell_writes: cp, rsync, install, ln, mv, tee, sed -i,
# rm); during a run each is judged like a redirect (#727).
#
# A program an interpreter runs inline (a -c/-e argument, a heredoc) is read for
# the files it writes (R76), and the guard reads a literal path only: a call
# that writes a file whose target is held in a variable, an expression or
# another call is refused under a run, with the fix named (R219). Unlike a
# heredoc fed to cat or tee, whose body is data (D281), an interpreter's is run.

include "holder" {search: "../lib"};
include "common" {search: "./"};
include "programs" {search: "./"};


def destructive:
  ( select(.cmd == "rm" and any(.args[]; test("^-[A-Za-z]*[rR]|^--recursive$")))
    | select(any(.args[]; test("^(/\\*?|~/?\\*?|\\$HOME/?\\*?|\\$\\{HOME\\}/?|\\./?\\*?|\\.\\./?|\\*|(\\./)?\\.(git|vbw)/?)$")))
    | "rm -r of the project, its history, the home directory or the root destroys work" ),
  ( select(.cmd == "git") | git_words as $g | ($g[0] // "") as $s | $g[1:] as $a
    | ( select($s == "push" and any($a[]; test("^(-f|--force|--force-with-lease.*|--mirror|--delete|-d|\\+.+|:.+)$")))
        | "git push that rewrites or deletes remote history" ),
      ( select($s == "reset" and any($a[]; . == "--hard")) | "git reset --hard discards uncommitted work" ),
      ( select($s == "clean" and any($a[]; test("^-[A-Za-z]*f|^--force$"))) | "git clean -f deletes untracked files" ),
      ( select(($s == "checkout" or $s == "restore") and any($a[]; test("^(\\.|\\*|:/)$"))
               and (($s == "restore" and any($a[]; . == "--staged") and (any($a[]; test("^(--worktree|-W)$")) | not)) | not))
        | "git \($s) of the whole tree discards uncommitted work" ),
      ( select($s == "branch" and (any($a[]; . == "-D")
               or (any($a[]; test("^(-d|--delete)$")) and any($a[]; test("^(-f|--force)$")))))
        | "git branch -D deletes unmerged work" ),
      ( select($s == "stash" and (($a[0] // "") | test("^(drop|clear)$"))) | "git stash \($a[0]) deletes stashed work" ),
      ( select(($s | test("^filter-(branch|repo)$")) or ($s == "update-ref" and any($a[]; . == "-d"))
               or ($s == "reflog" and (($a[0] // "") | test("^(expire|delete)$"))))
        | "git \($s) rewrites or deletes history" ) );

# Programs that only read the files they are given.
def reader: test("^(cat|jq|head|tail|less|more|grep|egrep|rg|wc|git|ls|stat|diff|cmp|shasum|sha256sum|file|test|sort|awk|gawk|nawk|cut|nl|column|paste|\\[\\[?)$");
def copier: test("^(cp|rsync|install|ln)$");

# The command writes a file the path rule names (record_path, glance_path): a
# redirect to it, a copier whose destination (last operand) is it, or a program
# that names it and is not known to only read (sort -o and awk -i inplace write
# the file they read).
def written(rule):
  (.out | any(.[]; rule))
  or (any(.args[]; rule) and
      (if .cmd | copier then
         ([.args[] | select(startswith("-") | not)] | (last // "") | rule)
         or any(.args[]; test("^(-t|--target-directory.*|--remove-source-files)$"))
       elif .cmd | reader then
         (.cmd == "sort" and any(.args[]; test("^(-[A-Za-z]*o|--output.*)$")))
         or (.cmd | test("awk$")) and any(.args[]; test("^(inplace|--in-place)$"))
       else true end));
def paths: (.args[] | sub("^--?[A-Za-z0-9-]+="; "")), .out[], .in[];


def approve_call:
  (if .cmd | shell then {cmd: ((.args[0] // "") | basename), args: .args[1:]} else . end)
  | select(.cmd == "vbw" and (.args[0] // "") == "approve");

def apply_call:
  (if .cmd | shell then {cmd: ((.args[0] // "") | basename), args: .args[1:]} else . end)
  | select(.cmd == "vbw" and (.args[0] // "") == "apply");

def loop_call:
  (if .cmd | shell then {cmd: ((.args[0] // "") | basename), args: .args[1:]} else . end)
  | select(.cmd == "vbw" and (.args[0] // "") == "loop")
  # A bare help form (vbw loop --help, vbw loop start -h) is read, not run; --help anywhere else is a value.
  | select((.args[1:] | (. == ["--help"] or . == ["-h"] or (length == 2 and (.[1] | test("^(--help|-h)$"))))) | not)
  | (.args[1] // "");

def everywhere:
  ( approve_call | "only the user approves the contract: ask with the approval menu (AskUserQuestion, the question vbw show contract prints; vbw show contract shows what they approve); /vbw:approve is the user's own command\nNext: ask the user with the approval menu (AskUserQuestion) instead of running vbw approve" ),
  ( loop_call | select(. == "start") | "only the user arms the loop: /vbw:loop ITEM... --ceiling USD is the user's own command, like /vbw:approve\nNext: ask the user to run /vbw:loop with the items and the ceiling they choose; never run vbw loop start yourself" ),
  ( loop_call | select(. == "next" or . == "park") | "vbw loop next and vbw loop park are the kernel's own loop steps: the Stop hook of /vbw:loop runs them, never a tool call\nNext: end your turn; the loop's Stop hook gives the next step" ),
  ( select((.out | any(.[]; consent_path)) or ((.cmd | reader) | not) and any(.args[]; consent_path)) | consent_reason );

# While a loop is on, nothing leaves the project (R180): pushes, releases,
# publishes and deploys wait for the user, for every caller.
def loop_outward:
  (if .cmd | test("^(npx|bunx)$") then (.args | skip_options) as $a | {cmd: ($a[0] // "" | basename), args: $a[1:]} else . end)
  # The subcommand is the first word after the leading options, with the value of an option that takes
  # one skipped (npm --tag next publish, docker --context x push, gh -R a/b release create, cargo
  # +nightly publish); a trigger word later in the line (cargo test publish, npm run publish, gh issue
  # list --label release) is an argument, not the subcommand (F175, F180).
  | def sub($vals): .args | until(length == 0 or ((.[0] | (startswith("-") or startswith("+"))) | not);
        (.[0]) as $o | if ($o | contains("=") | not) and any($vals[]; . == $o) then .[2:] else .[1:] end);
    def first($vals): (sub($vals) | .[0] // "");
    def second($vals): (sub($vals) | .[1] // "");
    ( select(.cmd == "git") | git_words as $g | select(($g[0] // "") == "push") | ["git push", "push"] ),
    ( select(.cmd == "gh") | ["-R", "--repo", "--hostname"] as $v | select(first($v) == "release" and (second($v) | test("^(list|view|download)$") | not)) | ["gh release", "release"] ),
    ( select(.cmd == "gh") | ["-R", "--repo", "--hostname"] as $v | select(first($v) == "pr" and second($v) == "create") | ["gh pr create", "open the pull request"] ),
    ( select(.cmd == "npm" and first(["--tag", "--registry", "--otp", "--access", "--workspace", "-w", "--userconfig", "--prefix", "-C", "--loglevel"]) == "publish") | ["npm publish", "publish"] ),
    ( select(.cmd == "cargo" and first(["--config", "-Z", "--color"]) == "publish") | ["cargo publish", "publish"] ),
    ( select(.cmd == "twine" and first(["--config-file"]) == "upload") | ["twine upload", "upload"] ),
    ( select(.cmd == "gem" and first(["--config-file"]) == "push") | ["gem push", "push"] ),
    ( select(.cmd == "docker" and first(["--context", "-c", "-H", "--host", "--config", "-l", "--log-level", "--tlscacert", "--tlscert", "--tlskey"]) == "push") | ["docker push", "push"] ),
    ( select(.cmd == "vercel" and ((.args[0] // "-") | startswith("-")) and (any(.args[]; test("^(-h|--help|-v|--version)$")) | not)
             or .cmd == "vercel" and first(["--token", "-t", "--scope", "-S", "--cwd", "--global-config", "-Q", "--local-config", "-A"]) == "deploy") | ["vercel deploy", "deploy"] ),
    ( select(.cmd == "netlify" and first(["--filter", "--cwd", "--auth", "--httpProxy"]) == "deploy") | ["netlify deploy", "deploy"] ),
    ( select(.cmd == "fly" and first(["-a", "--app", "-c", "--config", "-t", "--access-token"]) == "deploy") | ["fly deploy", "deploy"] ),
    ( select(.cmd == "flyctl" and first(["-a", "--app", "-c", "--config", "-t", "--access-token"]) == "deploy") | ["flyctl deploy", "deploy"] ),
    ( select(.cmd == "heroku" and first(["-a", "--app", "-r", "--remote"]) == "container:push") | ["heroku container:push", "deploy"] ),
    ( select(.cmd == "heroku" and first(["-a", "--app", "-r", "--remote"]) == "container:release") | ["heroku container:release", "deploy"] ),
    ( select(.cmd == "heroku" and first(["-a", "--app", "-r", "--remote"]) == "pipelines:promote") | ["heroku pipelines:promote", "deploy"] ),
    ( select(.cmd == "wrangler" and first(["--env", "-e", "--config", "-c"]) == "deploy") | ["wrangler deploy", "deploy"] ),
    ( select(.cmd == "wrangler" and first(["--env", "-e", "--config", "-c"]) == "publish") | ["wrangler publish", "deploy"] )
  | "the loop never leaves the project: \(.[0]) is not run while a loop is on\nNext: wait for the loop to end, or stop it with /vbw:loop stop, then \(.[1]) yourself";

def in_project($g):
  ( select($g.loop_on) | loop_outward ),
  destructive,
  ( select(.cmd | test("^(ls|stat|test|\\[\\[?)$") | not) | [paths | select(secret_path)][0] // empty | secret_reason ),
  ( select(written(record_path)) | record_reason );

# The guard of a command as it runs: the same, with the working folder the command has.
# The absolute path of {path, cwd}, for with_cwd (programs.jq cannot call abs_path).
def resolve: . as $o | $o.path | abs_path($o.cwd);

def here($g): . as $k | $g | .hook.cwd = $k.cwd;


# VBW's own chat (no agent_type) while its autonomous run is armed or a loop runs
# (R239): plan work is committed by vbw commit, never by hand. The user's own
# commands are never checked.
def chat_drives($g):
  select($g.lease == null and ($g.hook.agent_type // "") == "" and ($g.armed or $g.loop_on))
  | select(.cmd == "git") | git_words as $w | ($w[0] // "") as $s
  | select($s | test("^(commit|commit-tree|push|rebase|merge|pull|cherry-pick|revert|am)$"))
  | "git \($s) by VBW's chat while \(if $g.armed then "an autonomous run is armed" else "a loop runs" end): plan work is committed by vbw commit PLAN \"type(scope): description\" inside the run, never by hand\nNext: follow the proof's Next line, or run vbw commit PLAN \"type(scope): description\"; the user commits by hand from their own terminal";

# A subagent during a run (docs/workflows.md): commits go through vbw commit;
# builders share one working tree, so nothing may move HEAD or other builders'
# changes; files are restored and written by the shell (shell_writes) only
# within the run's files.
def in_run($g):
  # The Lead's job under a plan run is vbw apply (plain, --patch, --add); --amend stays the main session's (R250).
  ( apply_call
    | select((($g.hook.agent_type // "") == "vbw:lead" and ($g.lease.kind // "") == "plan" and (.args | any(.[]; . == "--amend") | not)) | not)
    | "vbw apply changes the plan of record: only the main session runs it, in every mode (--amend, --patch, --add included)\nNext: report it so the main session amends or patches the plan" ),
  ( select(written(glance_path)) | glance_reason ),
  ( select(.cmd == "git") | git_words as $w | ($w[0] // "") as $s | $w[1:] as $a
    | ( select($s | test("^(commit|commit-tree|push|rebase|merge|pull|cherry-pick|revert|am)$"))
        | "git \($s) by a builder: commits go through vbw commit PLAN \"type(scope): description\"\nNext: run vbw commit PLAN \"type(scope): description\" with the files you changed" ),
      ( select(($s == "stash" and (($a[0] // "") | test("^(list|show)$") | not)) or ($s | test("^(switch|reset)$"))
               or ($s == "checkout" and (any($a[]; . == "--") | not)))
        | "git \($s) by a builder changes the working tree other builders share: undo your own change by editing your files" ) ),
  ( git_paths | shell_write_denial($g) ),
  ( shell_writes | shell_write_denial($g) ),
  ( select(.cmd | interpreter) | [((.args | join("\n")) | program_writes | map(.target)), inplace_files] | add | program_denial(shell_write_denial($g)) ),
  ( select(.cmd | interpreter) | (.args | join("\n")) | unreadable_calls | unreadable_denial );

# Another session's open run (D11): shell writes of the files it writes.
def foreign_run($g):
  holder_name($g.foreign; foreign_stored_name($g.foreign); null) as $holder
  | shell_writes | project_path(session_dir($g); $root) | foreign_denial($g.foreign; $holder);

# Outside a run, every rule needs one of these words in the raw command,
# wherever it appears (strings and heredocs included), so a command without any
# is allowed unread. During a run a subagent's every command is read.
def may_matter: test("rm|git|vbw|gh|npm|cargo|twine|gem|docker|vercel|netlify|fly|heroku|wrangler|publish|push|deploy|consent|record\\.json|\\.env|\\.(pem|key|p12|pfx|kdbx|keystore|jks)|id_(rsa|dsa|ecdsa|ed25519)|netrc|pgpass|npmrc|pypirc|credentials");

# A write can land in another project (R254): an agent's call, and a command that names an
# absolute path, a .. segment or cd, are read whatever the words.
def reaches: test("(^|[^\\w.])/\\w|(^|[\\s/\"'=])\\.\\.($|[\\s/\"';&|)])|(^|[^\\w.-])cd($|[^\\w.-])");

# --- script files run by name (R255) ----------------------------------------
#
# Under a run lease, an interpreter or a shell that runs a file by name (python FILE,
# python < FILE, bash FILE) runs a program the agent may have written, so the file is read
# like an inline program. That reading is the second pass's (guard-read.jq, run by read.sh),
# because it needs a git lookup and the disk, which the first pass never touches: this
# pass finds the script calls and asks, with one request line each:
#   script<TAB>start commit or -<TAB>interpreter<TAB>path as written<TAB>absolute path<TAB>
#   working folder<TAB>mode
# mode is text when the command names the path a second time (it may write the file: the second
# pass takes the text from the command and looks nothing up) and file otherwise (read.sh looks the
# file up in git and reads it unless it is committed and unchanged since the start commit). A
# path holding ~ or a shell expansion cannot be obtained at all and is refused here as unreadable.
def script_requests($g; $cmds; $raw):
  $cmds[] | . as $k | script_call | . + {cwd: $k.cwd} | . as $s
  | if ($s.file | unresolved_path or test("[\t\n]")) then {deny: script_unreadable($s.file; $s.interp)}
    else {request: [($g.holder.head // "-"), $s.interp, $s.file, ($s.file | abs_path($s.cwd)), $s.cwd,
                    (if ($raw | split($s.file) | length) > 2 then "text" else "file" end)]} end;

# The request a guard prints for read.sh: request (common.jq) with the script lines; a script
# line needs the command, so the hook line then carries it.
def request_all($g; $targets; $scripts):
  select(($targets | length) + ($scripts | length) > 0)
  | "vbw-read",
    ($g.hook | {session_id, agent_type, tool_name, cwd} + (if ($scripts | length) > 0 then {tool_input: {command: $g.hook.tool_input.command}} else {} end) | tojson),
    ($targets | unique[] | "target\t\(.[0])\t\(.[1])"),
    ($scripts | unique[] | "script\t" + join("\t"));

def run:
  guard_context(true) as $g
  | ($g.hook.tool_input.command // "") as $c
  | select($g.lease != null or $g.foreign != null or ($g.hook.agent_type // "") != "" or ($c | may_matter or reaches))
  | session_dir($g) as $start
  | ([$c | commands(3)] | with_cwd($start; resolve)) as $cmds
  | [$c | select(test("<<")) | heredoc_programs
       | . + {cwd: ([.head | commands(3)] | with_cwd($start; resolve) | last.cwd // $start)}] as $hds
  | (if $g.lease != null then [script_requests($g; $cmds; $c)] else [] end) as $sr
  | ( [$cmds[] | everywhere][0]
      // (select($g.project and $g.foreign != null) | [$cmds[] | here($g) as $k | foreign_run($k)][0])
      // (select($g.project)
          | [$cmds[] | in_project($g)][0]
            // [$cmds[] | chat_drives($g)][0]
            // (select($g.lease != null)
                | [$cmds[] | here($g) as $k | in_run($k)][0]
                  // ([$hds[] | . as $h | ($g | .hook.cwd = $h.cwd) as $k | $h.text | program_writes | map(.target) | program_denial(shell_write_denial($k))][0])
                  // ([$hds[] | .text | unreadable_calls | unreadable_denial][0])
                  // ([$sr[] | .deny | select(. != null)][0]))) // null) as $deny
  | if $deny != null then $deny | deny
    elif $g.project then
      request_all($g; [($cmds[] | here($g) as $k | write_targets | request_target($k; true)),
                         ($hds[] | . as $h | ($g | .hook.cwd = $h.cwd) as $k | .text | program_writes[].target | request_target($k; true))];
                  [$sr[] | .request | select(. != null)])
    else empty end;

run, "vbw-guard-done"
