# MuninnDB Reference

## Configuration

All MuninnDB settings are in `.vbw-planning/config.json`. The `muninndb_vault` field is user-facing; the defaults below are hardcoded in agent instructions and scripts.

| Parameter | Default | Where used | Rationale |
|-----------|---------|------------|-----------|
| `muninndb_vault` | `""` (set by `/vbw:init`) | All agents, all scripts | Project-scoped vault name |
| MCP port | `8750` | session-start.sh, muninn-setup.sh, doctor.md, init.md, status.md | MuninnDB MCP server |
| REST port | `8475` | muninn-setup.sh, init.md, doctor.md, status.md | MuninnDB REST API |
| Recall limit (planning) | `10` | vbw-dev, vbw-lead, vbw-architect | Planning agents need broader recall for cross-cutting decisions |
| Recall limit (task) | `5` | vbw-scout, vbw-debugger, vbw-docs | Task agents need focused recall scoped to their work |
| Score threshold (recall) | `0.5` | All 6 agents with `muninn_activate` | Filter out weak matches — below 0.5 is noise |
| Score threshold (consolidation) | `0.3` | vibe.md (ship mode), execute-protocol.md (phase end) | Consolidation casts wider net to merge related engrams |
| Consolidation limit | `50` | vibe.md (ship mode) | Cap engrams collected for consolidation |
| Health check timeout | `2s` | session-start.sh, status.md | Quick check, fail-open |
| Health check timeout | `3s` | muninn-setup.sh, doctor.md | Diagnostic check, more patient |
| Health check timeout | `5s` | muninn-setup.sh (setup), init.md | Setup check, most patient |

## Engram Types

Canonical type values for `muninn_remember(... type: X)` calls across VBW agents.

## Types

| Type | Semantics | Used by |
|------|-----------|---------|
| `Issue` | Bug, defect, or problem with non-obvious root cause | Dev (after fixing bugs), Debugger (after diagnosing), QA (contradictions, pre-existing failures) |
| `Observation` | Pattern, insight, or finding discovered during work | Dev (patterns during implementation), Scout (research findings), QA (useful verification patterns) |
| `Decision` | Deliberate choice between alternatives — structure, naming, style | Docs (documentation decisions), Lead (via `muninn_decide`), Architect (via `muninn_decide`) |
| `Task` | Requirement with acceptance criteria, tracked for traceability | Architect (requirements from REQUIREMENTS.md) |

## Notes

- **`Decision` vs `muninn_decide`**: Lead and Architect use `muninn_decide(vault, concept, rationale, alternatives[])` which is a dedicated MuninnDB call for recording decisions with alternatives. Docs uses `muninn_remember(... type: Decision)` for simpler doc-level choices. Both produce engrams — `muninn_decide` additionally records rejected alternatives.
- **Tags**: Always include `phase:{N}` to enable phase-scoped retrieval. Role-specific tags: `[debug]` for Debugger, `[qa]` for QA, `[research, domain:{topic}]` for Scout.
- **Enum status**: These types are conventions enforced by agent instructions, not a closed enum on the MuninnDB side. MuninnDB accepts any string as `type`.
