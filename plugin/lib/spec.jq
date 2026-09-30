# Parse .vbw/spec.md (docs/proof.md). Input: the file as one string (jq -Rs).
# Output: {requirements: [{id, proof, text}], errors: [..], end: N} where end is
# the line after which a new requirement belongs (null: no Requirements section).

def heading: test("^#{1,2}\\s");

split("\n") | map(sub("\r$"; ""))
| reduce to_entries[] as $e (
    {in: false, seen: false, comment: false, reqs: [], errors: [], end: null};
    ($e.value) as $l | ($e.key + 1) as $n
    | if .comment then .comment = ($l | test("-->") | not)
      elif $l | test("^\\s*<!--") then .comment = ($l | test("-->") | not)
      elif $l | heading then
        .in = ($l | test("^##\\s+Requirements\\s*$"))
        | if .in then .seen = true | .end = $n else . end
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
| {requirements: .reqs, errors: .errors, end: .end}
