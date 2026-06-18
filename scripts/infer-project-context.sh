#!/usr/bin/env bash
set -euo pipefail


# infer-project-context.sh — Extract project context from codebase mapping files
#
# Usage: infer-project-context.sh CODEBASE_DIR [REPO_ROOT]
#   CODEBASE_DIR  Path to .vbw-planning/codebase/ mapping files
#   REPO_ROOT     Optional, defaults to current directory (for git repo name extraction)
#
# Output: Structured JSON to stdout with source attribution per field
# Exit: 0 on success, non-zero only on critical errors (missing CODEBASE_DIR)

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: infer-project-context.sh CODEBASE_DIR [REPO_ROOT]"
  echo ""
  echo "Extract project context from codebase mapping files."
  echo ""
  echo "  CODEBASE_DIR  Path to .vbw-planning/codebase/ mapping files"
  echo "  REPO_ROOT     Optional, defaults to current directory"
  echo ""
  echo "Outputs structured JSON to stdout with source attribution per field."
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "Error: CODEBASE_DIR is required" >&2
  echo "Usage: infer-project-context.sh CODEBASE_DIR [REPO_ROOT]" >&2
  exit 1
fi

CODEBASE_DIR="$1"
REPO_ROOT="${2:-$(pwd)}"

if [[ ! -d "$CODEBASE_DIR" ]]; then
  echo "Error: CODEBASE_DIR does not exist: $CODEBASE_DIR" >&2
  exit 1
fi

# --- Project name extraction (priority: git repo > plugin.json > directory) ---
NAME_VALUE=""
NAME_SOURCE=""

# Try git repo name
if [[ -z "$NAME_VALUE" ]]; then
  repo_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
  if [[ -n "$repo_url" ]]; then
    repo_name=$(echo "$repo_url" | sed 's/.*\///' | sed 's/\.git$//')
    if [[ -n "$repo_name" ]]; then
      NAME_VALUE="$repo_name"
      NAME_SOURCE="repo"
    fi
  fi
fi

# Try plugin.json name
if [[ -z "$NAME_VALUE" ]]; then
  plugin_json="$REPO_ROOT/.claude-plugin/plugin.json"
  if [[ -f "$plugin_json" ]]; then
    pname=$(jq -r '.name // empty' "$plugin_json" 2>/dev/null || true)
    if [[ -n "$pname" ]]; then
      NAME_VALUE="$pname"
      NAME_SOURCE="plugin.json"
    fi
  fi
fi

# Fallback to directory name
if [[ -z "$NAME_VALUE" ]]; then
  NAME_VALUE=$(basename "$REPO_ROOT")
  NAME_SOURCE="directory"
fi

# Build name JSON
NAME_JSON=$(jq -n --arg v "$NAME_VALUE" --arg s "$NAME_SOURCE" \
  '{value: $v, source: $s}')

