# The definition of .vbw/record.json: schema 1, 2 when a check is alone, 3 when a todo is sorted (docs/record.md).
# Input: the record. Output: a JSON array of violation messages; [] = valid.

def nonempty: type == "string" and length > 0;
def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
def safe_path: type == "string" and length > 0 and (startswith("/") | not)
  and (split("/") | any(. == "..") | not);
def one_of($vals): . as $v | any($vals[]; . == $v);
def argv: type == "array" and length > 0 and all(.[]; nonempty and (contains("\u0000") | not));
def int_in($lo; $hi): type == "number" and . == floor and . >= $lo and . <= $hi;
def sha256: type == "string" and test("^[0-9a-f]{64}$");
def results: type == "object" and all(.[];
  type == "object" and (.status | one_of(["pass","fail","timeout","skipped"]))
  and (.exit == null or (.exit | int_in(0; 255))) and (.seconds | type == "number")
  and (.tail | type == "string"));
def ids: [.[]?.id];
def has_id($x): any(.[]?; .id == $x);
def tier: one_of(["express","standard","deep"]);
def count: type == "number" and . == floor and . >= 0;

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
| ([($r.shipped // [])[]?.id] + [$r.milestone.id?]) as $milestones
| ($plans | map({key: .id, value: (.after // [])}) | from_entries) as $graph
| [
    ( select($r.schema != (if (($r.todos // []) | type) == "array" and any(($r.todos // [])[]?; type == "object" and (has("sort") or has("size"))) then 3
                           elif (($r.checks // []) | type) == "array" and any(($r.checks // [])[]?; type == "object" and .alone == true) then 2 else 1 end))
      | "schema must be 3 when a todo is sorted; schema must be 2 when a check is alone, else 1" ),
    ( $r | keys[]
      | select(one_of(["schema","project","milestone","requirements","checks","phases","plans",
                       "fixes","todos","decisions","commands","settings","evidence","lease","shipped","converted"]) | not)
      | "unknown key: \(.)" ),
    ( ["requirements","checks","phases","plans","fixes","todos","decisions","shipped"][]
      | select(($r[.] | type) != "array") | "\(.) must be an array" ),

    ( select(($r.project.name? | nonempty) | not) | "project.name must be a non-empty string" ),
    ( ($ARGS.named.interview[0]? // null) as $allowed
      | $r.project.interview? | select(. != null)
      | ( select(type != "object") | "project.interview must be an object" ),
        ( select(type == "object")
          | ( keys[] | select(one_of(["level","depth","involvement","at"]) | not) | "project.interview has an unknown field: \(.)" ),
            ( .at | select(iso | not) | "project.interview.at must be an ISO-8601 UTC time" ),
            ( . as $i | ["level","depth","involvement"][] as $k
              | select(($i[$k] | type) != "string" or ($allowed != null and (($i[$k] | one_of($allowed[$k])) | not)))
              | "project.interview.\($k) must be one of: \(if $allowed != null then $allowed[$k] | join(", ") else "a string" end)" ) ) ),
    ( $r.project.tools? | select(. != null)
      | select((type == "object" and (keys | sort) == ["answer","at"] and (.answer | one_of(["yes","no"])) and (.at | iso)) | not)
      | "project.tools must be an answer (yes or no) and an ISO-8601 UTC time" ),
    ( $r.project.legacy? | select(. != null)
      | select((type == "object" and (keys | sort) == ["at","choice"] and (.choice | one_of(["convert","fresh"])) and (.at | iso)) | not)
      | "project.legacy must be a choice (convert or fresh) and an ISO-8601 UTC time" ),
    ( $r.project.results? | select(. != null)
      | select((type == "array" and length > 0 and length == (unique | length)
          and all(.[]; safe_path and endswith("/") and (split("/") | .[0] != ".vbw" and all(.[:-1][]; . != "" and . != ".")))) | not)
      | "project.results must be a non-empty array of distinct relative folders ending in /, outside .vbw/" ),
    ( $r.project.declined? | select(. != null)
      | ( select(type != "array") | "project.declined must be an array" ),
        ( select(type == "array") | .[]
          | select((type == "object" and (keys | sort) == ["at","text"] and (.text | nonempty) and (.at | iso)) | not)
          | "project.declined entries need a text and an ISO-8601 UTC time" ) ),
    ( $r.milestone
      | ( select((.id? | type == "string" and test("^M[0-9]+$")) | not) | "milestone.id must look like M1" ),
        ( select((.title? | nonempty) | not) | "milestone.title must be a non-empty string" ),
        ( select((.status? | one_of(["active","shipped"])) | not) | "milestone.status must be active or shipped" ) ),
    ( arr("shipped")[]
      | ( select(((.id | type == "string" and test("^M[0-9]+$")) and (.title | nonempty) and (.at | iso)) | not)
          | "shipped milestones need an id, a title and an ISO-8601 UTC time" ),
        ( keys[] | select(one_of(["id","title","at"]) | not) | "a shipped milestone has an unknown field: \(.)" ) ),
    ( arr("shipped") | [.[].id] | group_by(.) | map(select(length > 1) | "milestone \(.[0]) is shipped twice") | .[] ),
    ( select(($r.milestone.status == "shipped") != any(arr("shipped")[]; .id == $r.milestone.id))
      | "the current milestone is shipped exactly when it is in shipped" ),

    id_rules($reqs; "^R[0-9]+$"),
    id_rules($checks; "^C[0-9]+$"),
    id_rules($phases; "^P[0-9]+$"),
    id_rules($plans; "^P[0-9]+\\.[0-9]+$"),
    id_rules(arr("fixes"); "^F[0-9]+$"),
    id_rules(arr("todos"); "^T[0-9]+$"),
    id_rules(arr("decisions"); "^D[0-9]+$"),

    ( $reqs[]
      | field_rule(["id","text","proof","status","milestone","rules"]),
        ( select(has("rules") and (.rules | type) != "array") | "\(.id) rules must be an array" ),
        ( select(has("rules") and .proof == "human") | "\(.id) is human-proved and cannot carry rules" ),
        ( . as $q | select(.rules | type == "array") | .rules[]
          | select(type != "object" or ((.text | nonempty) | not)) | "\($q.id) has a rule without text" ),
        ( . as $q | select(.rules | type == "array") | .rules[] | select(type == "object")
          | ( keys[] | select(one_of(["text","check"]) | not) | "\($q.id) has a rule with an unknown field: \(.)" ),
            ( . as $x | select(any($checks[]; .id == $x.check and .req == $q.id) | not)
              | "\($q.id) rule \"\($x.text)\" names \($x.check), which is not a check of \($q.id)" ) ),
        ( . as $q | select((.milestone | one_of($milestones)) | not) | "\(.id) belongs to unknown milestone \(.milestone)" ),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        ( select((.proof | one_of(["auto","human"])) | not) | "\(.id) proof must be auto or human" ),
        status_rule(["open","failing","proven","accepted","rejected"]),
        ( select(.proof == "human" and (.status | one_of(["proven","failing"]))) | "\(.id) is human-proved and cannot be \(.status)" ),
        ( select(.proof == "auto" and (.status | one_of(["accepted","rejected"]))) | "\(.id) is auto-proved and cannot be \(.status)" ) ),

    ( $checks[]
      | field_rule(["id","req","run","files","exit","output","timeout","alone"]),
        ( . as $o | select(($reqs | has_id($o.req)) | not) | "\(.id) references unknown requirement \(.req)" ),
        ( . as $o | select(any($reqs[]; .id == $o.req and .proof == "human")) | "\(.id) checks human-proved \(.req): only a person can judge it" ),
        ( select((.run | argv) | not) | "\(.id) run must be a non-empty argv array" ),
        ( . as $c | (.files // [])[] | select(safe_path | not) | "\($c.id) has an unsafe path: \(.)" ),
        ( select(has("files") and (.files | type) != "array") | "\(.id) files must be an array" ),
        ( select(has("exit") and ((.exit | int_in(0; 255)) | not)) | "\(.id) exit must be an integer 0-255" ),
        ( select(has("output") and ((.output | nonempty and (try (test(.) | true) catch false)) | not)) | "\(.id) output must be a valid regular expression" ),
        ( select(has("alone") and (.alone | type) != "boolean") | "\(.id) alone must be a boolean" ),
        ( select(has("timeout") and ((.timeout | int_in(1; 3600)) | not)) | "\(.id) timeout must be 1-3600 seconds" ) ),

    ( $phases[]
      | field_rule(["id","title","reqs","milestone","goal","criteria","qa","tier","proposed","reasons","predicted","escalations","outcome"]),
        ( select(has("tier") and ((.tier | tier) | not)) | "\(.id) tier must be express, standard or deep" ),
        ( select(has("proposed") and ((.proposed | tier) | not)) | "\(.id) proposed must be express, standard or deep" ),
        ( select(has("predicted") and ((.predicted | tier) | not)) | "\(.id) predicted must be express, standard or deep" ),
        ( select(has("reasons") and ((.reasons | type == "array" and all(.[]; type == "string")) | not)) | "\(.id) reasons must be an array of strings" ),
        ( select(has("escalations") and ((.escalations | type == "array" and all(.[];
              type == "object" and (keys - ["at","from","to","reason"] == []) and (.at | iso)
              and (.from | tier) and (.to | tier) and (.reason | nonempty))) | not))
          | "\(.id) escalations must be [{at, from: tier, to: tier, reason}]" ),
        ( select(has("outcome") and ((.outcome | type == "object" and (keys - ["tier","predicted","held","fix_rounds","qa_findings","escalations"] == [])
              and (.tier | tier) and (.predicted | tier) and (.held | type == "boolean")
              and (.fix_rounds | count) and (.qa_findings | count) and (.escalations | count)) | not))
          | "\(.id) outcome must be {tier, predicted, held: boolean, fix_rounds, qa_findings, escalations}" ),
        ( select(has("goal") and ((.goal | nonempty) | not)) | "\(.id) goal must be a non-empty string" ),
        ( select(has("criteria") and ((.criteria | type == "array") and all(.criteria[]; nonempty) | not)) | "\(.id) criteria must be an array of non-empty strings" ),
        ( select(has("qa")) | .qa as $q
          | select(($q | type == "object") and ($q | keys - ["result","tier","tree","at","note","rounds"] == [])
                   and ($q.result | one_of(["pass","fail"])) and ($q.tier | one_of(["quick","standard","deep"]))
                   and ($q.tree | nonempty) and ($q.at | iso)
                   and (($q | has("rounds") | not) or ($q.rounds | type == "number" and . >= 1 and . == floor)) | not)
          | "\(.id) qa must be {result: pass|fail, tier: quick|standard|deep, tree, at, note?, rounds?}" ),
        ( select((.milestone | one_of($milestones)) | not) | "\(.id) belongs to unknown milestone \(.milestone)" ),
        ( select((.reqs | type == "array" and length > 0) | not) | "\(.id) needs a non-empty reqs array" ),
        ( select((.title | nonempty) | not) | "\(.id) needs a non-empty title" ),
        ( . as $p | (.reqs // [])[] | . as $x | select(($reqs | has_id($x)) | not) | "\($p.id) references unknown requirement \(.)" ) ),

    ( $plans[]
      | field_rule(["id","phase","title","reqs","files","after","status","note","tasks","role"]),
        ( select(has("tasks") and ((.tasks | type == "array" and length > 0) and all(.tasks[]; nonempty) | not)) | "\(.id) tasks must be a non-empty array of non-empty strings" ),
        ( select(has("role") and (.role | one_of(["dev","docs"]) | not)) | "\(.id) role must be dev or docs" ),
        ( select(has("note") and ((.note | nonempty) | not)) | "\(.id) note must be a non-empty string" ),
        ( . as $o | select(($phases | has_id($o.phase)) | not) | "\(.id) references unknown phase \(.phase)" ),
        ( select((.id | type == "string") and (.phase | type == "string")
                 and (.phase as $ph | (.id | startswith($ph + ".")) | not)) | "plan \(.id) is not in its phase \(.phase)" ),
        ( select((.title | nonempty) | not) | "\(.id) needs a non-empty title" ),
        ( . as $p | (.reqs // [])[] | . as $x | select(($reqs | has_id($x)) | not) | "\($p.id) references unknown requirement \(.)" ),
        ( select((.reqs | type == "array" and length > 0) | not) | "\(.id) needs a non-empty reqs array" ),
        ( select((.files | type == "array" and length > 0) | not) | "\(.id) needs a non-empty files array" ),
        ( select((.after | type) != "array") | "\(.id) after must be an array" ),
        ( . as $p | (.files // [])[] | select(safe_path | not) | "\($p.id) has an unsafe path: \(.)" ),
        ( select(((.files // []) | length) != ((.files // []) | unique | length)) | "\(.id) lists a file twice" ),
        ( . as $p | (.after // [])[] | . as $x | select(($plans | has_id($x)) | not) | "\($p.id) references unknown plan \(.)" ),
        status_rule(["planned","building","done","blocked"]),
        ( select(.id as $id | reachable($graph; $id) | any(.[]; . == $id)) | "plan dependency cycle through \(.id)" ) ),

    ( arr("fixes")[]
      | field_rule(["id","req","command","attempts","status","note","source"]),
        ( select(has("source") and (.source != "qa" or has("command"))) | "\(.id) source must be qa, for a requirement" ),
        ( select(has("req") == has("command")) | "\(.id) needs exactly one of req or command" ),
        ( . as $o | select(has("req") and (($reqs | has_id($o.req)) | not)) | "\(.id) references unknown requirement \(.req)" ),
        ( . as $o | select(has("command") and (($r.commands | type == "object" and has($o.command | tostring)) | not))
          | "\(.id) references unknown command \(.command)" ),
        ( select((.note | type) != "string") | "\(.id) note must be a string" ),
        ( select((.attempts | type == "number" and . >= 0 and . == floor) | not) | "\(.id) attempts must be a non-negative integer" ),
        status_rule(["open","fixed","closed","escalated"]) ),

    ( arr("todos")[]
      | field_rule(["id","text","status","sort","size"]),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        ( select(has("sort") != has("size")) | "\(.id) needs both sort and size, or neither" ),
        ( select(has("sort") and ((.sort | one_of(["next","later"])) | not)) | "\(.id) has an invalid sort: \(.sort)" ),
        ( select(has("size") and ((.size | one_of(["small","medium","large"])) | not)) | "\(.id) has an invalid size: \(.size)" ),
        status_rule(["open","in_progress","done","dropped"]) ),

    ( arr("decisions")[]
      | field_rule(["id","text","why","at"]),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        ( select(has("why") and (.why | nonempty | not)) | "\(.id) why must be a non-empty string" ),
        ( select((.at | iso) | not) | "\(.id) needs an ISO-8601 UTC timestamp" ) ),

    ( select($r | has("converted")) | $r.converted
      | select((type == "object" and (keys == ["at", "from"]) and .from == ".vbw-planning" and (.at | iso)) | not)
      | "converted must be {from: \".vbw-planning\", at: an ISO-8601 UTC time}" ),

    ( $r.settings
      | if type != "object" then "settings must be an object" else
          ( select((.profile | one_of(["quality","balanced","budget"])) | not) | "settings.profile must be quality, balanced or budget" ),
          ( select((.autonomy_cap | int_in(1; 500)) | not) | "settings.autonomy_cap must be an integer 1-500" ),
          ( select(has("autonomy") and (.autonomy | one_of(["guided","balanced","hands-off"]) | not)) | "settings.autonomy must be guided, balanced or hands-off" ),
          ( select(has("rigor") and (.rigor | one_of(["auto","express","standard","deep"]) | not)) | "settings.rigor must be auto, express, standard or deep" ),
          ( select(has("motion") and (.motion | one_of(["full","calm","off"]) | not)) | "settings.motion must be full, calm or off" ),
          ( keys[] | select(one_of(["profile","autonomy","autonomy_cap","models","rigor","motion"]) | not) | "settings has an unknown key: \(.)" ),
          ( select(has("models")) | .models
            | if type != "object" then "settings.models must be an object" else
                to_entries[] | select((.key | one_of(["architect","lead","dev","qa","scout","debugger","docs","planner","critic","builder"])) and (.value | nonempty) | not)
                | "settings.models.\(.key) must name a role (architect, lead, dev, qa, scout, debugger, docs) and a model"
              end )
        end ),
    ( $r.commands
      | if type != "object" then "commands must be an object of name: argv" else
          to_entries[] | select((.value | argv) | not)
          | "command \(.key) must be a non-empty argv array"
        end ),
    ( $r.evidence
      | select(. != null)
      | if type != "object" then "evidence must be null or an object" else
          ( select(((.at | iso) and (.contract | sha256) and (.tree | type == "string" and test("^[0-9a-f]{40,64}$"))
                    and ((has("head") | not) or (.head | type == "string" and test("^([0-9a-f]{40,64})?$")))
                    and ((has("full") | not) or (.full | type == "boolean"))
                    and (.passed | type == "boolean") and (.checks | results) and (.commands | results)
                    and (.scope | type == "array" and all(.[]; type == "string"))) | not)
            | "evidence needs at, contract, tree, passed, checks, commands and scope (docs/proof.md)" )
        end ),
    ( $r.lease
      | select(. != null)
      | if type != "object" then "lease must be null or an object" else
          ( select(((.run | nonempty) and (.kind | one_of(["plan","build","fix","qa","map"])) and (.started_at | iso)
                    and (.files == null or (.files | type == "array" and all(.[]; safe_path)))
                    and ((has("session") | not) or (.session | type == "string" and length > 0))) | not)
            | "lease needs run, kind (plan, build, fix, qa or map), started_at (ISO-8601 UTC) and files (null or relative paths) and optionally a session (string)" ),
          ( . as $l | keys[] | select(one_of(["run","kind","started_at","files","session"]) | not) | "lease has an unknown field: \(.)" )
        end )
  ]
end
