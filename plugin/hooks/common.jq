# Shared by the PreToolUse guards (docs/guards.md). Each guard runs as jq
# itself (build plan K20), with --arg root PROJECT, --arg dir SESSION_DIR and
# --rawfile glance F. SESSION_DIR is the session's folder ($CLAUDE_PROJECT_DIR);
# PROJECT is the project of a session started there, found as the kernel finds
# it (vbw_git_root): the nearest folder at or above SESSION_DIR that holds .git,
# SESSION_DIR itself when none does. Its inputs, in order: the hook input (stdin);
# PROJECT/.vbw/record.json, which jq skips when it does not exist;
# hooks/end.json, the sentinel "vbw-guard-end". So after the hook input, the
# next input is the record (a VBW project), the sentinel (not one), or a parse
# error (a corrupt record: still a VBW project).
#
# The guard has two sources for the schema, lease and protected check files
# (R150). The glance (.vbw/runtime/glance.json, decision D238) is a small file
# the kernel rewrites with every record write; the hook command passes it as
# $glance only when the record exists and the glance is a readable regular file
# strictly newer than the record, else $glance is empty. When $glance parses to
# an object holding schema, lease and protected, the guard uses it and never
# reads the record input. Otherwise it reads the record with one plain input,
# whatever its size: the glance was missing, stale, forged older or damaged.
# Both give the same answers. A record that cannot be parsed counts as a VBW
# project with no lease, except during a run: the hook command passes
# --arg open 1 while .vbw/runtime/run-open exists, and then the guard fails
# (R165), which the hook command turns into a block.
#
# The one name a reason gives for the holder of the run is the glance's top-level
# holder field (R192, D442): the name vbw run start stored, never read from
# anywhere else on this hot path. The record carries no name, so a call that read
# the record has holder null and the reason names the first 8 characters of the id.
#
# This file includes no other module: each guard includes lib/holder.jq itself and
# passes the holder's display name in. jq 1.8.2 aborts, on its first call, a program
# that reaches a module only through another module (jqlang/jq#3636), and that would
# block every call of a run (R165).
#
# Membership tests are anchored regexes, not array literals: they compile to far
# fewer jq instructions, and compiling is most of a guard's cost.

# The glance as an object when it holds schema, lease and protected, else null.
def glance_object:
  (try fromjson catch null) | select(type == "object" and has("schema") and has("lease") and has("protected"));

