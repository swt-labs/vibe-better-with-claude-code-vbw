#!/usr/bin/env bash
set -u

# route-monorepo.sh <phase-dir>
# Detect monorepo structure and output relevant package paths for a phase.
# Scans PLAN.md Files: entries, maps file paths to package roots.
# Package roots detected by: package.json, Cargo.toml, go.mod, pyproject.toml
# Output: JSON array of relevant package paths (e.g., ["packages/core", "apps/web"])
# Fail-open: exit 0 always, outputs "[]" on error.

if [ $# -lt 1 ]; then
  echo "[]"
  exit 0
fi

PHASE_DIR="$1"

command -v jq &>/dev/null || { echo "[]"; exit 0; }
[ ! -d "$PHASE_DIR" ] && { echo "[]"; exit 0; }

# Check monorepo_routing flag — if disabled, skip
CONFIG_PATH=".vbw-planning/config.json"
if [ -f "$CONFIG_PATH" ]; then
  MONOREPO_ROUTING=$(jq -r 'if .monorepo_routing != null then .monorepo_routing elif .v3_monorepo_routing != null then .v3_monorepo_routing else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
  if [ "$MONOREPO_ROUTING" != "true" ]; then
    echo "[]"
    exit 0
  fi
fi

# Detect package root markers in the repo
PACKAGE_MARKERS="package.json Cargo.toml go.mod pyproject.toml"
PACKAGE_ROOTS=()

for marker in $PACKAGE_MARKERS; do
  while IFS= read -r marker_path; do
    [ -z "$marker_path" ] && continue
    root=$(dirname "$marker_path")
    # Skip root-level markers (not monorepo packages)
    [ "$root" = "." ] && continue
    PACKAGE_ROOTS+=("$root")
  done < <(find . -maxdepth 4 -name "$marker" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.vbw-planning/*' 2>/dev/null)
done

# If no sub-packages found, not a monorepo
if [ ${#PACKAGE_ROOTS[@]} -eq 0 ]; then
  echo "[]"
  exit 0
fi

# Extract file paths from PLAN.md task sections (flat root + wave subdirs)
PLAN_FILES=()
for plan_file in "$PHASE_DIR"/*-PLAN.md "$PHASE_DIR"/P*-*-wave/*-PLAN.md; do
  [ ! -f "$plan_file" ] && continue
  # Extract Files: lines from task blocks
  while IFS= read -r line; do
    # Parse files from markdown: - **Files:** `path1`, `path2` (new)
    cleaned=$(echo "$line" | sed 's/.*\*\*Files:\*\* *//' | sed 's/`//g' | sed 's/ *(new)//g')
    IFS=',' read -ra parts <<< "$cleaned"
    for part in "${parts[@]}"; do
      trimmed=$(echo "$part" | sed 's/^ *//;s/ *$//')
      [ -n "$trimmed" ] && PLAN_FILES+=("$trimmed")
    done
  done < <(grep -i '^\- \*\*Files:\*\*' "$plan_file" 2>/dev/null)
done

# Match plan files to package roots
RELEVANT_ROOTS=()
for plan_file in "${PLAN_FILES[@]+"${PLAN_FILES[@]}"}"; do
  [ -z "$plan_file" ] && continue
  for root in "${PACKAGE_ROOTS[@]}"; do
    # Strip leading ./ from root for comparison
    clean_root="${root#./}"
    case "$plan_file" in
      "$clean_root"/*)
        # Check if already in relevant roots
        FOUND=false
        for existing in "${RELEVANT_ROOTS[@]+"${RELEVANT_ROOTS[@]}"}"; do
          [ "$existing" = "$clean_root" ] && FOUND=true && break
        done
        [ "$FOUND" = false ] && RELEVANT_ROOTS+=("$clean_root")
        ;;
    esac
  done
done

# Output as JSON array
if [ ${#RELEVANT_ROOTS[@]} -eq 0 ]; then
  echo "[]"
else
  printf '%s\n' "${RELEVANT_ROOTS[@]}" | jq -R '.' | jq -s '.' 2>/dev/null || echo "[]"
fi

exit 0
