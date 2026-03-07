# VBW Typed Communication Protocol

V2 inter-agent messages use strict JSON schemas. Every message includes a mandatory envelope. Machine-readable definitions at `config/schemas/message-schemas.json`.

## Envelope (mandatory on all messages)

```json
{
  "id": "uuid-v4",
  "type": "scout_findings|plan_contract|execution_update|blocker_report|qa_verdict|approval_request|approval_response|shutdown_request|shutdown_response",
  "phase": 1,
  "task": "1-1-T3",
  "author_role": "lead|dev|qa|scout|debugger|architect|docs",
  "timestamp": "2026-02-12T10:00:00Z",
  "schema_version": "2.0",
  "payload": {},
  "confidence": "high|medium|low"
}
```

## Role Authorization Matrix

| Message Type | Allowed Senders | Typical Receivers |
|---|---|---|
| scout_findings | scout | lead, architect |
| plan_contract | lead, architect | dev, qa, scout |
| execution_update | dev, docs | lead |
| blocker_report | dev, docs | lead |
| debugger_report | debugger | lead |
| qa_verdict | qa | lead |
| approval_request | dev, lead | lead, architect |
| approval_response | lead, architect | dev, lead |
| shutdown_request | lead (orchestrator) | dev, qa, scout, lead, debugger, docs |
| shutdown_response | dev, qa, scout, lead, debugger, docs | lead (orchestrator) |

Unauthorized sender -> message rejected (v2_typed_protocol=true) or logged (false).

## `scout_findings` (Scout -> Lead/Architect)

Research findings from a Scout investigating a specific domain.

```json
{
  "id": "abc-123",
  "type": "scout_findings",
  "phase": 1,
  "task": "1-1-T1",
  "author_role": "scout",
  "timestamp": "2026-02-12T10:00:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "domain": "tech-stack|architecture|quality|concerns",
    "documents": [
      {"name": "STACK.md", "content": "## Tech Stack\n..."}
    ],
    "cross_cutting": [
      {"target_domain": "architecture", "finding": "...", "relevance": "high|medium|low"}
    ],
    "confidence_rationale": "Brief justification"
  }
}
```

## `plan_contract` (Lead/Architect -> Dev/QA/Scout)

Issued plan contract defining task scope and constraints.

```json
{
  "id": "contract-456",
  "type": "plan_contract",
  "phase": 1,
  "task": "1-1-T1",
  "author_role": "lead",
  "timestamp": "2026-02-12T10:00:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "plan_id": "phase-1-plan-1",
    "phase_id": "phase-1",
    "objective": "Implement feature X",
    "tasks": ["1-1-T1", "1-1-T2"],
    "allowed_paths": ["src/feature.js", "tests/feature.test.js"],
    "must_haves": ["Feature passes tests", "No regressions"],
    "forbidden_paths": [".env", "secrets/"],
    "depends_on": [],
    "verification_checks": ["npm test"],
    "token_budget": 50000
  }
}
```

## `execution_update` (Dev/Docs -> Lead)

Task progress or completion update from Dev or Docs.

```json
{
  "id": "update-789",
  "type": "execution_update",
  "phase": 1,
  "task": "1-1-T3",
  "author_role": "dev",
  "timestamp": "2026-02-12T10:05:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "plan_id": "1-1",
    "task_id": "1-1-T3",
    "status": "complete|partial|failed",
    "commit": "abc1234",
    "files_modified": ["src/feature.js"],
    "concerns": ["Interface changed — downstream plans may need update"],
    "evidence": "All tests pass",
    "pre_existing_issues": [
      {"test": "testName", "file": "path/to/file", "error": "failure message"}
    ]
  }
}
```

## `blocker_report` (Dev/Docs -> Lead)

Escalation when agent is blocked and cannot proceed.