# {project, record, holder}: from the current glance (holder: its top-level
# holder), else from the record input (holder: null).
def read_record:
  ([$glance | glance_object][0]) as $gl
  | if $gl != null then {project: true, record: $gl, holder: ($gl.holder // null)}
    else (try input catch "vbw-guard-corrupt") as $rec
      | if $rec == "vbw-guard-corrupt" and ($ARGS.named.open // "") == "1" then error("the record cannot be parsed during a run") else . end
      | {project: ($rec != "vbw-guard-end"), record: (if $rec | type == "object" then $rec else {} end), holder: null}
    end;

# {hook, project, record, holder, loop_on, lease, foreign}: loop_on is true while the
# record (or glance) holds a loop that has not ended; foreign is the open run lease (under
# 24 hours, with an owning session) when the hook input comes from a different
# session, main conversation or agent alike (D11), else null. lease is the active run lease when this call
# comes from a subagent (the hook input names an agent_type) during a run of
# at most 24 hours (docs/workflows.md), else null. The main session is never
# held to a lease.
def guard_context(writes):
  input as $hook
  | read_record as $r
  | ($r.record) as $record
  | (($record.lease | select(type == "object" and (try (now - (.started_at | fromdateiso8601) < 86400) catch false))) // null) as $live
  | {hook: $hook, project: $r.project, record: $record, holder: $r.holder,
     loop_on: ($record.loop | type == "object" and (.ended // null) == null),
     lease: (if ($hook.agent_type // "") != "" then $live else null end),
     foreign: (($live | select((.session // "") != "" and ($hook.session_id // .session) != .session) | . + {holder: $r.holder}) // null)};

def basename: split("/") | last // "";
def secret_path: basename
  | (test("^\\.env(\\..+)?$") and (test("^\\.env\\.(example|sample|template|dist|defaults)$") | not))
    or test("\\.(pem|key|p12|pfx|kdbx|keystore|jks)$|^id_(rsa|dsa|ecdsa|ed25519)$|^\\.(netrc|pgpass|npmrc|pypirc)$|^credentials(\\.json)?$");
def record_path: test("(^|/)\\.vbw/record\\.json$");
def glance_reason: ".vbw/runtime/glance.json is written only by vbw (vbw help lists the commands)\nNext: leave it as it is; vbw rewrites it with every change to the record";
def glance_path: test("(^|/)\\.vbw/runtime/glance\\.json$");
# The agents' scratch folder (project-relative), the one place a build or fix
# run writes besides its plan files (R177, D300): debugging scripts and logs,
# ignored by git and never read by a proof. The rest of .vbw/runtime/ is vbw's.
def scratch_path: test("^\\.vbw/runtime/scratch(/|$)");
def consent_path: test("(^|/)vbw/(consent|runs)\\.json$");

# PATH (relative to $cwd unless absolute) as a project-relative path, or null
# when it lies outside $root. "." and ".." segments are resolved.
def project_path($cwd; $root):
  (if startswith("/") then . else "\($cwd)/\(.)" end)
  | reduce (split("/")[] | select(. != "" and . != ".")) as $s ([];
      if $s == ".." then .[:-1] else . + [$s] end)
  | "/" + join("/")
  | if startswith(($root | rtrimstr("/")) + "/") then .[($root | rtrimstr("/") | length) + 1:] else null end;

# The folder a relative path in a tool call is read from: the session's working
# folder (the hook input's cwd), which may be a subfolder of the project.
def session_dir($g): $g.hook.cwd // $ARGS.named.dir // $root;

# A plan file entry covers PATH: the same path, or a directory entry (ending
# in /) with PATH under it.
def covers($p): . as $e | $e == $p or $e == $p + "/" or (($e | endswith("/")) and ($p | startswith($e)));

# PATH (project-relative) is a test file, by place or by name: the one
# definition of what a planning run may write besides .vbw/ (R75).
def test_path: test("(^|/)(tests?|spec|__tests__)/|(^|/)t/.*\\.t$") or (basename | test("[._](test|spec)\\.|^test_.*\\.py$"));

# Why a subagent may not write PATH (project-relative) under LEASE, or empty.
def lease_write_denial($lease; $record):
  if . == null then empty
  elif glance_path then glance_reason
  elif $lease.files == [] then
    "\(.) cannot be written during a \($lease.kind) run: its agents only read\nNext: leave \(.) as it is; report the change you need in your result for the session that started the run"
  elif scratch_path then empty
  elif $lease.kind == "plan" and test_path then empty
  # lease.editable of a build run: strengthen_files (lib/record.sh), written by vbw mutate at a survivor
  elif $lease.kind == "build" and (. as $p | any($lease.editable[]?; . == $p)) then empty
  elif $lease.kind == "fix" and (. as $p | any($lease.editable[]?; . == $p)) then empty
  elif $lease.kind == "fix" and ((($lease.editable // []) | length) > 0 or $lease.new_tests == true) and (. as $p | any($record.protected[]?; . == $p)) then
    "\(.) is a protected check file of another requirement: the fix may edit only the check files of its own requirement (\(($lease.editable // []) | if length > 0 then join(", ") else "none is exclusive to it" end))\n"
    + (if $lease.new_tests == true then "Next: leave \(.) as it is; put the regression test in a new test file and register it with vbw fix check"
       else "Next: leave \(.) as it is; fix the code through the plan, and edit only the files named above" end)
  # A folder a shell command names whole (rm -r, a copy into it) holding one (#727), ahead of
  # the test files a fix may add, which may sit under such a folder.
  elif ($lease.kind | test("^(build|fix)$")) and (. as $p | any($record.protected[]?; startswith($p + "/"))) then
    "\(.) holds a protected check file (\(. as $p | [$record.protected[] | select(startswith($p + "/"))] | join(", "))): the contract is fixed while building\nNext: leave the protected check files as they are; name only the files you write"
  elif $lease.new_tests == true and test_path then empty
  elif $lease.kind == "plan" and $lease.files != null and (. as $p | any($lease.files[]; covers($p)) | not) then
    "\(.) cannot be written while planning: planning writes the project's test files and .vbw/; product code is the build's\nNext: leave \(.) as it is; put the check in a test file, or name \(.) in a plan's files so the build writes it"
  elif $lease.files != null and (. as $p | any($lease.files[]; covers($p)) | not) then
    "\(.) is outside this run's files (\($lease.files | join(", "))): agents write only their plan's files\nNext: leave \(.) as it is; report that the plan needs it, so the plan can be replanned with vbw apply"
  elif ($lease.kind | test("^(build|fix)$")) and ($record | has("protected") | not) then
    "\(.) cannot be written: this project's record was not saved by this VBW yet, so its protected check files are unknown; end the run and start it again, which saves the record\nNext: tell the session that started the run to end it (vbw run end) and start it again"
  elif ($lease.kind | test("^(build|fix)$")) and (. as $p | any($record.protected[]?; . == $p)) then
    "\(.) is a protected check file: the contract is fixed while building\nNext: leave \(.) as it is; if the check is wrong, report it so the user can change the contract"
  else empty end;

# Why a subagent may not write ORIGINAL (the path as given), which lies outside
# the project, during a run, naming where the run may write instead (R177).
# HOW says what the path is: outside the project, or one the guard cannot
# resolve (D304: a path starting with ~ or holding a shell expansion is read as
# text, never expanded, so it counts as outside).
def outside_denial($lease; $how):
  (if $lease.kind == "plan" then "the project's test files and .vbw/"
   elif $lease.files == null then "project files"
   else "its plan files (\($lease.files | join(", ")))" end) as $where
  | if $lease.files == [] then
      "\(.) \($how): during a \($lease.kind) run agents write nothing\nNext: leave it; report what you needed in your result, this run's agents write nothing"
    else
      "\(.) \($how): during a \($lease.kind) run agents write only inside the project, and there only \($where)\nNext: write inside the project folder instead, or put scratch work in .vbw/runtime/scratch/"
    end;
def outside_denial($lease): outside_denial($lease; "is outside the project");
# A path the guard cannot resolve: ~ (bash expands it, the guard does not) or a
# shell expansion ($VAR, $(...), backticks). Read as text it would pass for a
# project path; it counts as outside (D304).
def unresolved_path: test("^~|[$`]");

# Why a subagent may not write ORIGINAL (the path as given) under LEASE: a
# path outside the project is denied (R177), one inside goes to the lease rules.
def run_write_denial($g):
  . as $o | project_path(session_dir($g); $root) as $p
  | if $p == null then (if $o | test("^/dev/(null|stdout|stderr|tty)$") then empty else $o | outside_denial($g.lease) end) else $p | lease_write_denial($g.lease; $g.record) end;

# The same for a path in shell text (a redirect target, a git checkout path, a
# program's file): the shell would expand ~, $VAR, $(...) and backticks and the
# guard cannot, so such a path counts as outside (D304). A file tool's path is
# never expanded, so run_write_denial takes it as written (D311: app/routes/$id.tsx
# is a plan file like any other). A glob the shell expands is refused under build
# and fix when it may match a protected check file or a folder above one (#727;
# * may cross /, as zsh's ** does; a pattern the guard cannot read counts as
# matching). Brace expansion is not read: a check file changed that way stops
# the proof until the user approves it (docs/proof.md).
def protected_glob($record):
  ("^" + gsub("(?<c>[.+(){}^$|\\\\]|\\*\\*/|\\*|\\?|\\[!)"; {"**/": "(.*/)?", "*": ".*", "?": "[^/]", "[!": "[^"}[.c] // "\\" + .c) + "(/.*)?$") as $re
  | try [$record.protected[]? | select(test($re))] catch [$record.protected[]?];
def shell_write_denial($g):
  if unresolved_path then outside_denial($g.lease; "cannot be resolved by the guard (~ or a shell expansion), so it counts as outside the project")
  elif test("[*?\\[]") and (($g.lease.kind // "") | test("^(build|fix)$")) then
    ((project_path(session_dir($g); $root) // "") as $p | $p | protected_glob($g.record) | select(. != [])
     | "\($p) matches a protected check file (\(join(", "))): the contract is fixed while building\nNext: leave the protected check files as they are; name only the files you write")
    // run_write_denial($g)
  else run_write_denial($g) end;

# The name vbw run start stored for FOREIGN's run: the glance's holder when it is
# that run's, else null.
def foreign_stored_name($f):
  ($f.holder // null) | if type == "object" and .run == $f.run then .session_name else null end;

# Why another session may not write PATH (project-relative) while FOREIGN's run
# is open, or empty: it writes lease.files (null: any project file, []: none).
# NAME is the holder's display name: holder_name($f; foreign_stored_name($f); null).
def foreign_denial($f; $name):
  . as $p | select($p != null and (($f.files // [$p]) | any(.[]; covers($p))))
  | "\($p) is being written by run \($f.run) of another session (\($name)): wait for it; if the user says that session is closed, they run vbw run end --owner-closed\nNext: work on files outside \($f.files // ["the project"] | join(", ")) meanwhile, or wait until run \($f.run) ends";

def secret_reason: "\(basename) may hold secrets; VBW never reads or writes secret files\nNext: do not open \(basename); ask the user for the value you need, or use an example file such as .env.example";
def record_reason: ".vbw/record.json is written only by vbw (vbw help lists the commands)\nNext: run the vbw command that makes this change (vbw help lists them); read the record with vbw show or vbw status";
def consent_reason: "the consent file is written only by /vbw:approve, and the store of recorded runs (vbw/runs.json) only by vbw\nNext: the user approves through the approval menu (vbw next asks); leave the run store alone, vbw rewrites it by itself";

# A reason string becomes the hook's deny decision. The whole reason goes to
# Claude; beside it, systemMessage shows the user its first line (what was
# refused and why), so a refusal never reaches only the model. The Next: step is
# addressed to Claude and stays in the reason.
def deny: {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("VBW guard: " + .)},
  systemMessage: ("VBW guard blocked this call: " + (split("\n")[0]))};
