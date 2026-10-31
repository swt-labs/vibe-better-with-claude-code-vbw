# The definition of .vbw/record.json (docs/record.md). Format 4 (D232) is what every write produces:
# schema 4 (5 while settings.efforts holds a helper's chosen effort) and protected, the sorted
# list of every file a check protects, each once ([] without checks), so a guard reads the list
# without reading through the checks (R150). The older formats stay valid until their next write:
# schema 1, 2 when a check is alone, 3 when a todo is sorted or a recommendation is stored; they
# carry no protected field.
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
def nonneg: type == "number" and . >= 0;
# The costs figures (R173) are dollars: {usd}. Records written while tokens were stored (Claude Code gives
# the status line no running token total, so they were dropped) also hold "in" and "out", both together:
# read, never written, never shown.
def figures: type == "object" and (keys | sort | . == ["usd"] or . == ["in","out","usd"]) and all(.[]; nonneg);
def session_figures: type == "object"
  and all(.[]; type == "object" and (keys | sort | . == ["at","usd"] or . == ["at","in","out","usd"])
               and (.at | iso) and (del(.at) | figures));
def strings_array: type == "array" and all(.[]; type == "string");
def loop_item: type == "object"
  and (keys - ["id","text","proof","status","milestone","req","head","baseline","retried","reverts","left","cost","reason","at","opened_at","stepped_at","away","budget"] == [])
  and (.id | type == "string" and test("^T[0-9]+$")) and (.text | nonempty)
  and (.proof | one_of(["auto","human"])) and (.status | one_of(["waiting","in_progress","shipped","parked"]))
  and ((has("milestone") | not) or (.milestone | type == "string" and test("^M[0-9]+$")))
  and ((has("head") | not) or (.head | type == "string" and test("^[0-9a-f]{40}$")))
  and ((has("baseline") | not) or (.baseline | session_figures))
  and ((has("retried") | not) or (.retried | type == "object" and (keys | sort) == ["fixes","plans"]
                                  and (.fixes | strings_array) and (.plans | strings_array)))
  and ((has("reverts") | not) or (.reverts | strings_array))
  and ((has("left") | not) or (.left | nonempty))
  and ((has("req") | not) or (.req | nonempty))
  and ((has("cost") | not) or .cost == null or (.cost | figures))
  and ((has("reason") | not) or (.reason | nonempty))
  and ((has("at") | not) or (.at | iso))
  and ((has("opened_at") | not) or (.opened_at | iso))
  and ((has("stepped_at") | not) or (.stepped_at | iso))
  and ((has("away") | not) or (.away | type == "number" and . == floor and . >= 0))
  and ((has("budget") | not) or (.budget | type == "object" and (keys - ["planned"] | sort) == ["basis","seconds"]
                                 and ((has("planned") | not) or .planned == true)
                                 and (.seconds | type == "number" and . > 0) and (.basis | nonempty)));

