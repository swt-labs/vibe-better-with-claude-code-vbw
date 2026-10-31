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

# --- reading a shell command -------------------------------------------------

def strip_heredocs:
  split("\n") | reduce .[] as $l ({out: [], end: null, tabs: false};
    if .end != null then
      (if (if .tabs then ($l | sub("^\t+"; "")) else $l end) == .end then .end = null else . end)
    else
      ([$l | match("(?<!<)<<(-?)\\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\\2")] | first) as $m
      | .out += [$l]
      | if $m == null then . else .end = $m.captures[2].string | .tabs = ($m.captures[0].string == "-") end
    end)
  | .out | join("\n");

# Quoted strings become \u0001<n>\u0002; .q keeps their raw text.
def mask:
  . as $s | [match("'[^']*'|\"(?:\\\\.|[^\"\\\\])*\""; "g")] as $ms
  | reduce range($ms | length) as $i ({text: "", pos: 0, q: []};
      $ms[$i] as $m | .text += $s[.pos:$m.offset] + "\u0001\($i)\u0002"
      | .q += [$m.string] | .pos = $m.offset + $m.length)
  | .text += $s[.pos:] | {text, q};

def unquote: if startswith("'") then .[1:-1] else .[1:-1] | gsub("\\\\(?<c>.)"; .c) end;
def restore($q): gsub("\u0001(?<n>[0-9]+)\u0002"; $q[.n | tonumber] | unquote);

def assignment: test("^[A-Za-z_][A-Za-z0-9_]*=");
def wrapper: basename | test("^(sudo|env|command|builtin|exec|nohup|time|nice|ionice|stdbuf|timeout|xargs|rtk|then|do|else|elif|if|while|until|!)$");
def skip_options: until(length == 0 or (.[0] | startswith("-") | not);
  if .[0] | test("^-[ugCDnIPLsEdko]$") then .[2:] else .[1:] end);

# Words from the command position on: assignments and wrappers dropped.
def command_words:
  until(length == 0 or ((.[0] | assignment) or (.[0] | wrapper) | not);
    if .[0] | assignment then .[1:]
    else (.[0] | basename) as $w | .[1:] | skip_options
      | if $w == "timeout" then .[1:] elif $w == "env" then until(length == 0 or (.[0] | assignment | not); .[1:]) else . end
    end);

