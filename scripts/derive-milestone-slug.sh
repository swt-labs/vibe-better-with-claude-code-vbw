#!/usr/bin/env bash
set -euo pipefail

# derive-milestone-slug.sh — Deterministic milestone slug from ROADMAP.md
#
# Usage: derive-milestone-slug.sh [PLANNING_DIR]
#
# Reads ROADMAP.md phase names and produces a kebab-case slug (max 60 chars).
# Also determines the next milestone number based on existing milestones.
#
# Output (stdout): The full slug with number prefix, e.g. "01-setup-api-layer"
# Exit codes: 0 on success, 1 on failure

PLANNING_DIR="${1:-.vbw-planning}"
ROADMAP="$PLANNING_DIR/ROADMAP.md"

if [[ ! -f "$ROADMAP" ]]; then
  echo "Error: ROADMAP.md not found at $ROADMAP" >&2
  exit 1
fi

# --- Normalize text to kebab-case slug ---
normalize_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9 -]//g' | \
    sed 's/  */ /g' | \
    tr ' ' '-' | \
    sed 's/--*/-/g' | \
    sed 's/^-//;s/-$//'
}

# --- Extract phase names from ROADMAP.md ---
# Looks for "## Phase N: Name" or "N. **Name**" or "- Phase N: Name" patterns
derive_slug() {
  local slug=""

  # Try 1: Extract from "## Phase N:" headers
  local phase_names
  phase_names=$(awk '
    /^## Phase [0-9]+:/ {
      sub(/^## Phase [0-9]+:[[:space:]]*/, "")
      # Strip trailing markdown/punctuation
      sub(/[[:space:]]*$/, "")
      if (length > 0) print
    }
  ' "$ROADMAP" | head -3)

  if [[ -n "$phase_names" ]]; then
    slug=$(echo "$phase_names" | tr '\n' ' ' | sed 's/ $//')
    slug=$(normalize_slug "$slug")
    # Truncate to 60 chars at word boundary
    if [[ ${#slug} -gt 60 ]]; then
      slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
    fi
    echo "$slug"
    return
  fi

  # Try 2: Extract from numbered list "N. **Name**" or "N. Name"
  phase_names=$(awk '
    /^[0-9]+\. / {
      sub(/^[0-9]+\.[[:space:]]+/, "")
      gsub(/\*\*/, "")
      sub(/ [—–-] .*/, "")
      sub(/[[:space:]]*$/, "")
      if (length > 0) print
    }
  ' "$ROADMAP" | head -3)

  if [[ -n "$phase_names" ]]; then
    slug=$(echo "$phase_names" | tr '\n' ' ' | sed 's/ $//')
    slug=$(normalize_slug "$slug")
    if [[ ${#slug} -gt 60 ]]; then
      slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
    fi
    echo "$slug"
    return
  fi

  # Try 3: Extract from bulleted list "- Phase N: Name"
  phase_names=$(awk '
    /^[-*] +(Phase [0-9]+: )?/ {
      sub(/^[-*] +(Phase [0-9]+: )?/, "")
      sub(/ [—–-] .*/, "")
      sub(/[[:space:]]*$/, "")
      if (length > 0) print
    }
  ' "$ROADMAP" | head -3)

  if [[ -n "$phase_names" ]]; then
    slug=$(echo "$phase_names" | tr '\n' ' ' | sed 's/ $//')
    slug=$(normalize_slug "$slug")
    if [[ ${#slug} -gt 60 ]]; then
      slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
    fi
    echo "$slug"
    return
  fi

  # Try 4: Use phase directory names
  if [[ -d "$PLANNING_DIR/phases" ]]; then
    local dir_names
    dir_names=$(ls -1 "$PLANNING_DIR/phases/" 2>/dev/null | sed 's/^[0-9]*-//' | head -3)
    if [[ -n "$dir_names" ]]; then
      slug=$(echo "$dir_names" | tr '\n' ' ' | sed 's/ $//')
      slug=$(normalize_slug "$slug")
      if [[ ${#slug} -gt 60 ]]; then
        slug=$(echo "$slug" | head -c 60 | sed 's/-[^-]*$//')
      fi
      echo "$slug"
      return
    fi
  fi

  # Fallback: timestamp
  echo "milestone-$(date +%Y%m%d)"
}

# --- Determine milestone number prefix ---
milestone_number() {
  local count=0
  if [[ -d "$PLANNING_DIR/milestones" ]]; then
    local d
    for d in "$PLANNING_DIR/milestones"/*/; do
      [[ -d "$d" ]] || continue
      count=$((count + 1))
    done
  fi
  printf "%02d" $((count + 1))
}

slug_name=$(derive_slug)
ms_num=$(milestone_number)

# Guard against empty slug
if [[ -z "$slug_name" ]]; then
  slug_name="milestone-$(date +%Y%m%d)"
fi

full_slug="${ms_num}-${slug_name}"

# Guard against collision
TARGET_DIR="$PLANNING_DIR/milestones/$full_slug"
if [[ -d "$TARGET_DIR" ]]; then
  suffix=1
  while [[ -d "${TARGET_DIR}-${suffix}" ]]; do
    suffix=$((suffix + 1))
    if [[ $suffix -gt 10 ]]; then
      echo "Error: cannot find unique slug (tried $full_slug through $full_slug-10)" >&2
      exit 1
    fi
  done
  full_slug="${full_slug}-${suffix}"
fi

echo "$full_slug"
