# Parse .vbw/spec.md (docs/proof.md). Input: the file as one string (jq -Rs).
# Output: {requirements: [{id, proof, text}], commands, errors: [..], end: N}
# where end is the line after which a new requirement belongs (null: no
# Requirements section), and commands is {name: argv} from the Commands section
# ("- name: words" or "- name: [\"json\", \"array\"]"), or null without one,
# and results is the Test results section's folders of saved test results
# ("- <folder>/": relative, no "." or "..", outside .vbw/, "/" added when
# missing), or null when the spec names none,
# and leave_out is the Clean copy section's [{path, line}] of git-ignored paths
# the proof's clean copy leaves out ("- <path>", kept as written), or null
# without that section,
# and test_files is the Test files section's forms (docs/proof.md): one unnamed
# form of top-level lines ("- run: <argv>" naming {file} exactly once; "- files:
# <git pathspecs>", any number of lines; an optional "- dir: <folder>"), or named
# forms ("- NAME:" with those lines nested under it). One unnamed form without a
# dir is {run, files}, as before forms had names; anything else is an array of
# {name, dir, run, files} (name and dir null when absent). null without the
# section. test_file_lines holds the line each form starts on, in that order.

def heading: test("^#{1,2}\\s");
# The argv of one command line: a JSON array of strings, or words split on spaces.
def argv_of: if startswith("[") then (try fromjson catch null)
  | if type == "array" and length > 0 and all(.[]; type == "string" and length > 0) then . else null end
  else [splits("\\s+") | select(length > 0)] end;
# The number of times "{file}" appears in an argv.
def file_slots: [.[] | [match("\\{file\\}"; "g")] | length] | add;
# A results folder as given, with its trailing "/", or null when it is unsafe.
# True when a clean copy path is unsafe: absolute, an empty, "." or ".." segment, or under .vbw or .git.
def bad_leave_out: (rtrimstr("/") | split("/")) as $s
  | startswith("/") or any($s[]; . == "" or . == "." or . == "..") or ($s[0] == ".vbw" or $s[0] == ".git");
# A test file form: how its messages name it.
def tf_label: if .name == null then "the Test files section" else "form \(.name)" end;
# tf_apply(LINE_NO; KEY; VALUE; LINE): one run, files or dir line applied to a
# form; a refusal goes in .err.
def tf_apply($n; $k; $v; $l):
  if $k == "files" then .files += [$v | splits("\\s+") | select(length > 0) | {p: ., line: $n}]
  elif $k == "run" then ($v | argv_of) as $a
    | if .run != null then .err = "line \($n): \(tf_label) has two run lines"
      elif $a == null or ($a | file_slots) != 1 then
        .err = "line \($n): the Test files run line must name {file} exactly once (words, or a JSON array of strings), got: \($l)"
      else .run = $a end
  else ($v | rtrimstr("/")) as $d
    | if .dir != null then .err = "line \($n): \(tf_label) has two dir lines"
      elif $d == "" or ($v | bad_leave_out) or ($d | test("[*?\\[]")) then
        .err = "line \($n): the dir of \(tf_label) must be a folder relative to the project root, with no '.' or '..' parts and no glob characters (* ? [), outside .vbw/ and .git/, got: \($v)"
      else .dir = $d end
  end;
