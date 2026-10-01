# Shared by the PreToolUse guards (docs/guards.md). Each guard runs as jq
# itself (build plan K20). Its inputs, in order: the hook input (stdin);
# $CLAUDE_PROJECT_DIR/.vbw/record.json, which jq skips when it does not exist;
# hooks/end.json, the sentinel "vbw-guard-end". So after the hook input, the next
# input is the record (a VBW project), the sentinel (not one), or a parse error
# (a corrupt record: still a VBW project).
#
# Membership tests are anchored regexes, not array literals: they compile to far
# fewer jq instructions, and compiling is most of a guard's cost.

def in_vbw_project: (try input catch {}) != "vbw-guard-end";

def basename: split("/") | last // "";
def secret_path: basename
  | (test("^\\.env(\\..+)?$") and (test("^\\.env\\.(example|sample|template|dist|defaults)$") | not))
    or test("\\.(pem|key|p12|pfx|kdbx|keystore|jks)$|^id_(rsa|dsa|ecdsa|ed25519)$|^\\.(netrc|pgpass|npmrc|pypirc)$|^credentials(\\.json)?$");
def record_path: test("(^|/)\\.vbw/record\\.json$");
def consent_path: test("(^|/)vbw/consent\\.json$");

def secret_reason: "\(basename) may hold secrets; VBW never reads or writes secret files";
def record_reason: ".vbw/record.json is written only by vbw (vbw help lists the commands)";
def consent_reason: "the consent file is written only by /vbw:approve";

# A reason string becomes the hook's deny decision.
def deny: {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("VBW guard: " + .)}};
