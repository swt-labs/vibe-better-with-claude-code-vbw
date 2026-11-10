# The record's schema, defined once (R247, docs/record.md Versioning). record_update in
# record.sh computes the schema of every write with schema_of, and record.jq refuses a
# schema above it. Definitions only: an included module may hold no main expression.
# Each row is a feature that raised the schema (optional "lead": how the refusal introduces it); the highest one present in the record wins.
# Evaluated on the record (null input works). The feature words are used by the refusal
# message and the docs.

# Every record field that holds a file fingerprint (a SHA-256 digest), R286: a secret scanner's
# keyword rule (api, key, token, auth, secret ...) refuses a line holding such a word and a 64-hex
# value, so no line pairs a path with a digest.
#   plans[].mutations[].digests  a list of {file, sha256}, path and digest on lines of their own
#                                (VBW 2.1.28 and older: an object {file: digest}, read by digests_list)
#   evidence.test_files          the path is a key on its own line; its fp is on another line
#   evidence.checks/commands fp, evidence.record, evidence.contract, a break's contract and
#   phases[].qa.tree             carry no path
# Free text the project writes (a test's output tail) is kept as written.

def schema_floor: 4;

# A break's digests as the list of {file, sha256} sorted by file; the older object {file: digest}
# is read through it (R286). Anything else stays as it is.
def digests_list:
  if type == "object" then to_entries | map({file: .key, sha256: .value}) | sort_by(.file)
  elif type == "array" then sort_by(if type == "object" then (.file // "") else "" end)
  else . end;

def schema_features: [
  {schema: 5, feature: "settings.efforts",
   present: ((.settings | type) == "object" and (.settings.efforts // null) != null)},
  {schema: 6, feature: "a decision that names its plans",
   present: ((.decisions | type) == "array" and any(.decisions[]; type == "object" and has("plans")))},
  {schema: 7, feature: "settings.mcp",
   present: ((.settings | type) == "object" and (.settings.mcp // null) != null)},
  {schema: 8, feature: "a recorded break that carries tree or contract",
   present: ((.plans | type) == "array" and any(.plans[]; type == "object" and (.mutations | type) == "array"
     and any(.mutations[]; type == "object" and (has("tree") or has("contract")))))},
  {schema: 9, feature: "an amendment, an awaited check or a queued requirement", lead: "",
   present: (((.plans | type) == "array" and any(.plans[]; type == "object" and (has("amendments") or has("awaits"))))
     or ((.checks | type) == "array" and any(.checks[]; type == "object" and has("amendments")))
     or ((.requirements | type) == "array" and any(.requirements[]; type == "object" and .queued == true)))},
  # Named forms or a dir: test_files is stored as an array; one plain form stays {run, files}.
  {schema: 10, feature: "a list of test file forms",
   present: ((.test_files | type) == "array")},
  {schema: 11, feature: "a proof that kept its clean copies",
   present: ((.evidence | type) == "object" and (.evidence.own | type) == "object" and (.evidence.own | has("copy_slots")))},
  {schema: 12, feature: "a break that names its rule by place or a requirement reworded with its rules kept",
   present: (((.plans | type) == "array" and any(.plans[]; type == "object" and (.mutations | type) == "array"
     and any(.mutations[]; type == "object" and (.rule | type) == "object" and (.rule | has("k")))))
     or ((.requirements | type) == "array" and any(.requirements[]; type == "object" and .reworded == true)))},
  {schema: 13, feature: "a recorded break that carries digests",
   present: ((.plans | type) == "array" and any(.plans[]; type == "object" and (.mutations | type) == "array"
     and any(.mutations[]; type == "object" and has("digests"))))},
  {schema: 14, feature: "a rule's --none entry marked git (its check reads the project through git)",
   present: ((.plans | type) == "array" and any(.plans[]; type == "object" and (.mutations | type) == "array"
     and any(.mutations[]; type == "object" and has("git"))))},
  {schema: 15, feature: "a break whose digests are a list, or a plan's red-first runs",
   present: ((.plans | type) == "array" and any(.plans[]; type == "object"
     and (has("red_runs")
          or ((.mutations | type) == "array"
              and any(.mutations[]; type == "object" and (.digests | type) == "array")))))}
];

def schema_of: . as $r | [schema_features[] | select(.present) | .schema] | max // schema_floor;

def schema_top: [schema_features[].schema] | max;

# R258: a break that names its rule by text ({req, text}) is converted to the rule's place,
# {req, k}: k is the 1-based place in the requirement's rules, retired ones counted. A
# break whose text matches no rule of its requirement is kept as it is. Run on every write,
# so the first write of an older record converts it; a converted record is unchanged.
def breaks_by_place:
  . as $r
  | if (.plans | type) != "array" then .
    else .plans |= map(
      if type == "object" and (.mutations | type) == "array" then
        .mutations |= map(
          if type == "object" and (.rule | type) == "object" and (.rule | has("text")) then
            ((.rule.req) as $q | (.rule.text) as $t
             | ([($r.requirements // [])[] | select(type == "object" and .id == $q) | (.rules // []) | to_entries[]
                 | select(.value.text == $t) | .key + 1] | first) as $k
             | if $k == null then . else .rule = {req: $q, k: $k} end)
          else . end)
      else . end) end;

# R265: once the record holds a break with digests, an older break of it (written before schema 13)
# gets digests: [] (none recorded), so every break carries the key and the validator can require it.
def breaks_with_digests:
  if (.plans | type) != "array"
     or (any(.plans[]; type == "object" and (.mutations | type) == "array"
         and any(.mutations[]; type == "object" and ((.digests // []) | length) > 0)) | not) then .
  else .plans |= map(
      if type == "object" and (.mutations | type) == "array" then
        .mutations |= map(if type == "object" and (has("none") | not) and (has("digests") | not) then . + {digests: []} else . end)
      else . end) end;

# R286: every write turns a break's older digests object into the list; files and values unchanged.
def breaks_digests_list:
  if (.plans | type) != "array" then .
  else .plans |= map(
      if type == "object" and (.mutations | type) == "array" then
        .mutations |= map(if type == "object" and has("digests") then .digests |= digests_list else . end)
      else . end) end;
