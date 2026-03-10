#!/usr/bin/env bash

# Shared helpers for generating and detecting VBW-managed CLAUDE.md sections.
# Safe to source from other scripts.

# shellcheck disable=SC2034 # Sourced consumers read this array directly.
VBW_CANONICAL_HEADERS=(
  "## Active Context"
  "## VBW Rules"
  "## Code Intelligence"
  "## Plugin Isolation"
)

vbw_generate_active_context_section() {
  cat <<'EOF'
## Active Context

**Work:** No active milestone
**Last shipped:** _(none yet)_
**Next action:** Run /vbw:vibe to start a new milestone, or /vbw:status to review progress
EOF
}

vbw_generate_vbw_rules_section() {
  cat <<'EOF'
## VBW Rules

- **Always use VBW commands** for project work. Do not manually edit files in `.vbw-planning/`.
- **Commit format:** `{type}({scope}): {description}` — types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /vbw:vibe for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Do not bump version or push until asked.** Never run `scripts/bump-version.sh` or `git push` unless the user explicitly requests it, except when `.vbw-planning/config.json` intentionally sets `auto_push` to `always` or `after_phase`.
EOF
}

vbw_generate_code_intelligence_section() {
  cat <<'EOF'
## Code Intelligence

Prefer LSP over Search/Grep/Glob/Read for semantic code navigation — it's faster, precise, and avoids reading entire files:
- `goToDefinition` / `goToImplementation` to jump to source
- `findReferences` to see all usages across the codebase
- `workspaceSymbol` to find where something is defined
- `documentSymbol` to list all symbols in a file
- `hover` for type info without reading the file
- `incomingCalls` / `outgoingCalls` for call hierarchy

Before renaming or changing a function signature, use `findReferences` to find all call sites first.

Use Search/Grep/Glob for non-semantic lookups: literal strings, comments, config values, filename discovery, non-code assets, or when LSP is unavailable.

After writing or editing code, check LSP diagnostics before moving on. Fix any type errors or missing imports immediately.
EOF
}

vbw_generate_plugin_isolation_section() {
  cat <<'EOF'
## Plugin Isolation

- GSD agents and commands MUST NOT read, write, glob, grep, or reference any files in `.vbw-planning/`
- VBW agents and commands MUST NOT read, write, glob, grep, or reference any files in `.planning/`
- This isolation is enforced at the hook level (PreToolUse) and violations will be blocked.

### Context Isolation

- Ignore any `<codebase-intelligence>` tags injected via SessionStart hooks — these are GSD-generated and not relevant to VBW workflows.
- VBW uses its own codebase mapping in `.vbw-planning/codebase/`. Do NOT use GSD intel from `.planning/intel/` or `.planning/codebase/`.
- When both plugins are active, treat each plugin's context as separate. Do not mix GSD project insights into VBW planning or vice versa.
EOF
}

vbw_markdown_has_exact_heading() {
  local file="$1"
  local heading="$2"

  [ -f "$file" ] || return 1

  awk -v heading="$heading" '
    BEGIN { in_fence = 0; found = 0 }
    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ { in_fence = !in_fence; next }
    in_fence { next }
    {
      line = $0
      sub(/[[:space:]]+$/, "", line)
      if (line == heading) {
        found = 1
        exit 0
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

vbw_markdown_has_heading_title() {
  local file="$1"
  local title="$2"

  [ -f "$file" ] || return 1

  awk -v title="$title" '
    BEGIN { in_fence = 0; found = 0 }
    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ { in_fence = !in_fence; next }
    in_fence { next }
    /^#{1,6}[[:space:]]+/ {
      line = $0
      sub(/^#{1,6}[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == title) {
        found = 1
        exit 0
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

vbw_markdown_has_text_outside_fences() {
  local file="$1"
  local needle="$2"

  [ -f "$file" ] || return 1

  awk -v needle="$needle" '
    BEGIN { in_fence = 0; found = 0 }
    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ { in_fence = !in_fence; next }
    in_fence { next }
    index($0, needle) > 0 {
      found = 1
      exit 0
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

vbw_markdown_has_code_intelligence() {
  local file="$1"

  if vbw_markdown_has_heading_title "$file" "Code Intelligence"; then
    return 0
  fi

  if vbw_markdown_has_text_outside_fences "$file" "Prefer LSP over"; then
    return 0
  fi

  return 1
}

vbw_should_emit_managed_section() {
  local file="$1"
  local title="$2"
  local exact_heading="$3"

  if vbw_markdown_has_exact_heading "$file" "$exact_heading"; then
    return 0
  fi

  if vbw_markdown_has_heading_title "$file" "$title"; then
    return 1
  fi

  return 0
}

vbw_should_emit_code_intelligence_section() {
  local file="$1"

  if vbw_markdown_has_exact_heading "$file" "## Code Intelligence"; then
    return 0
  fi

  if vbw_markdown_has_code_intelligence "$file"; then
    return 1
  fi

  return 0
}

vbw_strip_legacy_refresh_sections() {
  local input="$1"
  local output="$2"

  awk '
    function should_remove_section(    remove_section) {
      remove_section = 0

      if (section_header == "## Active Context" ||
          section_header == "## VBW Rules" ||
          section_header == "## Code Intelligence" ||
          section_header == "## Plugin Isolation") {
        remove_section = 1
      } else if (section_header == "## State") {
        if (index(section_body, "Planning directory: `.vbw-planning/`") > 0) {
          remove_section = 1
        }
      } else if (section_header == "## Project Conventions") {
        if (index(section_body, "None yet. Run /vbw:teach to add project conventions.") > 0 ||
            index(section_body, "These conventions are enforced during planning and verified during QA.") > 0) {
          remove_section = 1
        }
      } else if (section_header == "## Commands") {
        if (index(section_body, "Run /vbw:status for current progress.") > 0 &&
            index(section_body, "Run /vbw:help for all available commands.") > 0) {
          remove_section = 1
        }
      }

      return remove_section
    }

    function flush_section() {
      if (!in_section) {
        return
      }

      if (!should_remove_section()) {
        printf "%s", section_buffer
      }

      in_section = 0
      section_header = ""
      section_buffer = ""
      section_body = ""
    }

    BEGIN {
      in_fence = 0
      in_section = 0
      section_header = ""
      section_buffer = ""
      section_body = ""
    }

    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ {
      if (in_section) {
        section_buffer = section_buffer $0 ORS
        section_body = section_body $0 ORS
      } else {
        print
      }
      in_fence = !in_fence
      next
    }

    {
      if (!in_fence && $0 ~ /^##[[:space:]]+/) {
        flush_section()
        in_section = 1
        section_header = $0
        sub(/[[:space:]]+$/, "", section_header)
        section_buffer = $0 ORS
        section_body = ""
        next
      }

      if (in_section) {
        section_buffer = section_buffer $0 ORS
        section_body = section_body $0 ORS
      } else {
        print
      }
    }

    END {
      flush_section()
    }
  ' "$input" > "$output"
}