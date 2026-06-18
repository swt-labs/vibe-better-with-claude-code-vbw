#!/usr/bin/env bash
# Generate lightweight JSON index for archived GSD projects
# Called by: commands/init.md Step 0.5 (GSD import flow)
# Output: .vbw-planning/gsd-archive/INDEX.json
# Performance target: <5 seconds for typical projects

set -euo pipefail


# Check if archive exists
ARCHIVE_DIR="${VBW_PLANNING_DIR:-.vbw-planning}/gsd-archive"
if [[ ! -d "$ARCHIVE_DIR" ]]; then
  exit 0
fi

# Extract metadata
GSD_VERSION="unknown"
if [[ -f "$ARCHIVE_DIR/config.json" ]]; then
  GSD_VERSION=$(jq -r '.version // "unknown"' "$ARCHIVE_DIR/config.json" 2>/dev/null || echo "unknown")
fi

IMPORTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Scan phases
PHASES_JSON="[]"
PHASES_TOTAL=0
PHASES_COMPLETE=0

if [[ -d "$ARCHIVE_DIR/phases" ]]; then
  while IFS= read -r phase_dir; do
    [[ -z "$phase_dir" ]] && continue

    # Extract phase number and slug
    phase_name=$(basename "$phase_dir")
    phase_num=$(echo "$phase_name" | grep -oE '^[0-9]+' || echo "0")
    phase_slug=$(echo "$phase_name" | sed "s/^${phase_num}-//" || echo "unknown")

    # Count plans
    plan_count=$(find "$phase_dir" -maxdepth 1 -name "*-PLAN.md" 2>/dev/null | wc -l | tr -d ' ')

    # Determine status (complete if all plans have summaries)
    summary_count=$(find "$phase_dir" -maxdepth 1 -name "*-SUMMARY.md" 2>/dev/null | wc -l | tr -d ' ')
    status="in_progress"
    if [[ "$summary_count" -eq "$plan_count" ]] && [[ "$plan_count" -gt 0 ]]; then
      status="complete"
      ((PHASES_COMPLETE++)) || true
    fi

    # Build phase object
    PHASES_JSON=$(jq -n \
      --argjson phases "$PHASES_JSON" \
      --argjson num "$phase_num" \
      --arg slug "$phase_slug" \
      --argjson plans "$plan_count" \
      --arg status "$status" \
      '$phases + [{"num": $num, "slug": $slug, "plans": $plans, "status": $status}]')

    ((PHASES_TOTAL++)) || true
  done < <(find "$ARCHIVE_DIR/phases" -maxdepth 1 -type d -name "[0-9]*-*" 2>/dev/null | sort -V)
fi

# Extract milestones from ROADMAP.md
MILESTONES_JSON="[]"
if [[ -f "$ARCHIVE_DIR/ROADMAP.md" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+(.+)$ ]]; then
      milestone="${BASH_REMATCH[1]}"
      MILESTONES_JSON=$(jq -n --argjson ms "$MILESTONES_JSON" --arg m "$milestone" '$ms + [$m]')
    fi
  done < "$ARCHIVE_DIR/ROADMAP.md"
fi

# Build final JSON
jq -n \
  --arg imported_at "$IMPORTED_AT" \
  --arg gsd_version "$GSD_VERSION" \
  --argjson phases_total "$PHASES_TOTAL" \
  --argjson phases_complete "$PHASES_COMPLETE" \
  --argjson milestones "$MILESTONES_JSON" \
  --argjson phases "$PHASES_JSON" \
  '{
    "imported_at": $imported_at,
    "gsd_version": $gsd_version,
    "phases_total": $phases_total,
    "phases_complete": $phases_complete,
    "milestones": $milestones,
    "quick_paths": {
      "roadmap": "gsd-archive/ROADMAP.md",
      "project": "gsd-archive/PROJECT.md",
      "phases": "gsd-archive/phases/",
      "config": "gsd-archive/config.json"
    },
    "phases": $phases
  }' > "$ARCHIVE_DIR/INDEX.json"
