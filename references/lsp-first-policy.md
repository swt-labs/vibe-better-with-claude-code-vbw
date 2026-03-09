# LSP-First Code Navigation Policy

Repo-wide rule for all LSP-capable agents (Scout, Architect, Lead, Dev, QA, Debugger, Docs).

## When to use LSP

Use LSP **first** for any semantic code navigation:
- `goToDefinition` / `goToImplementation` — jump to source
- `findReferences` — all usages across the codebase
- `workspaceSymbol` — find where something is defined
- `documentSymbol` — list all symbols in a file
- `hover` — type info without reading the file
- `incomingCalls` / `outgoingCalls` — call hierarchy
- `diagnostics` — type errors, missing imports

These cover: tracing call sites, navigating type hierarchies, following data flow, verifying wiring, cross-file dependencies, and targeted validation of known symbols.

## When LSP does NOT apply

Use Search/Grep/Glob (not LSP) for:
- **Literal strings:** comments, log messages, config values, hardcoded paths
- **Filename discovery:** finding files by name or glob pattern
- **Non-code assets:** markdown, docs, images, config files (JSON/YAML/TOML)
- **Pattern matching:** regex across files, string occurrences
- **Raw text search:** REQ-IDs, TODO markers, section headings
- **Unavailable LSP:** when LSP errors or the project has no language server

## Fallback rule

If LSP is unavailable or returns an error on a semantic query, fall back **immediately** to Grep/Glob. Do not retry LSP — treat the failure as permanent for the session and switch tools.

## Agent-specific guidance

### Lead (research-present path)
When RESEARCH.md exists, the Lead must not do broad exploratory scanning. But **targeted validation** of specific claims (confirming a symbol exists, checking a definition is current) should still prefer LSP over Search/Grep when the query is semantic. The constraint is "no broad scans," not "no LSP."

### Lead (no-research path)
Full LSP-first scanning: use LSP for type hierarchies, call sites, data flow. Grep/Glob for pattern matching, string searches, file discovery.

### Dev / QA / Debugger
LSP-first for all code navigation during implementation, verification, and investigation. Grep/Glob for literal-text matches and file discovery.

### Scout / Architect / Docs
LSP available for code understanding when needed. Grep/Glob remains primary for research, file discovery, and documentation tasks where semantic navigation is secondary.