# --- Tech stack extraction from STACK.md ---
STACK_FILE="$CODEBASE_DIR/STACK.md"
if [[ -f "$STACK_FILE" ]]; then
  # Extract languages from the Languages table and technologies from Key Technologies
  stack_items=()

  # Parse Languages table: lines matching "| Name | ..." pattern (skip header/separator)
  in_languages=false
  while IFS= read -r line; do
    if [[ "$line" == "## Languages" ]]; then
      in_languages=true
      continue
    fi
    if $in_languages; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ "$line" == "| "* && "$line" != "| Language"* && "$line" != "|--"* && "$line" != "|-"* ]]; then
        lang=$(echo "$line" | sed 's/^| *//' | sed 's/ *|.*//')
        if [[ -n "$lang" ]]; then
          stack_items+=("$lang")
        fi
      fi
    fi
  done < "$STACK_FILE"

  # Parse Key Technologies section only (not Model Routing or other sections)
  in_key_tech=false
  while IFS= read -r line; do
    if [[ "$line" == "## Key Technologies" ]]; then
      in_key_tech=true
      continue
    fi
    if $in_key_tech; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ "$line" == "- "* ]]; then
        tech=$(echo "$line" | sed 's/^- \*\*//' | sed 's/\*\*.*//')
        if [[ -n "$tech" ]]; then
          stack_items+=("$tech")
        fi
      fi
    fi
  done < "$STACK_FILE"

  if [[ ${#stack_items[@]} -gt 0 ]]; then
    STACK_JSON=$(printf '%s\n' "${stack_items[@]}" | jq -R . | jq -s '{value: ., source: "STACK.md"}')
  else
    STACK_JSON='{"value": null, "source": null}'
  fi
else
  STACK_JSON='{"value": null, "source": null}'
fi

# --- Architecture extraction from ARCHITECTURE.md ---
ARCH_FILE="$CODEBASE_DIR/ARCHITECTURE.md"
if [[ -f "$ARCH_FILE" ]]; then
  # Extract the Overview section (first paragraph after ## Overview)
  arch_text=""
  in_overview=false
  while IFS= read -r line; do
    if [[ "$line" == "## Overview" ]]; then
      in_overview=true
      continue
    fi
    if $in_overview; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ -n "$line" ]]; then
        if [[ -n "$arch_text" ]]; then
          arch_text="$arch_text $line"
        else
          arch_text="$line"
        fi
      fi
    fi
  done < "$ARCH_FILE"

  if [[ -n "$arch_text" ]]; then
    ARCH_JSON=$(jq -n --arg v "$arch_text" '{value: $v, source: "ARCHITECTURE.md"}')
  else
    ARCH_JSON='{"value": null, "source": null}'
  fi
else
  ARCH_JSON='{"value": null, "source": null}'
fi

# --- Purpose extraction from CONCERNS.md ---
CONCERNS_FILE="$CODEBASE_DIR/CONCERNS.md"
if [[ -f "$CONCERNS_FILE" ]]; then
  # Extract the document title (first # heading) and first concern as domain indicator
  purpose_text=""
  while IFS= read -r line; do
    if [[ "$line" == "# "* ]]; then
      purpose_text=$(echo "$line" | sed 's/^# //')
      break
    fi
  done < "$CONCERNS_FILE"

  # Also extract concern headings as domain signals
  concerns=()
  while IFS= read -r line; do
    concern=$(echo "$line" | sed 's/^## //')
    concerns+=("$concern")
  done < <(grep -E '^## ' "$CONCERNS_FILE" || true)

  if [[ -n "$purpose_text" && ${#concerns[@]} -gt 0 ]]; then
    concern_list=$(printf '%s\n' "${concerns[@]}" | jq -R . | jq -s 'join(", ")')
    PURPOSE_JSON=$(jq -n --arg title "$purpose_text" --argjson concerns "$concern_list" \
      '{value: ($title + " — key concerns: " + $concerns), source: "CONCERNS.md"}')
  elif [[ -n "$purpose_text" ]]; then
    PURPOSE_JSON=$(jq -n --arg v "$purpose_text" '{value: $v, source: "CONCERNS.md"}')
  else
    PURPOSE_JSON='{"value": null, "source": null}'
  fi
else
  PURPOSE_JSON='{"value": null, "source": null}'
fi

# --- Features extraction from INDEX.md ---
INDEX_FILE="$CODEBASE_DIR/INDEX.md"
if [[ -f "$INDEX_FILE" ]]; then
  # Extract Cross-Cutting Themes section (bullet points after ## Cross-Cutting Themes)
  features=()
  in_themes=false
  while IFS= read -r line; do
    if [[ "$line" == "## Cross-Cutting Themes" ]]; then
      in_themes=true
      continue
    fi
    if $in_themes; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ "$line" == "- "* ]]; then
        # Extract the bold title from each bullet: "- **Title**: description"
        feature=$(echo "$line" | sed 's/^- \*\*//' | sed 's/\*\*:.*//')
        if [[ -n "$feature" ]]; then
          features+=("$feature")
        fi
      fi
    fi
  done < "$INDEX_FILE"

  if [[ ${#features[@]} -gt 0 ]]; then
    FEATURES_JSON=$(printf '%s\n' "${features[@]}" | jq -R . | jq -s '{value: ., source: "INDEX.md"}')
  else
    FEATURES_JSON='{"value": null, "source": null}'
  fi
else
  FEATURES_JSON='{"value": null, "source": null}'
fi

# --- Combine all fields into final JSON output ---
jq -n \
  --argjson name "$NAME_JSON" \
  --argjson tech_stack "$STACK_JSON" \
  --argjson architecture "$ARCH_JSON" \
  --argjson purpose "$PURPOSE_JSON" \
  --argjson features "$FEATURES_JSON" \
  '{
    name: $name,
    tech_stack: $tech_stack,
    architecture: $architecture,
    purpose: $purpose,
    features: $features
  }'

exit 0
