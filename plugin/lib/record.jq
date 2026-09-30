# The definition of .vbw/record.json, schema 1 (docs/record.md).
# Input: the record. Output: a JSON array of violation messages; [] = valid.

def nonempty: type == "string" and length > 0;
def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
def safe_path: type == "string" and length > 0 and (startswith("/") | not)
  and (split("/") | any(. == "..") | not);
def one_of($vals): . as $v | any($vals[]; . == $v);
def ids: [.[]?.id];
def has_id($x): any(.[]?; .id == $x);

# Plan ids reachable from $n through "after" edges ($g: id -> [ids]).
def reachable($g; $n):
  {seen: [], todo: ($g[$n] // [])}
  | until(.todo | length == 0;
      .todo[0] as $x | .todo |= .[1:]
      | if any(.seen[]; . == $x) then . else .seen += [$x] | .todo += ($g[$x] // []) end)
  | .seen;

def id_rules($items; $pattern):
  ($items | ids | map(select(type != "string" or (test($pattern) | not)) | "bad id: \(.)") | .[]),
  ($items | ids | group_by(.) | map(select(length > 1) | "duplicate id: \(.[0])") | .[]);

def status_rule($enum): select((.status | one_of($enum)) | not) | "\(.id) has an invalid status: \(.status)";

def field_rule($allowed): . as $o | keys[] | select(one_of($allowed) | not) | "\($o.id) has an unknown field: \(.)";

if type != "object" then ["record must be a JSON object"] else
. as $r
| def arr($k): ($r[$k] | if type == "array" then . else [] end);
  (arr("requirements")) as $reqs
| (arr("checks")) as $checks
| (arr("phases")) as $phases
| (arr("plans")) as $plans
| ($plans | map({key: .id, value: (.after // [])}) | from_entries) as $graph
| [
    ( select($r.schema != 1) | "schema must be 1" ),
    ( $r | keys[]
      | select(one_of(["schema","project","milestone","requirements","checks","phases","plans",
                       "fixes","todos","decisions","contract","evidence","lease"]) | not)
      | "unknown key: \(.)" ),
    ( ["requirements","checks","phases","plans","fixes","todos","decisions"][]
      | select(($r[.] | type) != "array") | "\(.) must be an array" ),

    ( select(($r.project.name? | nonempty) | not) | "project.name must be a non-empty string" ),
    ( $r.milestone
      | ( select((.id? | type == "string" and test("^M[0-9]+$")) | not) | "milestone.id must look like M1" ),
        ( select((.title? | nonempty) | not) | "milestone.title must be a non-empty string" ),
        ( select((.status? | one_of(["active","shipped"])) | not) | "milestone.status must be active or shipped" ) ),

    id_rules($reqs; "^R[0-9]+$"),
    id_rules($checks; "^C[0-9]+$"),
    id_rules($phases; "^P[0-9]+$"),
    id_rules($plans; "^P[0-9]+\\.[0-9]+$"),
    id_rules(arr("fixes"); "^F[0-9]+$"),
    id_rules(arr("todos"); "^T[0-9]+$"),
    id_rules(arr("decisions"); "^D[0-9]+$"),

    ( $reqs[]
      | field_rule(["id","text","proof","checks","status"]),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        ( select((.proof | one_of(["auto","human"])) | not) | "\(.id) proof must be auto or human" ),
        ( . as $q | (.checks // [])[] | . as $x | select(($checks | has_id($x)) | not) | "\($q.id) references unknown check \(.)" ),
        status_rule(["open","failing","proven","accepted","rejected"]),
        ( select(.proof == "human" and ((.checks // []) | length) > 0) | "\(.id) is human-proved and cannot have checks" ),
        ( select(.proof == "human" and (.status | one_of(["proven","failing"]))) | "\(.id) is human-proved and cannot be \(.status)" ),
        ( select(.proof == "auto" and (.status | one_of(["accepted","rejected"]))) | "\(.id) is auto-proved and cannot be \(.status)" ) ),

    ( $checks[]
      | field_rule(["id","req","kind","path"]),
        ( . as $o | select(($reqs | has_id($o.req)) | not) | "\(.id) references unknown requirement \(.req)" ),
        ( select((.kind | one_of(["spec","test"])) | not) | "\(.id) kind must be spec or test" ),
        ( select((.path | safe_path) | not) | "\(.id) has an unsafe path: \(.path)" ) ),

    ( $phases[]
      | field_rule(["id","title","reqs","status"]),
        ( select((.title | nonempty) | not) | "\(.id) needs a non-empty title" ),
        ( . as $p | (.reqs // [])[] | . as $x | select(($reqs | has_id($x)) | not) | "\($p.id) references unknown requirement \(.)" ),
        status_rule(["planned","building","built"]) ),

    ( $plans[]
      | field_rule(["id","phase","title","reqs","files","after","status"]),
        ( . as $o | select(($phases | has_id($o.phase)) | not) | "\(.id) references unknown phase \(.phase)" ),
        ( select((.id | type == "string") and (.phase | type == "string")
                 and (.phase as $ph | (.id | startswith($ph + ".")) | not)) | "plan \(.id) is not in its phase \(.phase)" ),
        ( select((.title | nonempty) | not) | "\(.id) needs a non-empty title" ),
        ( . as $p | (.reqs // [])[] | . as $x | select(($reqs | has_id($x)) | not) | "\($p.id) references unknown requirement \(.)" ),
        ( . as $p | (.files // [])[] | select(safe_path | not) | "\($p.id) has an unsafe path: \(.)" ),
        ( select(((.files // []) | length) != ((.files // []) | unique | length)) | "\(.id) lists a file twice" ),
        ( . as $p | (.after // [])[] | . as $x | select(($plans | has_id($x)) | not) | "\($p.id) references unknown plan \(.)" ),
        status_rule(["planned","building","done","blocked"]),
        ( select(.id as $id | reachable($graph; $id) | any(.[]; . == $id)) | "plan dependency cycle through \(.id)" ) ),

    ( arr("fixes")[]
      | field_rule(["id","req","attempts","status","note"]),
        ( . as $o | select(($reqs | has_id($o.req)) | not) | "\(.id) references unknown requirement \(.req)" ),
        ( select((.attempts | type == "number" and . >= 0 and . == floor) | not) | "\(.id) attempts must be a non-negative integer" ),
        status_rule(["open","closed","escalated"]) ),

    ( arr("todos")[]
      | field_rule(["id","text","status"]),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        status_rule(["open","in_progress","done","dropped"]) ),

    ( arr("decisions")[]
      | field_rule(["id","text","at"]),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        ( select((.at | iso) | not) | "\(.id) needs an ISO-8601 UTC timestamp" ) ),

    ( $r.contract
      | if type != "object" then "contract must be an object" else
          ( select(.hash != null and ((.hash | type == "string" and test("^[0-9a-f]{64}$")) | not)) | "contract hash must be a SHA-256 hex digest" ),
          ( select(.approved_at != null and ((.approved_at | iso) | not)) | "contract approved_at must be ISO-8601 UTC" ),
          ( select((.hash == null) != (.approved_at == null)) | "contract hash and approved_at must both be set or both be null" )
        end ),

    ( select(($r.evidence | type) != "null" and ($r.evidence | type) != "object") | "evidence must be null or an object" ),
    ( $r.lease
      | select(. != null)
      | if type != "object" then "lease must be null or an object" else
          ( select(((.run | nonempty) and (.session | nonempty) and (.started_at | iso) and (.agents | type == "array")) | not)
            | "lease needs run, session, started_at (ISO-8601 UTC) and agents[]" )
        end )
  ]
end