# tf_line(LINE_NO; FORM_INDEX; KEY; VALUE; LINE): apply the line to form FORM_INDEX, its refusal to .errors.
def tf_line($n; $i; $k; $v; $l):
  (.tforms[$i] | tf_apply($n; $k; $v; $l)) as $f
  | .tforms[$i] = ($f | del(.err)) | .errors += [$f.err // empty];
def folder_of: (if endswith("/") then . else . + "/" end) as $f
  | ($f | rtrimstr("/") | split("/")) as $s
  | if startswith("/") or any($s[]; . == "" or . == "." or . == "..") or $s[0] == ".vbw" then null else $f end;

split("\n") | map(sub("\r$"; ""))
| reduce to_entries[] as $e (
    {in: false, seen: false, comment: false, reqs: [], errors: [], end: null, cmds: false, commands: null, res: false, results: [], tf: false, tfline: null, tforms: [], tmode: null, cc: false, leave_out: null};
    ($e.value) as $l | ($e.key + 1) as $n
    | if .comment then .comment = ($l | test("-->") | not)
      elif $l | test("^\\s*<!--") then .comment = ($l | test("-->") | not)
      elif $l | heading then
        .in = ($l | test("^##\\s+Requirements\\s*$"))
        | .cmds = ($l | test("^##\\s+Commands\\s*$"))
        | .res = ($l | test("^##\\s+Test results\\s*$"; "i"))
        | .tf = ($l | test("^##\\s+Test files\\s*$"; "i"))
        | .cc = ($l | test("^##\\s+Clean copy\\s*$"; "i"))
        | if .cc then .leave_out = (.leave_out // []) else . end
        | if .tf then .tfline = (.tfline // $n) else . end
        | if .cmds and .commands == null then .commands = {} else . end
        | if .in then .seen = true | .end = $n else . end
      elif .cmds and ($l | test("^[-*+]\\s")) then
        ($l | [capture("^- (?<name>[A-Za-z0-9_-]+): +(?<cmd>\\S.*?)\\s*$")] | first) as $m
        | ($m.cmd // "" | argv_of) as $a
        | if $m == null or $a == null then
            .errors += ["line \($n): expected '- name: command' (words, or a JSON array of strings), got: \($l)"]
          elif .commands | has($m.name) then
            .errors += ["line \($n): command \($m.name) is defined twice"]
          else .commands[$m.name] = $a end
      elif .tf and ($l | test("^\\s*[-*+]\\s")) then
        ($l | [capture("^- (?<name>[A-Za-z0-9_-]+):\\s*$")] | first
          | if . != null and (.name == "run" or .name == "files" or .name == "dir") then null else . end) as $f
        | ($l | [capture("^- (?<key>run|files|dir): +(?<val>\\S.*?)\\s*$")] | first) as $t
        | ($l | [capture("^\\s+[-*+] +(?<key>run|files|dir): +(?<val>\\S.*?)\\s*$")] | first) as $s
        | if $f != null then
            if .tmode == "root" then .errors += ["line \($n): the Test files section mixes top-level run, files or dir lines with named forms (- \($f.name):): use one shape"]
            elif any(.tforms[]; .name == $f.name) then .errors += ["line \($n): test file form \($f.name) is named twice"]
            else .tmode = "named" | .tforms += [{name: $f.name, line: $n, dir: null, run: null, files: []}] end
          elif $t != null then
            if .tmode == "named" then .errors += ["line \($n): the Test files section mixes top-level run, files or dir lines with named forms: use one shape"]
            else (if .tmode == null then .tmode = "root" | .tforms = [{name: null, line: .tfline, dir: null, run: null, files: []}] else . end)
              | tf_line($n; 0; $t.key; $t.val; $l) end
          elif $s != null then
            if .tmode != "named" then .errors += ["line \($n): a nested run, files or dir line belongs under a named form (- NAME:), got: \($l)"]
            else tf_line($n; (.tforms | length) - 1; $s.key; $s.val; $l) end
          else
            .errors += ["line \($n): expected '- run: <command with {file}>', '- files: <git pathspecs>', '- dir: <folder>' or a named form '- NAME:' with those lines nested under it, got: \($l)"]
          end
      elif .cc and ($l | test("^[-*+]\\s")) then
        ($l | [capture("^- +(?<p>\\S+)\\s*$")] | first | .p // null) as $p
        | if $p == null or ($p | bad_leave_out) then
            .errors += ["line \($n): expected \"- <path>\" (a git-ignored path relative to the project root, no \".\" or \"..\", outside .vbw/ and .git/), got: \($l)"]
          elif any(.leave_out[]; (.path | rtrimstr("/")) == ($p | rtrimstr("/"))) then
            .errors += ["line \($n): clean copy path \($p) is named twice"]
          else .leave_out += [{path: $p, line: $n}] end
      elif .res and ($l | test("^[-*+]\\s")) then
        ($l | [capture("^- +(?<p>\\S+)\\s*$")] | first | .p // null | if . == null then null else folder_of end) as $f
        | if $f == null then
            .errors += ["line \($n): expected '- <folder>/' (a relative folder, no '.' or '..', outside .vbw/), got: \($l)"]
          elif any(.results[]; . == $f) then
            .errors += ["line \($n): test results folder \($f) is named twice"]
          else .results += [$f] end
      elif (.in | not) then .
      elif $l | test("^[-*+]\\s") then
        ($l | [capture("^- (?<id>R[0-9]+) \\[(?<proof>auto|human)\\] +(?<text>\\S.*?)\\s*$")] | first) as $m
        | if $m == null then
            .errors += ["line \($n): expected '- R<n> [auto|human] statement', got: \($l)"]
          elif any(.reqs[]; .id == $m.id) then
            .errors += ["line \($n): \($m.id) is defined twice"]
          else .reqs += [$m] | .end = $n end
      elif ($l | test("^\\s+\\S")) and .end != null and ($n - 1) == .end then .end = $n
      else . end )
| if .seen then . else .errors += ["no '## Requirements' section"] end
| if .tfline == null or (.errors | length) > 0 then .
  else
    (if .tforms == [] then [{name: null, line: .tfline, dir: null, run: null, files: []}] else .tforms end) as $fs
    | .errors += [$fs[]
        | if .run == null then "line \(.line): \(tf_label) needs a '- run: <command with {file}>' line"
          elif .files == [] then "line \(.line): \(tf_label) needs a '- files: <git pathspecs>' line"
          elif .dir != null then . as $f | (.files[] | select(.p | ltrimstr(":!") | (startswith($f.dir + "/") | not) or any(split("/")[]; . == "." or . == ".."))
            | "line \(.line): the files of \($f | tf_label) must lie under its dir \($f.dir)/ (each pathspec starts with it, with no '.' or '..' parts), got: \(.p)")
          else empty end]
  end
| .tforms as $fs
| {requirements: .reqs, commands: .commands, results: (if .results == [] then null else .results end), leave_out: (if .leave_out == [] then null else .leave_out end),
   test_files: (if .tfline == null then null
     else [$fs[] | {name, dir, run, files: [.files[].p]}]
       | if length == 1 and .[0].name == null and .[0].dir == null then .[0] | {run, files} else . end end),
   test_file_lines: [$fs[].line], errors: .errors, end: .end}
