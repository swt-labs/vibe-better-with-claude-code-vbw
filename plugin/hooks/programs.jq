# Reading text the way the shell and the interpreters would run it (docs/guards.md,
# "How a command is read"): the one module of the Bash guard (guard-bash.jq) and of
# its second pass (guard-read.jq) that turns a command, a program or a script into the
# files it writes. It includes no other module: jq 1.8.2 aborts, on its first call, a
# program that reaches a module only through another module (jqlang/jq#3636), so a
# guard includes holder, common and this module itself, and this module takes from
# common.jq only through filter arguments (the denial and the path resolver).
#
# A program is read for the files it names as string literals (R76); a call whose
# target the guard cannot read is its own finding (R219). A script file run by name
# is read like an inline program (R255): script_call finds the file, script_denials
# judges its text.

def basename: split("/") | last // "";   # common.jq has the same: modules cannot share a definition

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
  . as $seg
  | [splits("\\s+") | select(length > 0)
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
  # text: the command as written, quotes kept (a refusal names it).
  | {cmd: (($cw[0] // "") | basename), args: $cw[1:], out, in,
     text: ($seg | gsub("\u0001(?<n>[0-9]+)\u0002"; $q[.n | tonumber]) | sub("^\\s+"; "") | sub("\\s+$"; ""))};

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

def git_words: .args | until(length == 0 or (.[0] | startswith("-") | not);
  if .[0] | test("^(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env)$") then .[2:] else .[1:] end);

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

# --- programs that write files (R76) -----------------------------------------

def interpreter: test("^(python[0-9.]*|pypy[0-9]*|node|nodejs|deno|bun|perl|ruby|php|lua)$");

# The call a write match starts, as written: from its head (the receiver before a
# leading dot included) through the closing parenthesis of its arguments and of a
# method called on its result (Path('a').write_text('b')), the whitespace of a
# line break collapsed; the match itself when no parenthesis closes it.
def call_at($t; $off; $str):
  ( if $str | startswith(".") then ($t[:$off] | [match("[A-Za-z_$][\\w$]*$").string][0] // "") else "" end ) as $pre
  | ( [$t[$off:] | match("(?<i>\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`|\\((?:\\g<i>|,)*\\)|\\[(?:\\g<i>|,)*\\]|\\{(?:\\g<i>|,)*\\}|[^,()\\[\\]{}'\"`]){0}^[\\w$.\\s]*\\((?:\\g<i>|,)*\\)"
        + (if $str | test("^(?:pathlib\\s*\\.\\s*)?Path\\b") then "(?:\\s*\\.\\s*\\w+\\s*\\((?:\\g<i>|,)*\\))?" else "" end)).string][0] // $str ) as $call
  | ($pre + $call) | gsub("\\s*\\n\\s*"; " ") | sub("\\s+$"; "");

# The calls of a program's source text that write a file, each as {call, target}: the
# call as written (call_at) and the path it names as a string literal (a path held in a
# variable cannot be read). One regex, as the guard's cost is mostly compiling it.
def program_writes:
  . as $t
  | [match("(?:\\bopen\\(\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*,\\s*(?:mode\\s*=\\s*)?['\\\"][^'\\\"]*[wax+])|(?:\\bPath\\(\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*\\)\\s*\\.\\s*(?:write_text|write_bytes|unlink|touch|mkdir|rmdir|rename|replace|open\\(\\s*['\\\"][^'\\\"]*[wax+]))|(?:\\bopen\\s*\\(?\\s*\\w+\\s*,\\s*['\\\"]\\s*\\+?>>?\\s*([^'\\\"]+?)\\s*['\\\"])|(?:\\bopen\\s*\\(?\\s*\\w+\\s*,\\s*['\\\"]\\+?>>?['\\\"]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\.(?:writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|unlink|unlinkSync|rmSync|rmdirSync|mkdirSync|makedirs|rmtree|truncate)\\(\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:os|fs|File|FileUtils|shutil|Dir)\\.(?:remove|unlink|rmdir|mkdir|write|binwrite|delete|rm|rm_f|rm_rf|mkdir_p|touch|truncate|chmod)\\(?\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:unlink|mkdir|rmdir|file_put_contents)\\b\\s*\\(?\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:os|fs|File|FileUtils|shutil)\\.(?:rename|renameSync|replace|move|mv)\\(\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\brename\\b\\s*\\(?\\s*['\"`]([^'\"`\\\\]+)['\"`]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])|(?:\\b(?:shutil|FileUtils|fs)\\.(?:copy|copyfile|copy2|copytree|cp|cp_r|copyFile|copyFileSync)\\(\\s*['\"`][^'\"`\\\\]+['\"`]\\s*,\\s*['\"`]([^'\"`\\\\]+)['\"`])"; "g")
   # A backtick template holding ${ is not a literal path: unreadable_calls refuses it (R219).
   | select(.string | test("`[^`]*\\$\\{") | not)
   | call_at($t; .offset; .string) as $call
   | .captures[].string | select(. != null) | {call: $call, target: .}];

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


# The working folder each command runs in (R254): each command of the array gets .cwd, the
# folder in effect when it runs, which a cd moves for the commands after it (a cd to ~, $VAR,
# an expansion or - is not resolved and leaves it, as before). Subshell scope is not read.
# RESOLVE takes {path, cwd} and gives the absolute path (common.jq's abs_path: this module
# cannot call it).
def with_cwd($start; resolve):
  reduce .[] as $c ({cwd: $start, out: []};
    .cwd as $w | .out += [$c + {cwd: $w}]
    | if $c.cmd == "cd" then ([$c.args[] | select(startswith("-") | not)][0]) as $t
        | if $t == null or ($t | test("^~|[$`]")) then . else .cwd = ({path: $t, cwd: $w} | resolve) end
      else . end)
  | .out;

# Every heredoc of a text, as {line, text, quoted, head}: the line that starts it, its body,
# whether its delimiter is quoted (the shell then expands nothing in the body), and the text
# up to the end of that line (the working folder of the line is read from it).
def heredocs:
  . as $t
  | match("(?:^|\\n)([^\\n]*(?<!<)<<-?[ \\t]*(['\\\"]?)(\\w+)\\2[^\\n]*)\\n(.*?)\\n[ \\t]*\\3[ \\t]*(?=\\n|$)"; "gp") as $m
  | {line: $m.captures[0].string, text: $m.captures[3].string, quoted: ($m.captures[1].string != ""),
     head: $t[:$m.offset + 1 + ($m.string[1:] | index("\n"))]};

# Programs read from standard input by a heredoc: the bodies strip_heredocs drops, for the
# commands that run an interpreter.
def heredoc_programs:
  heredocs | select(.line | test("\\b(?:python[0-9.]*|node|perl|ruby|php|deno|bun|lua)\\b"));

# The files a command writes by name, as written: what the run's rules judge (in_run) and
# what a guard asks read.sh about when one lies in another project (R254).
def git_paths:
  select(.cmd == "git") | git_words as $w | ($w[0] // "") as $s | $w[1:] as $a
  | select($s == "checkout" or ($s == "restore" and ((any($a[]; . == "--staged") and (any($a[]; test("^(--worktree|-W)$")) | not)) | not)))
  | (if $s == "checkout" then $a[(($a | index("--")) + 1):] else [$a[] | select(startswith("-") | not)] end)[];
def write_targets:
  shell_writes, git_paths,
  ( select(.cmd | interpreter) | [((.args | join("\n")) | program_writes | map(.target)), inplace_files] | add | .[] );

def program_denial(wd): (.[] | wd);

def unreadable_text:
  "\(.) writes a file the guard cannot name: the program gives its target through a variable, an expression or another call, so the guard cannot read where it writes\nNext: name the file as a literal path in the program, or write it with the Edit tool (Write for a new file)";
def unreadable_denial: (.[] | unreadable_text);

# --- script files run by name (R255) -----------------------------------------

def runner: test("^(sh|bash|zsh)$");

# Whether an option makes the program inline: the interpreter takes its program from the
# command line (-c, -e, -m, -p, -r of php) or the shell its command (-c).
def inline_option($c):
  if $c | runner then test("^-[A-Za-z]*c$")
  elif $c | test("^(python[0-9.]*|pypy[0-9]*)$") then test("^-[A-Za-z]*[cm]$")
  elif $c | test("^(node|nodejs|bun)$") then test("^-[A-Za-z]*[ep]$|^--(eval|print)$")
  elif $c == "perl" then test("^-[A-Za-z]*[eES]$")
  elif $c == "ruby" then test("^-[A-Za-z]*[eS]$")
  elif $c == "php" then . == "-r"
  else . == "-e" end;

# The script file a simple command runs by name, as {interp, file} with the file as
# written: the first argument that is not an option, or a file redirected in with < (an
# option that takes a value is skipped with it; - and the inline options leave the program
# inline; deno and bun run a file after run, and their other subcommands run none). A
# heredoc or here-string redirected in is a program of its own, read by heredoc_programs.
def script_call:
  .cmd as $c
  | select(($c | interpreter) or ($c | runner))
  | (reduce .args[] as $a ({file: null, stop: false, skip: false};
      if .stop or .file != null then .
      elif .skip then .skip = false
      elif $a == "-" then .stop = true
      elif $a | inline_option($c) then .stop = true | .inline = true
      elif $a | test("^(-W|-X|-I|-C|-r|-d|-o|\\+o|--require|--import|--loader|--conditions)$") then .skip = true
      elif $a | startswith("-") then .
      elif $c | test("^(deno|bun)$") and $a == "run" then .
      else .file = $a end)) as $w
  | (if $w.inline then null
     else $w.file // ([.in[] | select(startswith("<") | not)][0]) end) as $f
  | select($f != null and (($c | test("^(deno|bun)$")) | not or ($f | test("[./]"))))
  | {interp: $c, file: $f};

# The text of a script, as what it writes: {call, target, cwd} for a write whose target is
# read, {unreadable: call, cwd} for a call whose target is not (R219). A shell script is
# read as the guard reads a command (the commands of it to the same depth, their redirects,
# shell_writes, git_paths, the programs of its interpreters and of its heredocs); any other
# is the program of its interpreter. A cd inside the text moves the folder of what follows.
def program_findings($cwd):
  (program_writes[] | . + {cwd: $cwd}), (unreadable_calls[] | {unreadable: ., cwd: $cwd});
def script_findings($interp; $start; resolve):
  . as $t
  | if $interp | runner then
      ([$t | commands(3)] | with_cwd($start; resolve)) as $cs
      | ( $cs[] | . as $c
          | ( ($c | shell_writes, git_paths) | {call: $c.text, target: ., cwd: $c.cwd} ),
            ( $c | select(.cmd | interpreter)
              | ((.args | join("\n")) | program_findings($c.cwd)),
                (inplace_files[] | {call: $c.text, target: ., cwd: $c.cwd}) ) ),
        ( $t | select(test("<<")) | heredoc_programs | . as $h
          | ([$h.head | commands(3)] | with_cwd($start; resolve) | last.cwd // $start) as $w
          | $h.text | program_findings($w) )
    else program_findings($start) end;

# The refusals of a script's text (the input): the script file as written, its interpreter,
# the call as written, its target, and WD's text for it: a filter taking {target, cwd}.
def script_denials($file; $interp; $start; resolve; wd):
  "\($file) (run by \($interp)): " as $h
  | script_findings($interp; $start; resolve)
  | if .unreadable != null then $h + (.unreadable | unreadable_text)
    else . as $w | ($w | wd) as $d | "\($h)\($w.call) writes \($w.target): \($d)" end;

# The refusal for a script the guard cannot read: its path holds a shell expansion, or no
# readable file is at it and the command does not write it.
def script_unreadable($file; $interp):
  "\($file) (run by \($interp)): a script the guard cannot read: its path holds a shell expansion, or no readable file is at it and this command does not write it\nNext: write the program with the Edit tool and run it, or give the program inline (-c, or a heredoc on standard input)";