```json
{
  "id": "block-012",
  "type": "blocker_report",
  "phase": 1,
  "task": "1-2-T1",
  "author_role": "dev",
  "timestamp": "2026-02-12T10:10:00Z",
  "schema_version": "2.0",
  "confidence": "medium",
  "payload": {
    "plan_id": "1-2",
    "task_id": "1-2-T1",
    "blocker": "Dependency module from plan 1-1 not yet committed",
    "needs": "Plan 1-1 to complete first",
    "attempted": ["Checked git log for 1-1 commits — none found"],
    "severity": "blocking|degraded|informational",
    "pre_existing_issues": [
      {"test": "testName", "file": "path/to/file", "error": "failure message"}
    ]
  }
}
```
If no pre-existing issues were found, omit the field or pass an empty array.

## `debugger_report` (Debugger -> Lead)

Diagnostic investigation report from the Debugger agent. Used in Teammate Mode when the Debugger is assigned a single hypothesis to investigate. Distinct from `blocker_report` — the Debugger's payload uses diagnostic fields, not escalation fields.

```json
{
  "id": "debug-456",
  "type": "debugger_report",
  "phase": 1,
  "task": "debug-hyp-1",
  "author_role": "debugger",
  "timestamp": "2026-02-12T10:12:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "hypothesis": "Race condition in sync handler causes intermittent auth failure",
    "evidence_for": ["Thread dump shows concurrent access at auth.js:42", "Failure rate correlates with load"],
    "evidence_against": ["Single-threaded test passes consistently"],
    "confidence": "high",
    "recommended_fix": "Add mutex lock around credential refresh in auth.js:40-50",
    "pre_existing_issues": [
      {"test": "testName", "file": "path/to/file", "error": "failure message"}
    ]
  }
}
```
If no pre-existing issues were found, omit the field or pass an empty array.

## `qa_verdict` (QA -> Lead)

Structured verification results.

```json
{
  "id": "qa-345",
  "type": "qa_verdict",
  "phase": 1,
  "task": "1-1-T1",
  "author_role": "qa",
  "timestamp": "2026-02-12T10:15:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "tier": "quick|standard|deep",
    "result": "PASS|FAIL|PARTIAL",
    "checks": {"passed": 18, "failed": 2, "total": 20},
    "failures": [
      {"check": "Link integrity", "expected": "All resolve", "actual": "broken ref", "evidence": "line 42"}
    ],
    "checks_detail": [
      {"id": "MH-01", "category": "must_have", "description": "Feature exists", "status": "PASS", "evidence": "File found at src/feature.js"},
      {"id": "MH-02", "category": "must_have", "description": "Tests pass", "status": "FAIL", "evidence": "2 failures in test suite"},
      {"id": "ART-01", "category": "artifact", "description": "README.md", "status": "PASS", "exists": true, "contains": "## Setup section"},
      {"id": "KL-01", "category": "key_link", "description": "Config references module", "status": "WARN", "from": "config.js", "to": "module.js", "via": "import pattern"},
      {"id": "CC-01", "category": "convention", "description": "kebab-case naming", "status": "PASS", "file": "src/my-module.js", "detail": "follows pattern"},
      {"id": "RM-01", "category": "requirement", "description": "REQ-01 implemented", "status": "PASS", "plan_ref": "PLAN.md §3", "evidence": "function at line 42"}
    ],
    "body": "## Must-Have Checks\n...",
    "recommendations": ["Fix broken cross-reference before shipping"],
    "pre_existing_issues": [
      {"test": "testName", "file": "path/to/file", "error": "failure message"}
    ]
  }
}
```

### `checks_detail` Per-Category Fields

All items share: `id`, `category`, `description`, `status`, `evidence`. Category-specific optional fields enable richer VERIFICATION.md output:

| Category | Optional Fields | Fallback |
|---|---|---|
| `must_have` | _(none)_ | 5-col: Truth/Condition, Status, Evidence |
| `artifact` | `exists` (bool), `contains` (string) | 5-col when absent |
| `key_link` | `from`, `to`, `via` (strings) | 5-col when absent |
| `anti_pattern` | _(none)_ | 5-col: Pattern, Status, Evidence |
| `convention` | `file`, `detail` (strings) | 5-col when absent |
| `requirement` | `plan_ref` (string) | 5-col when absent |
| `skill_augmented` | _(none)_ | 5-col: Skill Check, Status, Evidence |

When category-specific fields are present, `write-verification.sh` emits a 6-column table. When absent, falls back to uniform 5-column format.

## `approval_request` (Dev/Lead -> Lead/Architect)

Request for approval on plan, scope change, or override.

```json
{
  "id": "approve-678",
  "type": "approval_request",
  "phase": 1,
  "task": "1-1-T1",
  "author_role": "dev",
  "timestamp": "2026-02-12T10:20:00Z",
  "schema_version": "2.0",
  "confidence": "medium",
  "payload": {
    "subject": "Scope expansion needed for Task 3",
    "request_type": "scope_change|plan_approval|gate_override",
    "evidence": "Task requires modifying auth module not in allowed_paths",
    "options": ["Expand contract", "Split into new task"],
    "deadline": "2026-02-12T12:00:00Z"
  }
}
```

## `approval_response` (Lead/Architect -> Dev/Lead)

Response to an approval request.

```json
{
  "id": "response-901",
  "type": "approval_response",
  "phase": 1,
  "task": "1-1-T1",
  "author_role": "lead",
  "timestamp": "2026-02-12T10:25:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "request_id": "approve-678",
    "approved": true,
    "reason": "Auth module access justified by cross-cutting dependency",
    "conditions": ["Must not change existing API surface"],
    "modifications": []
  }
}
```

## `shutdown_request` (Orchestrator -> All teammates)

Graceful termination signal sent by the orchestrator after phase/plan work is complete.

```json
{
  "id": "shut-001",
  "type": "shutdown_request",
  "phase": 1,
  "task": "",
  "author_role": "lead",
  "timestamp": "2026-02-12T10:30:00Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "reason": "phase_complete|plan_complete|user_abort",
    "team_name": "vbw-phase-01"
  }
}
```

## `shutdown_response` (Teammate -> Orchestrator)

Acknowledgment from a teammate that it will terminate.

```json
{
  "id": "shut-resp-001",
  "type": "shutdown_response",
  "phase": 1,
  "task": "",
  "author_role": "dev",
  "timestamp": "2026-02-12T10:30:05Z",
  "schema_version": "2.0",
  "confidence": "high",
  "payload": {
    "request_id": "shut-001",
    "approved": true,
    "final_status": "complete|idle|in_progress",
    "pending_work": ""
  }
}
```

On receiving `shutdown_request`: respond with `shutdown_response` (approved=true), finish any in-progress tool call, then STOP all further work. Do NOT start new tasks, fix additional issues, or take any action after responding. The orchestrator will call TeamDelete after collecting all responses.

> **Conditional refusal:** The schema allows `approved: false` with `pending_work` describing what remains. Currently all agents are instructed to always approve. The orchestrator retries up to 3 times on rejection before proceeding. If a future agent needs to delay shutdown (e.g., mid-write to disk), update its Shutdown Handling section to allow conditional refusal with `approved: false`.

## Backward Compatibility

Old-format messages (without full envelope) are accepted when `v2_typed_protocol=false`. The validate-message.sh script parses the `type` field to determine schema and validates accordingly.

**Note:** `shutdown_request` and `shutdown_response` were introduced in v2.0. When `v2_typed_protocol=false`, validate-message.sh short-circuits to valid (no schema check), so shutdown messages pass through without rejection. Agents running in V1 mode will not recognize these types and should treat unrecognized messages as plain markdown.

When receiving messages, agents should:
1. Try to parse as V2 typed message (full envelope)
2. Fall back to V1 format (simple type + payload, no envelope fields)
3. Fall back to plain markdown on parse failure
