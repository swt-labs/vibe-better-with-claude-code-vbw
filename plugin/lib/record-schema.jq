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
     or ((.requirements | type) == "array" and any(.requirements[]; type == "object" and .queued == true)))}
];

def schema_of: . as $r | [schema_features[] | select(.present) | .schema] | max // schema_floor;

def schema_top: [schema_features[].schema] | max;
