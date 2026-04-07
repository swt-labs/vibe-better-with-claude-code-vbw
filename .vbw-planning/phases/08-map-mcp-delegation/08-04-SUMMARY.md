---
phase: 8
plan: 4
title: "Semantic MCP Capability Detection via Tool Descriptions"
status: complete
completed: 2026-04-04
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 938d086
deviations:
  - "Plan specified 5 new categories but only 3 were implemented (OUTLINE, IMPACT_ANALYSIS, CLASS_HIERARCHY). DOC_SEARCH and DOC_STRUCTURE were absorbed into existing CODE_SEARCH and OUTLINE categories via extended suffixes, making dedicated categories redundant."
---

Extended Step 1.7 MCP capability detection with two-pass matching and broader tool coverage. Pass 1 (name suffix) extended with 20+ new suffixes covering jcodemunch and jdocmunch tool surfaces. Pass 2 (new) matches tool descriptions via semantic keyword sets for tools not caught by name. Added 3 new capability categories routed to mapping documents.

## What Was Built

- Pass 1 extended: 8 existing categories gained new suffixes (get_symbol_source, find_importers, get_blast_radius, get_changed_symbols, index_local, index_repo, search_sections, get_section, get_file_outline, get_document_outline, get_toc, get_broken_links, get_doc_coverage, find_dead_code, get_symbol_importance, get_layer_violations, get_section_context, index_folder, get_toc_tree, get_repo_outline)
- 3 new capability categories: CAPABILITY_OUTLINE (file/doc structure), CAPABILITY_IMPACT_ANALYSIS (blast radius, dead code, broken links), CAPABILITY_CLASS_HIERARCHY (inheritance chains)
- Pass 2: description-based semantic matching with 11 keyword sets, priority rules (name > description), first-match-wins for description pass
- Updated capability-to-document routing in solo, duo, and quad modes for new categories
- 10 new bats tests (tests 16-25) validating extended suffixes, new categories, Pass 2 presence, keyword sets, priority rules, routing, no-regression, and no hardcoded server names

## Files Modified

- `commands/map.md` — Extended Step 1.7 with Pass 1/Pass 2 structure, new suffixes, new categories, description keyword sets; updated routing in Step 3-solo, Step 3-duo, Step 3-quad
- `tests/map-mcp-delegation.bats` — Added 10 tests (16-25), all 25 pass

## Expected Coverage After

- jcodemunch: 12/13 tools detectable (up from 1; audit_agent_config excluded — operational)
- jdocmunch: 11/13 tools detectable (up from 0; list_repos, delete_index excluded — operational)
- Novel MCP servers: detected via Pass 2 description keywords without suffix updates