# One simple command: {cmd, args, out, in} (out/in: redirect targets).
def simple($q):
  [splits("\\s+") | select(length > 0)
   # A redirect glued to the word before it (push>out.log, push&>log) is a word of its own, as the shell
   # reads it; a word that is only a descriptor number (2>&1) stays whole (F206).
   | (capture("^(?<pre>[^<>]*?)(?<red>&?[<>].*)$") // null) as $m
   | if $m != null and ($m.pre | test("^[0-9]*$") | not) then $m.pre, $m.red else . end]
  | reduce .[] as $w ({words: [], out: [], in: [], next: null};
      if .next != null then .[.next] += [$w | restore($q)] | .next = null
      else ([$w | capture("^[0-9]*&?(?<op>>\\||>>?|<)(?<rest>.*)$")] | first) as $r
        | if $r == null then .words += [$w | restore($q)]
          else (if $r.op == "<" then "in" else "out" end) as $k
            | if $r.rest == "" or $r.rest == "&" then .next = $k
              # >&1, 2>&1, <&0, >&-: a descriptor, not a file; >&FILE writes FILE (D304).
              elif $r.rest | test("^&([0-9]+|-)$") then .
              elif $r.rest | startswith("&") then .[$k] += [$r.rest[1:] | restore($q)]
              else .[$k] += [$r.rest | restore($q)] end
          end
      end)
  # A redirect whose target the splitter cut off (a backtick substitution starts
  # it) has an unresolved target: refused under a run like any expansion (D304).
  | if .next != null then .[.next] += ["`...`"] else . end
  # A target cut at the ( of an unquoted $(...) is named as $(...), the same way.
  | .out |= map(if endswith("$") then . + "(...)" else . end)
  | .in |= map(if endswith("$") then . + "(...)" else . end)
  | (.words | command_words) as $cw
  | {cmd: (($cw[0] // "") | basename), args: $cw[1:], out, in};

def shell: test("^(sh|bash|zsh|dash|ksh)$");

# The bodies of the $(...) and `...` the shell runs inside a double-quoted
# string; an escaped \$ or \` is text, so naming a command there runs nothing.
def substitutions:
  .[1:-1] | match("\\\\.|\\$(?<p>\\((?:[^()\\\\]|\\\\.|\\g<p>)*\\))|`(?<b>(?:[^`\\\\]|\\\\.)*)`"; "g")
  | .captures[] | select(.string != null) | .string | (if startswith("(") then .[1:-1] else . end)
  | gsub("\\\\(?<c>[\"\\\\$`])"; .c);

# Every simple command the shell would run.
def commands($depth):
  strip_heredocs | mask as $m
  | ( [$m.text | splits("\\|\\||&&|;;?|(?<!>)\\||(?<![<>])&(?!>)|\\n|\\(|\\)|\\{|\\}|`") | select(test("\\S"))][]
      | simple($m.q) as $c
      | $c,
        ( select($depth > 0)
          | ( ($c | select(.cmd | shell)
               | [.args | to_entries[] | select(.value | test("^-[A-Za-z]*c[A-Za-z]*$")) | .key][0] as $i
               | select($i != null) | .args[$i + 1] // empty),
              ($c | select(.cmd == "eval") | .args | join(" ")) )
          | commands($depth - 1) ) ),
    ( select($depth > 0) | $m.q[] | select(startswith("\"")) | substitutions | commands($depth - 1) );

# --- rules -------------------------------------------------------------------

def git_words: .args | until(length == 0 or (.[0] | startswith("-") | not);
  if .[0] | test("^(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env)$") then .[2:] else .[1:] end);

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

# The files a simple command writes by name, as written (#727): its redirect
# targets; the destination of a copier (the last operand, or -t DIR) and of mv,
# whose sources go too, as do rsync --remove-source-files'; tee's and rm's
# operands; the files sed -i edits, not its script. A destination ending in /
# (or -t's) is a folder, written at each source's name; ln with one operand
# links at its name here. Flags are never targets. A folder named without a
# trailing / is judged as itself: the guard reads text and cannot tell it from
# a file, so a write there is refused unless the folder is the run's to write
# and holds no protected check file (lease_write_denial).
# The words are read by one pattern per tool over the words joined by NUL (the
# guard's cost is mostly compiling it, and a pattern is one constant): o, an
# operand; t, GNU's target folder of cp, mv, install or ln (-t DIR, -rtDIR,
# --target-directory[=]DIR and its abbreviations; rsync's -t is --times); s, a
# sed script given by -e/-f (else the first operand is the script); m, a dot
# word after sed's bare -i (BSD's suffix .bak or GNU's file, so it is judged as
# a file too; BSD's '' suffix is skipped). A valued flag's value is skipped:
# those of install, rsync and cp/mv/ln's --suffix; any other valued flag only
# makes the guard judge one path too many.
def shell_writes:
  .out[],
  ( .cmd as $cmd
    | select(($cmd | test("^(cp|mv|rsync|install|ln|tee|rm)$")) or $cmd == "sed" and any(.args[]; test("^-[A-Za-z]*i|^--in-place")))
    # Each pattern: the tool's valued flags with their value, its target-folder forms (--ta[-a-z]* is
    # --target-directory and its abbreviations: no other long flag of these tools starts so), any
    # other flag, else an operand.
    | ({sed: "\u0000(?:(?<s>-[A-Za-z]*[ef]\u0000|--(?:expression|file)\u0000|-[A-Za-z]*[ef][^\u0000]|--(?:expression|file)=)[^\u0000]*|-[A-Za-z]*i\u0000(?<m>\\.[^/\u0000]*)?(?=\u0000)|-[^\u0000]*|(?<o>[^\u0000]*))(?=\u0000)",
        install: "\u0000(?:(?:--ta[-a-z]*=|-[A-Za-z]*?t(?=[^\u0000])|(?:--ta[-a-z]*|-[A-Za-z]*?t)\u0000)(?<t>[^\u0000]*)|(?:-[A-Za-z]*[mogS]|--(?:mode|owner|group|suffix))\u0000[^\u0000]*|-[^\u0000]*|(?<o>[^\u0000]*))(?=\u0000)",
        rsync: "\u0000(?:(?:-[A-Za-z]*[ef]|--(?:exclude|include|filter|rsh|exclude-from|include-from|files-from))\u0000[^\u0000]*|-[^\u0000]*|(?<o>[^\u0000]*))(?=\u0000)",
        tee: "\u0000(?:-[^\u0000]*|(?<o>[^\u0000]*))(?=\u0000)",
        rm: "\u0000(?:-[^\u0000]*|(?<o>[^\u0000]*))(?=\u0000)"}[$cmd]
       // "\u0000(?:(?:-S|--suffix)\u0000[^\u0000]*|(?:--ta[-a-z]*=|-[A-Za-z]*?t(?=[^\u0000])|(?:--ta[-a-z]*|-[A-Za-z]*?t)\u0000)(?<t>[^\u0000]*)|-[^\u0000]*|(?<o>[^\u0000]*))(?=\u0000)") as $re
    | (reduce (((.args | map("\u0000" + .) | add // "") + "\u0000") | match($re; "g").captures[] | select(.string != null)) as $x
        ({o: []}; .[$x.name] += [$x.string])) as $r
    | $r.o as $o
    | if $cmd == "sed" then (if $r.s then $o else $o[1:] end)[], ($r.m // [])[]
      elif $cmd == "tee" or $cmd == "rm" then $o[]
      else
        ( if $r.t then {srcs: $o, dir: $r.t[0]}
          elif ($o | length) == 1 and $cmd == "ln" then {srcs: $o, dir: "."}
          elif ($o | length) < 2 then {srcs: []}
          elif $o[-1] | endswith("/") or . == "." or . == ".." then {srcs: $o[:-1], dir: $o[-1]}
          else {srcs: $o[:-1], file: $o[-1]} end ) as $w
        | (if $w.dir then $w.srcs[] | ($w.dir | rtrimstr("/")) + "/" + basename else $w.file // empty end),
          (select($cmd == "mv" or any(.args[]; . == "--remove-source-files")) | $w.srcs[])
      end );

def approve_call:
  (if .cmd | shell then {cmd: ((.args[0] // "") | basename), args: .args[1:]} else . end)
  | select(.cmd == "vbw" and (.args[0] // "") == "approve");

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

# --- programs that write files (R76) -----------------------------------------

def interpreter: test("^(python[0-9.]*|pypy[0-9]*|node|nodejs|deno|bun|perl|ruby|php|lua)$");

# The paths a program's source text writes, read from the calls that name them
# as string literals (a path held in a variable cannot be read). One regex, as
# the guard's cost is mostly compiling it.
def program_writes:
  [match("(?:\\bopen\\(\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*,\\s*(?:mode\\s*=\\s*)?['\\\"][^'\\\"]*[wax+])|(?:\\bPath\\(\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*\\)\\s*\\.\\s*(?:write_text|write_bytes|unlink|touch|mkdir|rmdir|rename|replace|open\\(\\s*['\\\"][^'\\\"]*[wax+]))|(?:\\bopen\\s*\\(?\\s*\\w+\\s*,\\s*['\\\"]\\s*\\+?>>?\\s*([^'\\\"]+?)\\s*['\\\"])|(?:\\bopen\\s*\\(?\\s*\\w+\\s*,\\s*['\\\"]\\+?>>?['\\\"]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\.(?:writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|unlink|unlinkSync|rmSync|rmdirSync|mkdirSync|makedirs|rmtree|truncate)\\(\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:os|fs|File|FileUtils|shutil|Dir)\\.(?:remove|unlink|rmdir|mkdir|write|binwrite|delete|rm|rm_f|rm_rf|mkdir_p|touch|truncate|chmod)\\(?\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:unlink|mkdir|rmdir|file_put_contents)\\b\\s*\\(?\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:os|fs|File|FileUtils|shutil)\\.(?:rename|renameSync|replace|move|mv)\\(\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\brename\\b\\s*\\(?\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:shutil|FileUtils|fs)\\.(?:copy|copyfile|copy2|copytree|cp|cp_r|copyFile|copyFileSync)\\(\\s*['\"`][^'\"`\\\\]+['\"`]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])"; "g")
   # A backtick template holding ${ is not a literal path: unreadable_calls refuses it (R219).
   | select(.string | test("`[^`]*\\$\\{") | not) | .captures[].string | select(. != null)];

# The calls of a program text that write a file whose target the guard cannot
# read (R219): a call head program_writes reads as a write whose target
# argument is not a string literal (it starts with a name, a $, a parenthesis,
# an f-string prefix, a backtick template holding ${, a dot or any token but a
# plain quote), and an open whose mode is not a literal. Each is the call as
# written, from its head through the closing parenthesis of its arguments. One
# match pass over the text; the arguments of a call found are read only then.
def unreadable_calls:
  ("(?<i>\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`|\\((?:\\g<i>|,)*\\)|\\[(?:\\g<i>|,)*\\]|\\{(?:\\g<i>|,)*\\}|[^,()\\[\\]{}'\"`]){0}"
   + "(?<![.\\w])(?<n1>open|unlink|mkdir|rmdir|rename|file_put_contents)\\s*\\((?<a1>(?:\\g<i>|,)*)\\)"
   + "|\\b(?<p2>os|fs|File|FileUtils|shutil|Dir)(?:\\s*\\.\\s*promises)?\\s*\\.\\s*(?<m2>remove|unlink|unlinkSync|rmdir|rmdirSync|mkdir|mkdirSync|makedirs|write|writeFile|writeFileSync|binwrite|appendFile|appendFileSync|createWriteStream|delete|rm|rmSync|rm_f|rm_rf|rmtree|mkdir_p|touch|truncate|chmod|rename|renameSync|replace|move|mv|copy|copyfile|copy2|copytree|cp|cp_r|copyFile|copyFileSync)\\s*\\((?<a2>(?:\\g<i>|,)*)\\)"
   + "|(?:(?<![.\\w])|(?<=\\bpathlib\\.))Path\\s*\\((?<a3>(?:\\g<i>|,)*)\\)\\s*\\.\\s*(?<m3>write_text|write_bytes|unlink|touch|mkdir|rmdir|rename|replace|open)\\s*\\((?<b3>(?:\\g<i>|,)*)\\)"
   + "|(?<![\\w.)\\]])(?<r4>\\((?:\\g<i>|,)*\\))\\s*\\.\\s*(?:write_text|write_bytes)\\s*\\((?:\\g<i>|,)*\\)"
   + "|\\.\\s*(?<m6>writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|rmSync|rmdirSync|mkdirSync|unlinkSync|makedirs|rmtree)\\s*\\((?<a6>(?:\\g<i>|,)*)\\)"
   + "|(?<![.\\w])(?<m9>writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|rmSync|rmdirSync|mkdirSync|unlinkSync)\\s*\\((?<a9>(?:\\g<i>|,)*)\\)"
   + "|\\b(?<p7>os|fs|File|FileUtils|shutil|Dir)\\s*\\.\\s*(?<m7>remove|unlink|rmdir|mkdir|write|binwrite|delete|rm|rm_f|rm_rf|mkdir_p|touch|truncate|chmod|rename|replace|move|mv|copy|cp|cp_r)[ \\t]+(?<a7>[^(\\s;\\n][^;\\n]*)"
   + "|(?<![.\\w])(?<n8>open)[ \\t]+(?<a8>[^(\\s;\\n][^;\\n]*)"
   + "|(?<![.\\w])(?<n5>unlink|mkdir|rmdir|rename)[ \\t]+(?<a5>\\$[^;\\n]*)") as $re
  | def args: [match("(?<j>\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`|\\((?:\\g<j>|,)*\\)|\\[(?:\\g<j>|,)*\\]|\\{(?:\\g<j>|,)*\\}|[^,()\\[\\]{}'\"`]){0}\\s*((?:\\g<j>)*)(?:,|$)"; "g").captures[] | select(.name == null) | .string | sub("\\s+$"; "") | sub("^\\s+"; "")] | map(select(length > 0));
    def literal: test("^['\"]") or (test("^`") and (contains("${") | not));
    # The mode of an open: the second argument or mode=...; null when none is given.
    def mode_arg: ((.[1:] | map(select(test("^mode\\s*=[^=]"))) | .[0]) | select(. != null) | sub("^mode\\s*=\\s*"; ""))
      // (.[1] // null | select(. != null and (test("^[A-Za-z_]\\w*\\s*=[^=]") | not)))
      // null;
    # Perl opens take ">", ">>", "+<" and a path; Python modes hold w, a, x or +.
    def open_unreadable:
      . as $a | ($a | mode_arg) as $m
      | if $m == null then false
        elif ($m | literal | not) then true
        else ($m[1:-1]) as $s
          | if $s | test("^\\s*\\+?[<>]") then
              ($s | test(">|^\\s*\\+<")) and (if $s | test("^\\s*\\+?>>?\\s*\\S") then $s | test("\\$") else ($a[2] // "'") | literal | not end)
            else ($s | test("[wax+]")) and (($a[0] // "'") | literal | not) end
        end;
    def rename_unreadable: any(.[0:2][]; literal | not);
  [match($re; "g")
   | (.captures | map(select(.name != null and .string != null) | {(.name): .string}) | add // {}) as $c
   | select(
       if $c.n1 != null then
         ($c.a1 | args) as $a
         | if $c.n1 == "open" then $a | open_unreadable
           elif $c.n1 == "rename" then $a | rename_unreadable
           else ($a[0] // "'") | literal | not end
       elif $c.m6 != null or $c.m9 != null then
         (($c.a6 // $c.a9) | args) as $a | ($a[0] // "'") | literal | not
       elif $c.n8 != null then
         ($c.a8 | args) | open_unreadable
       elif $c.p2 != null or $c.p7 != null then
         (($c.a2 // $c.a7) | args) as $a | ($c.m2 // $c.m7) as $m
         | if $m | test("^(rename|renameSync|replace|move|mv)$") then $a | rename_unreadable
           elif $m | test("^(copy|copyfile|copy2|copytree|cp|cp_r|copyFile|copyFileSync)$") then ($a[1] // "'") | literal | not
           else ($a[0] // "'") | literal | not end
       elif $c.m3 != null then
         ($c.a3 | args) as $p | ($c.b3 | args) as $b
         | if $c.m3 == "open" then
             ($b | length > 0) and ([($p | map(select(literal | not)) | .[0]) // "'"] + $b | open_unreadable)
           else $p | any(literal | not) end
       elif $c.n5 != null then
         ($c.a5 | args) as $a | if $c.n5 == "rename" then $a | rename_unreadable else true end
       else $c.r4 != null end)
   | .string | gsub("\\s*\\n\\s*"; " ") | sub("\\s+$"; "")];

# perl -i and ruby -i edit the files they are given in place.
def inplace_files:
  select(.cmd | test("^(perl|ruby)$")) | select(any(.args[]; test("^-[A-Za-z]*i")))
  | [.args | reduce .[] as $a ({skip: false, files: []};
      if .skip then .skip = false
      elif $a | test("^-[A-Za-z]*[eE]$") then .skip = true
      elif $a | startswith("-") then .
      else .files += [$a] end) | .files[]];

# Programs read from standard input by a heredoc: the bodies strip_heredocs
# drops, for the commands that run an interpreter.
def heredoc_programs:
  match("(?:^|\\n)[^\\n]*(?:\\b(?:python[0-9.]*|node|perl|ruby|php|deno|bun|lua)\\b[^\\n]*<<|<<[^\\n]*\\b(?:python[0-9.]*|node|perl|ruby|php|deno|bun|lua)\\b)-?[ \\t]*(['\\\"]?)(\\w+)\\1[^\\n]*\\n(.*?)\\n[ \\t]*\\2[ \\t]*(?:\\n|$)"; "gp") | .captures[2].string;

def program_denial($g):
  (.[] | shell_write_denial($g));

def unreadable_denial:
  (.[] | "\(.) writes a file the guard cannot name: the program gives its target through a variable, an expression or another call, so the guard cannot read where it writes\nNext: name the file as a literal path in the program, or write it with the Edit tool (Write for a new file)");

# A subagent during a run (docs/workflows.md): commits go through vbw commit;
# builders share one working tree, so nothing may move HEAD or other builders'
# changes; files are restored and written by the shell (shell_writes) only
# within the run's files.
def in_run($g):
  ( select(written(glance_path)) | glance_reason ),
  ( select(.cmd == "git") | git_words as $w | ($w[0] // "") as $s | $w[1:] as $a
    | ( select($s | test("^(commit|push|rebase|merge|pull|cherry-pick|revert|am)$"))
        | "git \($s) by a builder: commits go through vbw commit PLAN \"type(scope): description\"" ),
      ( select(($s == "stash" and (($a[0] // "") | test("^(list|show)$") | not)) or ($s | test("^(switch|reset)$"))
               or ($s == "checkout" and (any($a[]; . == "--") | not)))
        | "git \($s) by a builder changes the working tree other builders share: undo your own change by editing your files" ),
      ( select($s == "checkout" or ($s == "restore" and ((any($a[]; . == "--staged") and (any($a[]; test("^(--worktree|-W)$")) | not)) | not)))
        | (if $s == "checkout" then $a[(($a | index("--")) + 1):] else [$a[] | select(startswith("-") | not)] end)[]
        | shell_write_denial($g) ) ),
  ( shell_writes | shell_write_denial($g) ),
  ( select(.cmd | interpreter) | [((.args | join("\n")) | program_writes), inplace_files] | add | program_denial($g) ),
  ( select(.cmd | interpreter) | (.args | join("\n")) | unreadable_calls | unreadable_denial );

# Another session's open run (D11): shell writes of the files it writes.
def foreign_run($g):
  holder_name($g.foreign; foreign_stored_name($g.foreign); null) as $holder
  | shell_writes | project_path(session_dir($g); $root) | foreign_denial($g.foreign; $holder);

# Outside a run, every rule needs one of these words in the raw command,
# wherever it appears (strings and heredocs included), so a command without any
# is allowed unread. During a run a subagent's every command is read.
def may_matter: test("rm|git|vbw|gh|npm|cargo|twine|gem|docker|vercel|netlify|fly|heroku|wrangler|publish|push|deploy|consent|record\\.json|\\.env|\\.(pem|key|p12|pfx|kdbx|keystore|jks)|id_(rsa|dsa|ecdsa|ed25519)|netrc|pgpass|npmrc|pypirc|credentials");

guard_context(true) as $g
| ($g.hook.tool_input.command // "") as $c
| select($g.lease != null or $g.foreign != null or ($c | may_matter))
| [$c | commands(3)] as $cmds
| ( [$cmds[] | everywhere][0]
    // (select($g.project and $g.foreign != null) | [$cmds[] | foreign_run($g)][0])
    // (select($g.project)
        | [$cmds[] | in_project($g)][0]
          // (select($g.lease != null)
              | [$cmds[] | in_run($g)][0]
                // (select($c | test("<<")) | ([$c | heredoc_programs | program_writes | program_denial($g)][0])
                    // ([$c | heredoc_programs | unreadable_calls | unreadable_denial][0])))) )
| select(. != null)
| deny
