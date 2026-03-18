#!/usr/bin/env bash
set -u

# research-warn.sh <phase_dir>
# Checks for RESEARCH.md in phase directory (v3_plan_research_persist graduated).
# Warns when effort != turbo and no RESEARCH.md found.
# Output: JSON {"check":"research_persist","result":"ok|warn","reason":"<reason>"}
# Exit: 0 always — advisory only, never blocks.

PHASE_DIR="${1:-}"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
CONFIG_PATH="${PLANNING_DIR}/config.json"

# Read effort config
EFFORT="balanced"
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  EFFORT=$(jq -r '.effort // "balanced"' "$CONFIG_PATH" 2>/dev/null || echo "balanced")
fi

if [ "$EFFORT" = "turbo" ]; then
  echo '{"check":"research_persist","result":"ok","reason":"turbo effort: research skipped"}'
  exit 0
fi

if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
  echo '{"check":"research_persist","result":"warn","reason":"phase directory not found"}'
  echo "[research-warn] WARNING: phase directory not found" >&2
  exit 0
fi

# Look for RESEARCH.md in phase dir (per-plan {NN}-{MM}-RESEARCH.md or legacy {NN}-RESEARCH.md)
RESEARCH_FILE=$(find "$PHASE_DIR" -maxdepth 1 -name "*-RESEARCH.md" -print -quit 2>/dev/null || true)

if [ -n "$RESEARCH_FILE" ] && [ -f "$RESEARCH_FILE" ]; then
  echo '{"check":"research_persist","result":"ok","reason":"RESEARCH.md found"}'
else
  echo '{"check":"research_persist","result":"warn","reason":"No RESEARCH.md found. Research recommended before planning."}'
  echo "[research-warn] WARNING: No RESEARCH.md found in ${PHASE_DIR}. Research recommended before planning." >&2
fi