# One recorded break of a plan (vbw mutate): a rule or a task K with what was broken,
# the files, each check red or green and the result (a red one may carry pending: the
# check files waiting for approval that caught it), a task with nothing to break, or a rule
# whose check reads no file of its requirement's plans ({rule, none, at, head}).
def mutation_ok:
  type == "object" and (.at | iso)
  and (if has("none") then (.none | nonempty) and (
        if has("rule")
        then (keys | sort) == ["at","head","none","rule"]
          and (.rule | type == "object" and (keys | sort) == ["req","text"] and (.req | nonempty) and (.text | nonempty))
          and (.head | type == "string" and test("^[0-9a-f]{40}$"))
        else (keys | sort) == ["at","none","task"] and (.task | int_in(1; 9999)) end)
      else (keys - ["rule","task","what","files","checks","result","at","head","tree","strengthened","pending"] == [])
        and (has("rule") != has("task"))
        and ((has("rule") | not) or (.rule | type == "object" and (keys | sort) == ["req","text"] and (.req | nonempty) and (.text | nonempty)))
        and ((has("task") | not) or (.task | int_in(1; 9999)))
        and (.what | nonempty)
        and (.files | type == "array" and length > 0 and all(.[]; safe_path))
        and (.checks | type == "object" and length > 0 and all(.[]; one_of(["red","green"])))
        and (.result == (if all(.checks[]; . == "green") then "survivor" else "red" end))
        and (.head | type == "string" and test("^[0-9a-f]{40}$"))
        and ((has("tree") | not) or (.tree | type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$")))
        and ((has("strengthened") | not) or (.strengthened | type == "array" and all(.[]; safe_path)))
        and ((has("pending") | not) or (.pending | type == "array" and length > 0 and all(.[]; safe_path)))
      end);

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
| ([($r.shipped // [])[]?.id] + [($r.parked // [])[]?.id] + [$r.milestone.id?]) as $milestones
| ($plans | map({key: .id, value: (.after // [])}) | from_entries) as $graph
| [
    ( select(($r | has("protected") | not) and ($r.schema == 4 or $r.schema == 5 or $r.schema == 6))
      | "protected is missing: a schema-4, 5 or 6 record must carry the protected field" ),
    ( select(($r | has("protected")) and $r.schema != 4 and $r.schema != 5 and $r.schema != 6)
      | "protected is only for a schema-4, 5 or 6 record" ),
    ( select((($r.settings // {}) | type) == "object" and (($r.settings.efforts // null) != null)
             and $r.schema != 5 and $r.schema != 6)
      | "settings.efforts needs schema 5 (6 with a decision's plans), so a VBW that reads only up to schema 4 asks for an update" ),
    ( select($r.schema == 5 and ((($r.settings // {}) | type) != "object" or ($r.settings.efforts // null) == null))
      | "schema 5 is only for a record with settings.efforts; without them the schema is 4" ),
    ( select(((($r.decisions // []) | type) == "array" and any(($r.decisions // [])[]?; type == "object" and has("plans"))) != ($r.schema == 6))
      | if $r.schema == 6 then "schema 6 is only for a record with a decision that names its plans"
        else "a decision that names its plans needs schema 6, so a VBW that reads only up to schema 5 asks for an update" end ),
    ( select(($r | has("protected") | not) and $r.schema != 4 and $r.schema != 5 and $r.schema != 6
             and $r.schema != (if ($r | has("recommendation")) or ((($r.todos // []) | type) == "array" and any(($r.todos // [])[]?; type == "object" and (has("sort") or has("size")))) then 3
                               elif (($r.checks // []) | type) == "array" and any(($r.checks // [])[]?; type == "object" and .alone == true) then 2 else 1 end))
      | "schema must be 3 when a todo is sorted or a recommendation is stored; schema must be 2 when a check is alone, else 1" ),
    ( select($r | has("protected"))
      | select($r.protected != ([($r.checks // [])[]? | objects | .files? | arrays | .[] | strings] | unique))
      | "protected must be the sorted list of every file the checks protect, each once" ),
    ( $r | keys[]
      | select(one_of(["schema","project","milestone","requirements","checks","phases","plans",
                       "fixes","todos","decisions","commands","test_files","settings","evidence","lease","shipped","parked","converted","recommendation","protected","costs","loop"]) | not)
      | "unknown key: \(.)" ),
    ( ["requirements","checks","phases","plans","fixes","todos","decisions","shipped"][]
      | select(($r[.] | type) != "array") | "\(.) must be an array" ),
    ( select($r | has("parked")) | select(($r.parked | type) != "array") | "parked must be an array" ),

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
    ( $r.project.leave_out? | select(. != null)
      | select((type == "array" and length > 0 and length == (unique | length)
          and all(.[]; safe_path and (rtrimstr("/") | split("/") | .[0] != ".vbw" and .[0] != ".git" and all(.[]; . != "" and . != ".")))) | not)
      | "project.leave_out must be a non-empty array of distinct relative paths, outside .vbw/ and .git/" ),
    ( $r.project.declined? | select(. != null)
      | ( select(type != "array") | "project.declined must be an array" ),
        ( select(type == "array") | .[]
          | select((type == "object" and (keys | sort) == ["at","text"] and (.text | nonempty) and (.at | iso)) | not)
          | "project.declined entries need a text and an ISO-8601 UTC time" ) ),
    ( $r.recommendation? | select(. != null)
      | ( select(type != "object") | "recommendation must be an object" ),
        ( select(type == "object")
          | ( select((.at | iso) | not) | "recommendation.at must be an ISO-8601 UTC time" ),
            ( if .empty == true then select((keys | sort) != ["at","empty"]) | "an empty recommendation has exactly at and empty"
              else select((keys | sort) != ["at","runners","top"]) | "a recommendation has exactly at, top and runners" end ),
            ( select(has("top"))
              | ( .top | select((type == "object" and (.text | nonempty) and (.reason | nonempty) and (.size | one_of(["small","medium","large"]))
                  and ((keys - ["text","reason","size","source"]) | length == 0) and ((has("source") | not) or (.source | nonempty))) | not)
                  | "recommendation.top needs a text, a reason and a size (small, medium or large)" ),
                ( .runners | select((type == "array" and length <= 2 and all(.[]; type == "object" and (.text | nonempty) and (.size | one_of(["small","medium","large"]))
                  and ((keys - ["text","size","source"]) | length == 0) and ((has("source") | not) or (.source | nonempty)))) | not)
                  | "recommendation.runners holds at most two runners-up, each with a text and a size" ) ) ) ),
    ( $r.milestone
      | ( select((.id? | type == "string" and test("^M[0-9]+$")) | not) | "milestone.id must look like M1" ),
        ( select((.title? | nonempty) | not) | "milestone.title must be a non-empty string" ),
        ( select((.status? | one_of(["active","shipped","parked"])) | not) | "milestone.status must be active, shipped or parked" ) ),
    ( arr("shipped")[]
      | ( select(((.id | type == "string" and test("^M[0-9]+$")) and (.title | nonempty) and (.at | iso)) | not)
          | "shipped milestones need an id, a title and an ISO-8601 UTC time" ),
        ( keys[] | select(one_of(["id","title","at"]) | not) | "a shipped milestone has an unknown field: \(.)" ) ),
    ( arr("shipped") | [.[].id] | group_by(.) | map(select(length > 1) | "milestone \(.[0]) is shipped twice") | .[] ),
    ( select(($r.milestone.status == "shipped") != any(arr("shipped")[]; .id == $r.milestone.id))
      | "the current milestone is shipped exactly when it is in shipped" ),
    ( arr("parked")[]
      | ( select(((.id | type == "string" and test("^M[0-9]+$")) and (.title | nonempty) and (.at | iso) and (.reason | nonempty)) | not)
          | "parked milestones need an id, a title, an ISO-8601 UTC time and a reason" ),
        ( select(has("ids") and ((.ids | type == "array" and all(.[]; type == "string" and test("^[PRF][0-9]+$"))) | not))
          | "a parked milestone's ids are the phase, requirement and fix ids it freed (P<n>, R<n>, F<n>)" ),
        ( keys[] | select(one_of(["id","title","at","reason","ids"]) | not) | "a parked milestone has an unknown field: \(.)" ) ),
    ( arr("parked") | [.[].id] | group_by(.) | map(select(length > 1) | "milestone \(.[0]) is parked twice") | .[] ),
    ( arr("parked")[] | .id as $p
      | select(any(arr("shipped")[]; .id == $p)) | "milestone \($p) cannot be both shipped and parked" ),
    ( select(($r.milestone.status == "parked") != any(arr("parked")[]; .id == $r.milestone.id))
      | "the current milestone is parked exactly when it is in parked" ),
    ( arr("parked")[].id as $p
      | ( (arr("requirements")[], arr("phases")[], arr("plans")[]) | select(.milestone? == $p) | "\(.id) belongs to parked milestone \($p): a park leaves no requirement, phase or plan" ) ),

    id_rules($reqs; "^R[0-9]+$"),
    id_rules($checks; "^C[0-9]+$"),
    id_rules($phases; "^P[0-9]+$"),
    id_rules($plans; "^P[0-9]+\\.[0-9]+$"),
    id_rules(arr("fixes"); "^F[0-9]+$"),
    id_rules(arr("todos"); "^T[0-9]+$"),
    id_rules(arr("decisions"); "^D[0-9]+$"),

    ( $reqs[]
      | field_rule(["id","text","proof","status","milestone","rules","skipped","later"]),
        ( select((has("skipped") and .skipped != true) or (has("later") and .later != true)) | "\(.id) skipped and later can only be true" ),
        ( select((has("skipped") or has("later")) and .proof != "human") | "\(.id) is auto-proved and cannot be skipped" ),
        ( select(has("later") and (has("skipped") | not)) | "\(.id) moves to the next milestone only when skipped" ),
        ( select(has("rules") and (.rules | type) != "array") | "\(.id) rules must be an array" ),
        ( select(has("rules") and .proof == "human") | "\(.id) is human-proved and cannot carry rules" ),
        ( . as $q | select(.rules | type == "array") | .rules[]
          | select(type != "object" or ((.text | nonempty) | not)) | "\($q.id) has a rule without text" ),
        ( . as $q | select(.rules | type == "array") | .rules[] | select(type == "object")
          | ( keys[] | select(one_of(["text","check","plan","retired"]) | not) | "\($q.id) has a rule with an unknown field: \(.)" ),
            # A retired rule (T168) keeps its place, words and reason; the check and plan it named may be gone.
            ( . as $x | select(has("retired") and ((.retired | nonempty) | not))
              | "\($q.id) rule \"\($x.text)\" is retired without a reason" ),
            ( . as $x | select((has("retired") | not) and (any($checks[]; .id == $x.check and .req == $q.id) | not))
              | "\($q.id) rule \"\($x.text)\" names \($x.check), which is not a check of \($q.id)" ),
            # The plan that builds the rule's code (T152): one that serves the requirement.
            ( . as $x | select(has("plan") and (has("retired") | not) and (any($plans[]; .id == $x.plan and any(.reqs[]?; . == $q.id)) | not))
              | "\($q.id) rule \"\($x.text)\" names plan \($x.plan), which is not a plan of \($q.id)" ) ),
        ( . as $q | select((.milestone | one_of($milestones)) | not) | "\(.id) belongs to unknown milestone \(.milestone)" ),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        ( select((.proof | one_of(["auto","human"])) | not) | "\(.id) proof must be auto or human" ),
        status_rule(["open","failing","proven","accepted","rejected"]),
        ( select(.proof == "human" and (.status | one_of(["proven","failing"]))) | "\(.id) is human-proved and cannot be \(.status)" ),
        ( select(.proof == "auto" and (.status | one_of(["accepted","rejected"]))) | "\(.id) is auto-proved and cannot be \(.status)" ) ),

    ( $checks[]
      | field_rule(["id","req","run","files","exit","output","timeout","alone","fix"]),
        ( . as $c | select(has("fix") and ((.fix | type) != "string" or (arr("fixes") | has_id($c.fix) | not))) | "\(.id) fix must be the id of an existing fix" ),
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
      | field_rule(["id","phase","title","reqs","files","after","status","note","tasks","role","mutations"]),
        ( select(has("mutations") and ((.mutations | type == "array" and all(.[]; mutation_ok)) | not)) | "\(.id) mutations must be recorded breaks (vbw mutate)" ),
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
      | field_rule(["id","req","command","attempts","status","note","source","phase","restore"]),
        ( select(has("restore") and ((.restore | type) != "string" or (.restore | length) == 0 or has("command") or has("source"))) | "\(.id) restore must be a file path, on a requirement's fix that is not a QA finding" ),
        ( select(has("source") and (.source != "qa" or has("command"))) | "\(.id) source must be qa, for a requirement" ),
        ( . as $o | select(has("phase") and ((.phase | type) != "string" or (any($r.phases[]; .id == $o.phase) | not))) | "\(.id) references unknown phase \(.phase)" ),
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
      | field_rule(["id","text","why","at","plans"]),
        ( select((.text | nonempty) | not) | "\(.id) needs non-empty text" ),
        ( select(has("plans") and ((.plans | type) != "array" or any(.plans[]; nonempty | not))) | "\(.id) plans must be an array of plan ids" ),
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
          ( select(has("command_timeout") and ((.command_timeout | int_in(1; 86400)) | not)) | "settings.command_timeout must be a whole number from 1 to 86400" ),
          ( select(has("check_budget") and ((.check_budget | int_in(1; 86400)) | not)) | "settings.check_budget must be a whole number from 1 to 86400" ),
          ( keys[] | select(one_of(["profile","autonomy","autonomy_cap","models","efforts","rigor","motion","command_timeout","check_budget"]) | not) | "settings has an unknown key: \(.)" ),
          ( select(has("efforts")) | .efforts
            | if type != "object" or length == 0 then "settings.efforts must be an object naming at least one role" else
                to_entries[] | select((.key | one_of(["architect","lead","dev","qa","scout","debugger","docs"])) and (.value | one_of(["low","medium","high","xhigh","max"])) | not)
                | "settings.efforts.\(.key) must name a role (architect, lead, dev, qa, scout, debugger, docs) and low, medium, high, xhigh or max"
              end ),
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
    ( $r.test_files
      | select(. != null)
      | select((type == "object" and (keys == ["files","run"]) and (.run | argv)
                and ((.run | [.[] | [match("\\{file\\}"; "g")] | length] | add) == 1)
                and (.files | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))) | not)
      | "test_files must be {run, files}: run an argv naming {file} exactly once, files a non-empty array of git pathspecs" ),
    ( $r.evidence
      | select(. != null)
      | if type != "object" then "evidence must be null or an object" else
          ( select(((.at | iso) and (.contract | sha256) and (.tree | type == "string" and test("^[0-9a-f]{40,64}$"))
                    and ((has("head") | not) or (.head | type == "string" and test("^([0-9a-f]{40,64})?$")))
                    and ((has("full") | not) or (.full | type == "boolean"))
                    and (.passed | type == "boolean") and (.checks | results) and (.commands | results)
                    and (.scope | type == "array" and all(.[]; type == "string"))) | not)
            | "evidence needs at, contract, tree, passed, checks, commands and scope (docs/proof.md)" )
          , ( select(has("own") and ((.own | type == "object" and (keys == ["copies","planning","record","saving","tracking","wall"])
                    and all(.[]; nonneg)) | not))
            | "evidence.own must be an object with exactly planning, copies, tracking, saving, record and wall, each a number of at least 0 (docs/record.md)" )
          , ( select(has("undone") and ((.undone | type == "array" and all(.[]; type == "object" and (keys == ["by","commit","plan"])
                    and (.commit | type == "string" and test("^[0-9a-f]{40}$")) and (.by | type == "string" and test("^[0-9a-f]{40}$"))
                    and (.plan | type == "string" and test("^P[0-9]+\\.[0-9]+$")))) | not))
            | "evidence.undone must be an array of {commit, plan, by}: commit and by 40 hex digits, plan a plan id P<n>.<m> (docs/record.md)" )
          , ( select(has("causes") and ((.causes | type == "array" and all(.[]; type == "string")) | not))
            | "evidence.causes must be an array of strings (docs/record.md)" )
          , ( def oid: type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$");
              select(has("deviations") and ((.deviations | type == "array" and all(.[]; type == "object" and (keys == ["at","by","change","commit","file","plan"])
                    and (.file | nonempty) and (.plan | type == "string" and test("^P[0-9]+\\.[0-9]+$")) and (.commit | oid) and (.at | iso)
                    and (.change | one_of(["deleted","changed"])) and (.by | type == "array" and all(.[]; oid)))) | not))
            | "evidence.deviations must be an array of {file, plan, commit, at, change, by}: plan a plan id P<n>.<m>, commit a commit id, at an ISO-8601 UTC time, change deleted or changed, by an array of commit ids (docs/record.md)" )
        end ),
    ( $r.costs
      | select(. != null)
      | if type != "object" then "costs must be an object of runs and milestones" else
          ( keys[] | select(one_of(["runs","milestones"]) | not) | "costs has an unknown key: \(.)" ),
          ( select((.runs // []) | type != "array") | "costs.runs must be an array" ),
          ( select((.milestones // {}) | type != "object") | "costs.milestones must be an object" ),
          ( ((.runs // []) | if type == "array" then . else [] end)[]
            | select((type == "object"
                and (keys | sort) == ["cost","ended","id","kind","milestone","session","started"]
                and (.id | nonempty) and (.kind | one_of(["plan","build","fix","qa","map"]))
                and (.session == null or (.session | type == "string"))
                and (.milestone | type == "string" and one_of($milestones))
                and (.started | iso) and (.ended | iso)
                and (.cost == null or (.cost | figures))) | not)
            | "costs.runs entries need exactly id, kind (plan, build, fix, qa or map), session (string or null), milestone (an existing id), started, ended (ISO-8601 UTC) and cost (null or {usd}, a non-negative number)" ),
          ( ((.milestones // {}) | if type == "object" then . else {} end) | to_entries[]
            | select((.key | one_of($milestones)) | not) | "costs.milestones.\(.key) is not an existing milestone" ),
          ( ((.milestones // {}) | if type == "object" then . else {} end) | to_entries[] | .key as $k | .value
            | select((type == "object" and (keys - ["baseline","total"] == []) and has("baseline")
                and (.baseline | session_figures)
                and ((has("total") | not)
                     or (.total | type == "object" and (keys | sort | . == ["sessions","usd"] or . == ["in","out","sessions","usd"])
                         and all(.[]; nonneg)))) | not)
            | "costs.milestones.\($k) needs a baseline of {usd, at} per session and, optionally, a total of {usd, sessions}, all non-negative numbers" )
        end ),
    ( $r.loop
      | select(. != null)
      | if type != "object" then "loop must be an object" else
          ( keys[] | select(one_of(["items","ceiling","session","started_at","baseline","stopping","ended","report","asked"]) | not) | "loop has an unknown field: \(.)" ),
          ( select(has("asked") and ((.asked | type == "object" and (keys | sort) == ["instruction","item"] and (.item | type == "string" and test("^T[0-9]+$"))
                and (.instruction | nonempty)) | not))
            | "loop.asked must be {item: T<n>, instruction: a non-empty string}" ),
          ( select((has("items") and has("ceiling") and has("session") and has("started_at") and has("baseline")) | not)
            | "loop needs items, ceiling, session, started_at and baseline" ),
          ( select(has("items") and ((.items | type == "array" and length > 0 and all(.[]; loop_item)) | not))
            | "loop.items must be a non-empty array of {id: T<n>, text, proof: auto|human, status: waiting|in_progress|shipped|parked, and optionally milestone, head, baseline, retried, reverts, cost, reason, at, opened_at, stepped_at, away (whole seconds), budget: {seconds, basis, planned?}}" ),
          ( select(has("items") and (.items | type == "array") and ((.items | map(.id? // null) | length) != (.items | map(.id? // null) | unique | length)))
            | "loop.items names an item twice" ),
          ( select(has("ceiling") and (.ceiling != null) and ((.ceiling | type == "object" and (keys | sort) == ["finish_item","usd"]
                and (.usd | type == "number" and . > 0) and (.finish_item | type == "boolean")) | not))
            | "loop.ceiling must be null or {usd: a number above 0, finish_item: true or false}" ),
          ( select(has("session") and (.session != null) and (.session | type != "string")) | "loop.session must be a string or null" ),
          ( select(has("started_at") and ((.started_at | iso) | not)) | "loop.started_at must be an ISO-8601 UTC time" ),
          ( select(has("baseline") and ((.baseline | session_figures) | not))
            | "loop.baseline needs, per session, {usd, at} with a non-negative number" ),
          ( select(has("stopping") and ((.stopping | type == "object" and (keys | sort) == ["at","session"] and (.at | iso)
                and (.session == null or (.session | type == "string"))) | not))
            | "loop.stopping must be {at: an ISO-8601 UTC time, session: a string or null}" ),
          ( select(has("ended") and ((.ended | type == "object" and (keys | sort) == ["at","reason"] and (.at | iso) and (.reason | nonempty)) | not))
            | "loop.ended must be {at: an ISO-8601 UTC time, reason}" ),
          ( select(has("report") and ((.report | safe_path) | not)) | "loop.report must be a relative path" )
        end ),
    ( $r.lease
      | select(. != null)
      | if type != "object" then "lease must be null or an object" else
          ( select(((.run | nonempty) and (.kind | one_of(["plan","build","fix","qa","map"])) and (.started_at | iso)
                    and (.files == null or (.files | type == "array" and all(.[]; safe_path)))
                    and ((has("session") | not) or (.session | type == "string" and length > 0))
                    and ((has("editable") | not) or (.editable | type == "array" and all(.[]; safe_path)))
                    and ((has("new_tests") | not) or (.new_tests | type == "boolean"))
                    and ((has("cost") | not) or .cost == null or (.cost | figures))) | not)
            | "lease needs run, kind (plan, build, fix, qa or map), started_at (ISO-8601 UTC) and files (null or relative paths) and optionally a session (string), cost (null or the costs figures {usd}), editable (relative paths) and new_tests (true or false)" ),
          ( select(has("new_tests") and .kind != "fix") | "only a fix run carries new_tests" ),
          ( select(has("editable") and (.kind | one_of(["fix","build"]) | not)) | "only a fix or build run carries editable" ),
          ( . as $l | keys[] | select(one_of(["run","kind","started_at","files","session","editable","new_tests","cost"]) | not) | "lease has an unknown field: \(.)" )
        end )
  ]
end
