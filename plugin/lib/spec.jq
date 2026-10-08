# Parse .vbw/spec.md (docs/proof.md). Input: the file as one string (jq -Rs).
# Output: {requirements: [{id, proof, text}], commands, errors: [..], end: N}
# where end is the line after which a new requirement belongs (null: no
# Requirements section), and commands is {name: argv} from the Commands section
# ("- name: words" or "- name: [\"json\", \"array\"]"), or null without one,
# and results is the Test results section's folders of saved test results
# ("- <folder>/": relative, no "." or "..", outside .vbw/, "/" added when
# missing), or null when the spec names none.

def heading: test("^#{1,2}\\s");
# The argv of one command line: a JSON array of strings, or words split on spaces.
def argv_of: if startswith("[") then (try fromjson catch null)
  | if type == "array" and length > 0 and all(.[]; type == "string" and length > 0) then . else null end
  else [splits("\\s+") | select(length > 0)] end;
# A results folder as given, with its trailing "/", or null when it is unsafe.
def folder_of: (if endswith("/") then . else . + "/" end) as $f
  | ($f | rtrimstr("/") | split("/")) as $s
  | if startswith("/") or any($s[]; . == "" or . == "." or . == "..") or $s[0] == ".vbw" then null else $f end;

split("\n") | map(sub("\r$"; ""))
| reduce to_entries[] as $e (
    {in: false, seen: false, comment: false, reqs: [], errors: [], end: null, cmds: false, commands: null, res: false, results: []};
    ($e.value) as $l | ($e.key + 1) as $n
    | if .comment then .comment = ($l | test("-->") | not)
      elif $l | test("^\\s*<!--") then .comment = ($l | test("-->") | not)
      elif $l | heading then
        .in = ($l | test("^##\\s+Requirements\\s*$"))
        | .cmds = ($l | test("^##\\s+Commands\\s*$"))
        | .res = ($l | test("^##\\s+Test results\\s*$"; "i"))
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
| {requirements: .reqs, commands: .commands, results: (if .results == [] then null else .results end), errors: .errors, end: .end}
