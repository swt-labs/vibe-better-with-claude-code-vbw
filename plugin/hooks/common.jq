# Shared by the PreToolUse guards (docs/guards.md). Each guard runs as jq
# itself (build plan K20), with --arg root "$CLAUDE_PROJECT_DIR". Its inputs, in
# order: the hook input (stdin); $CLAUDE_PROJECT_DIR/.vbw/record.json, which jq
# skips when it does not exist; hooks/end.json, the sentinel "vbw-guard-end".
# So after the hook input, the next input is the record (a VBW project), the
# sentinel (not one), or a parse error (a corrupt record: still a VBW project).
#
# Membership tests are anchored regexes, not array literals: they compile to far
# fewer jq instructions, and compiling is most of a guard's cost.

# {hook, project, record, lease, foreign}: foreign is the open run lease (under
# 24 hours, with an owning session) when the hook input comes from a different
# session, main conversation or agent alike (D11), else null. lease is the active run lease when this call
# comes from a subagent (the hook input names an agent_type) during a run of
# at most 24 hours (docs/workflows.md), else null. The main session is never
# held to a lease.
def guard_context:
  input as $hook | (try input catch {}) as $rec
  | ($rec | if type == "object" then . else {} end) as $record
  | (($record.lease | select(type == "object" and (try (now - (.started_at | fromdateiso8601) < 86400) catch false))) // null) as $live
  | {hook: $hook, project: ($rec != "vbw-guard-end"), record: $record,
     lease: (if ($hook.agent_type // "") != "" then $live else null end),
     foreign: (($live | select((.session // "") != "" and ($hook.session_id // .session) != .session)) // null)};

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

# A plan file entry covers PATH: the same path, or a directory entry (ending
# in /) with PATH under it.
def covers($p): . as $e | $e == $p or (($e | endswith("/")) and ($p | startswith($e)));

# PATH (project-relative) is a test file, by place or by name: the one
# definition of what a planning run may write besides .vbw/ (R75).
def test_path: test("(^|/)(tests?|spec|__tests__)/") or (basename | test("\\.test\\.|_test\\.|^test_.*\\.py$"));

# Why a subagent may not write PATH (project-relative) under LEASE, or empty.
def lease_write_denial($lease; $record):
  if . == null then empty
  elif $lease.files == [] then
    "\(.) cannot be written during a \($lease.kind) run: its agents only read"
  elif $lease.kind == "plan" and test_path then empty
  elif $lease.files != null and (. as $p | any($lease.files[]; covers($p)) | not) then
    "\(.) is outside this run's files (\($lease.files | join(", "))): agents write only their plan's files"
  elif ($lease.kind | test("^(build|fix)$")) and (. as $p | any($record.checks[]?.files[]?; . == $p)) then
    "\(.) is a protected check file: the contract is fixed while building"
  else empty end;

# Why another session may not write PATH (project-relative) while FOREIGN's run
# is open, or empty: it writes lease.files (null: any project file, []: none).
def foreign_denial($f):
  . as $p | select($p != null and (($f.files // [$p]) | any(.[]; covers($p))))
  | "\($p) is being written by run \($f.run) of another session (\($f.session)): wait for it; if the user says that session is closed, they run vbw run end --owner-closed";

def secret_reason: "\(basename) may hold secrets; VBW never reads or writes secret files";
def record_reason: ".vbw/record.json is written only by vbw (vbw help lists the commands)";
def consent_reason: "the consent file is written only by /vbw:approve";

# A reason string becomes the hook's deny decision.
def deny: {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("VBW guard: " + .)}};
