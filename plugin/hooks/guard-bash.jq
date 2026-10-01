# PreToolUse guard for Bash (docs/guards.md; inputs in common.jq).
#
# Only what the shell would execute is judged. Heredoc bodies and quoted
# strings are data (ledger D281), except where the shell runs them: $(...) and
# `...` inside double quotes, and sh -c / eval strings.

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
def wrapper: basename | test("^(sudo|env|command|builtin|exec|nohup|time|nice|ionice|stdbuf|timeout|xargs|then|do|else|elif|if|while|until|!)$");
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
  [splits("\\s+") | select(length > 0)]
  | reduce .[] as $w ({words: [], out: [], in: [], next: null};
      if .next != null then .[.next] += [$w | restore($q)] | .next = null
      else ([$w | capture("^[0-9]*&?(?<op>>>?|>\\||<)(?<rest>.*)$")] | first) as $r
        | if $r == null then .words += [$w | restore($q)]
          else (if $r.op == "<" then "in" else "out" end) as $k
            | if $r.rest == "" then .next = $k
              elif $r.rest | startswith("&") then .
              else .[$k] += [$r.rest | restore($q)] end
          end
      end)
  | (.words | command_words) as $cw
  | {cmd: (($cw[0] // "") | basename), args: $cw[1:], out, in};

def shell: test("^(sh|bash|zsh|dash|ksh)$");

# Every simple command the shell would run.
def commands($depth):
  strip_heredocs | mask as $m
  | ( [$m.text | splits("\\|\\||&&|;;?|\\||&|\\n|\\(|\\)|\\{|\\}|`") | select(test("\\S"))][]
      | simple($m.q) as $c
      | $c,
        ( select($depth > 0)
          | ( ($c | select(.cmd | shell)
               | [.args | to_entries[] | select(.value | test("^-[A-Za-z]*c[A-Za-z]*$")) | .key][0] as $i
               | select($i != null) | .args[$i + 1] // empty),
              ($c | select(.cmd == "eval") | .args | join(" ")) )
          | commands($depth - 1) ) ),
    ( select($depth > 0) | $m.q[] | select(startswith("\"")) | unquote | select(test("\\$\\(|`")) | commands($depth - 1) );

# --- rules -------------------------------------------------------------------

def git_words: .args | until(length == 0 or (.[0] | startswith("-") | not);
  if .[0] | test("^-[Cc]$") then .[2:] else .[1:] end);

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
def reader: test("^(cat|jq|head|tail|less|more|grep|egrep|rg|wc|git|ls|stat|diff|cmp|shasum|sha256sum|file|test|\\[\\[?)$");
def paths: (.args[] | sub("^--?[A-Za-z0-9-]+="; "")), .out[], .in[];

def approve_call:
  (if .cmd | shell then {cmd: ((.args[0] // "") | basename), args: .args[1:]} else . end)
  | select(.cmd == "vbw" and (.args[0] // "") == "approve");

def everywhere:
  ( approve_call | "only the user approves the contract: ask them to run /vbw:approve (vbw show contract shows what they approve)" ),
  ( select((.out | any(.[]; consent_path)) or ((.cmd | reader) | not) and any(.args[]; consent_path)) | consent_reason );

def in_project:
  destructive,
  ( select(.cmd | test("^(ls|stat|test|\\[\\[?)$") | not) | [paths | select(secret_path)][0] // empty | secret_reason ),
  ( select((.out | any(.[]; record_path)) or ((.cmd | reader) | not) and any(.args[]; record_path)) | record_reason );

# A subagent during a run (docs/workflows.md): commits go through vbw commit,
# and redirects write only the run's files.
def in_run($g):
  ( select(.cmd == "git") | (git_words[0] // "") | select(test("^(commit|push|rebase|merge)$"))
    | "git \(.) by a builder: commits go through vbw commit PLAN \"type(scope): description\"" ),
  ( .out[] | project_path($g.hook.cwd // $root; $root) | lease_write_denial($g.lease; $g.record) );

# Outside a run, every rule needs one of these words in the raw command,
# wherever it appears (strings and heredocs included), so a command without any
# is allowed unread. During a run a subagent's every command is read.
def may_matter: test("rm|git|vbw|consent|record\\.json|\\.env|\\.(pem|key|p12|pfx|kdbx|keystore|jks)|id_(rsa|dsa|ecdsa|ed25519)|netrc|pgpass|npmrc|pypirc|credentials");

guard_context as $g
| ($g.hook.tool_input.command // "") as $c
| select($g.lease != null or ($c | may_matter))
| [$c | commands(3)] as $cmds
| ( [$cmds[] | everywhere][0]
    // (select($g.project)
        | [$cmds[] | in_project][0] // (select($g.lease != null) | [$cmds[] | in_run($g)][0])) )
| select(. != null)
| deny
