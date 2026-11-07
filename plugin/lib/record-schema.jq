# The record's schema, defined once (R247, docs/record.md Versioning). record_update in
# record.sh computes the schema of every write with schema_of, and record.jq refuses a
# schema above it. Definitions only: an included module may hold no main expression.
# Each row is a feature that raised the schema (optional "lead": how the refusal introduces it); the highest one present in the record wins.
# Evaluated on the record (null input works). The feature words are used by the refusal
# message and the docs.

def schema_floor: 4;

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
     and any(.mutations[]; type == "object" and has("digests"))))}
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
# gets digests: {} (none recorded), so every break carries the key and the validator can require it.
def breaks_with_digests:
  if (.plans | type) != "array"
     or (any(.plans[]; type == "object" and (.mutations | type) == "array"
         and any(.mutations[]; type == "object" and ((.digests // {}) | length) > 0)) | not) then .
  else .plans |= map(
      if type == "object" and (.mutations | type) == "array" then
        .mutations |= map(if type == "object" and (has("none") | not) and (has("digests") | not) then . + {digests: {}} else . end)
      else . end) end;
