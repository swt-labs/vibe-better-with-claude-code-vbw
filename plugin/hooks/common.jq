# Shared by the PreToolUse guards (docs/guards.md). Each guard runs as jq
# itself (build plan K20), with --arg root "$CLAUDE_PROJECT_DIR". Its inputs, in
# order: the hook input (stdin); $CLAUDE_PROJECT_DIR/.vbw/record.json, which jq
# skips when it does not exist; hooks/end.json, the sentinel "vbw-guard-end".
# So after the hook input, the next input is the record (a VBW project), the
# sentinel (not one), or a parse error (a corrupt record: still a VBW project).
#
# Membership tests are anchored regexes, not array literals: they compile to far
# fewer jq instructions, and compiling is most of a guard's cost.

# {hook, project, record, lease}: lease is the active run lease when this call
# comes from a subagent (the hook input names an agent_type) during a run of
# at most 24 hours (docs/workflows.md), else null. The main session is never
# held to a lease.
def guard_context:
  input as $hook | (try input catch {}) as $rec
  | ($rec | if type == "object" then . else {} end) as $record
  | {hook: $hook, project: ($rec != "vbw-guard-end"), record: $record,
     lease: (if ($hook.agent_type // "") != "" and ($record.lease | type) == "object"
                and (try (now - ($record.lease.started_at | fromdateiso8601) < 86400) catch false)
             then $record.lease else null end)};

def basename: split("/") | last // "";
def secret_path: basename
  | (test("^\\.env(\\..+)?$") and (test("^\\.env\\.(example|sample|template|dist|defaults)$") | not))
    or test("\\.(pem|key|p12|pfx|kdbx|keystore|jks)$|^id_(rsa|dsa|ecdsa|ed25519)$|^\\.(netrc|pgpass|npmrc|pypirc)$|^credentials(\\.json)?$");
def record_path: test("(^|/)\\.vbw/record\\.json$");
def consent_path: test("(^|/)vbw/consent\\.json$");

# PATH (relative to $cwd unless absolute) as a project-relative path, or null
# when it lies outside $root. "." and ".." segments are resolved.
def project_path($cwd; $root):
  (if startswith("/") then . else "\($cwd)/\(.)" end)
  | reduce (split("/")[] | select(. != "" and . != ".")) as $s ([];
      if $s == ".." then .[:-1] else . + [$s] end)
  | "/" + join("/")
  | if startswith(($root | rtrimstr("/")) + "/") then .[($root | rtrimstr("/") | length) + 1:] else null end;

# Why a subagent may not write PATH (project-relative) under LEASE, or empty.
def lease_write_denial($lease; $record):
  if . == null then empty
  elif $lease.files == [] then
    "\(.) cannot be written during a \($lease.kind) run: its agents only read"
  elif $lease.files != null and (. as $p | any($lease.files[]; . == $p) | not) then
    "\(.) is outside this run's files (\($lease.files | join(", "))): agents write only their plan's files"
  elif ($lease.kind | test("^(build|fix)$")) and (. as $p | any($record.checks[]?.files[]?; . == $p)) then
    "\(.) is a protected check file: the contract is fixed while building"
  else empty end;

def secret_reason: "\(basename) may hold secrets; VBW never reads or writes secret files";
def record_reason: ".vbw/record.json is written only by vbw (vbw help lists the commands)";
def consent_reason: "the consent file is written only by /vbw:approve";

# A reason string becomes the hook's deny decision.
def deny: {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("VBW guard: " + .)}};
