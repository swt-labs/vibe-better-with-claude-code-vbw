#!/usr/bin/env bash
set -u

# generate-contract.sh <plan-path>
# Generates a contract sidecar JSON from PLAN.md metadata.
# Output: .vbw-planning/.contracts/{phase}-{plan}.json
#
# Full contract (v2_hard_contracts, graduated): 11 fields + contract_hash
#   task_id, phase_id, plan_id, objective, allowed_paths, forbidden_paths,
#   depends_on, must_haves, verification_checks, max_token_budget, timeout_seconds,
#   contract_hash (SHA-256 of serialized contract excluding hash)
#
# Hard stop behavior delegated to validate-contract.sh.

if [ $# -lt 1 ]; then
  echo "Usage: generate-contract.sh <plan-path>" >&2
  exit 0
fi

PLAN_PATH="$1"
[ ! -f "$PLAN_PATH" ] && exit 0

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${CONFIG_PATH:-${PLANNING_DIR}/config.json}"

# Extract phase and plan from frontmatter
PHASE=$(awk '/^---$/{n++; next} n==1 && /^phase:/{print $2; exit}' "$PLAN_PATH" 2>/dev/null) || exit 0
PLAN=$(awk '/^---$/{n++; next} n==1 && /^plan:/{print $2; exit}' "$PLAN_PATH" 2>/dev/null) || exit 0
[ -z "$PHASE" ] || [ -z "$PLAN" ] && exit 0

# Extract title (objective) from frontmatter
TITLE=$(awk '/^---$/{n++; next} n==1 && /^title:/{sub(/^title: */, ""); print; exit}' "$PLAN_PATH" 2>/dev/null) || TITLE=""

# Extract must_haves from frontmatter
MUST_HAVES=$(awk '
  BEGIN { in_front=0; in_mh=0 }
  /^---$/ { if (in_front==0) { in_front=1; next } else { exit } }
  in_front && /^must_haves:/ { in_mh=1; next }
  in_front && in_mh && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    gsub(/^"/, ""); gsub(/"$/, "")
    print
    next
  }
  in_front && in_mh && /^[^[:space:]]/ { exit }
' "$PLAN_PATH" 2>/dev/null) || true

# Extract depends_on from frontmatter
DEPENDS_ON=$(awk '
  BEGIN { in_front=0; in_dep=0 }
  /^---$/ { if (in_front==0) { in_front=1; next } else { exit } }
  in_front && /^depends_on:/ {
    # Check inline array format: depends_on: [1, 2]
    if (match($0, /\[.*\]/)) {
      sub(/^depends_on: *\[/, ""); sub(/\].*$/, "")
      gsub(/ /, ""); gsub(/,/, "\n")
      print
      exit
    }
    in_dep=1; next
  }
  in_front && in_dep && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    print
    next
  }
  in_front && in_dep && /^[^[:space:]]/ { exit }
' "$PLAN_PATH" 2>/dev/null) || true

# Extract verification_checks from frontmatter (if present)
VERIFICATION_CHECKS=$(awk '
  BEGIN { in_front=0; in_vc=0 }
  /^---$/ { if (in_front==0) { in_front=1; next } else { exit } }
  in_front && /^verification_checks:/ { in_vc=1; next }
  in_front && in_vc && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    gsub(/^"/, ""); gsub(/"$/, "")
    print
    next
  }
  in_front && in_vc && /^[^[:space:]]/ { exit }
' "$PLAN_PATH" 2>/dev/null) || true

# Extract forbidden_paths from frontmatter (if present)
FORBIDDEN_PATHS=$(awk '
  BEGIN { in_front=0; in_fp=0 }
  /^---$/ { if (in_front==0) { in_front=1; next } else { exit } }
  in_front && /^forbidden_paths:/ { in_fp=1; next }
  in_front && in_fp && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    gsub(/^"/, ""); gsub(/"$/, "")
    print
    next
  }
  in_front && in_fp && /^[^[:space:]]/ { exit }
' "$PLAN_PATH" 2>/dev/null) || true

# Extract file paths from **Files:** lines in task descriptions
ALLOWED_PATHS=$(grep -oE '\*\*Files:\*\* .+' "$PLAN_PATH" 2>/dev/null | \
  sed 's/\*\*Files:\*\* //' | \
  tr ',' '\n' | \
  sed 's/^ *//;s/ *$//;s/ *(new)//;s/ *(if exists)//' | \
  grep -v '^$' | \
  sed 's/^`//;s/`$//' | \
  sort -u) || true

# Count tasks from ### Task N: headings
TASK_COUNT=$(grep -c '^### Task [0-9]' "$PLAN_PATH" 2>/dev/null) || TASK_COUNT=0

# Extract task IDs: {phase}-{plan}-T{NN}
TASK_IDS=""
for i in $(seq 1 "$TASK_COUNT"); do
  if [ -n "$TASK_IDS" ]; then
    TASK_IDS="${TASK_IDS}
${PHASE}-${PLAN}-T${i}"
  else
    TASK_IDS="${PHASE}-${PLAN}-T${i}"
  fi
done

# Build JSON arrays
MH_JSON="[]"
if [ -n "$MUST_HAVES" ]; then
  MH_JSON=$(echo "$MUST_HAVES" | jq -R '.' | jq -s '.' 2>/dev/null) || MH_JSON="[]"
fi

AP_JSON="[]"
if [ -n "$ALLOWED_PATHS" ]; then
  AP_JSON=$(echo "$ALLOWED_PATHS" | jq -R '.' | jq -s '.' 2>/dev/null) || AP_JSON="[]"
fi

# Write contract
CONTRACT_DIR="${PLANNING_DIR}/.contracts"
mkdir -p "$CONTRACT_DIR" 2>/dev/null || exit 0
CONTRACT_FILE="${CONTRACT_DIR}/${PHASE}-${PLAN}.json"

# Full contract: all 11 fields + contract_hash
  FP_JSON="[]"
  if [ -n "$FORBIDDEN_PATHS" ]; then
    FP_JSON=$(echo "$FORBIDDEN_PATHS" | jq -R '.' | jq -s '.' 2>/dev/null) || FP_JSON="[]"
  fi

  DEP_JSON="[]"
  if [ -n "$DEPENDS_ON" ]; then
    DEP_JSON=$(echo "$DEPENDS_ON" | jq -R 'tonumber' | jq -s '.' 2>/dev/null) || DEP_JSON="[]"
  fi

  VC_JSON="[]"
  if [ -n "$VERIFICATION_CHECKS" ]; then
    VC_JSON=$(echo "$VERIFICATION_CHECKS" | jq -R '.' | jq -s '.' 2>/dev/null) || VC_JSON="[]"
  fi

  TID_JSON="[]"
  if [ -n "$TASK_IDS" ]; then
    TID_JSON=$(echo "$TASK_IDS" | jq -R '.' | jq -s '.' 2>/dev/null) || TID_JSON="[]"
  fi

  # Token budget from config or default
  TOKEN_BUDGET=$(jq -r '.max_token_budget // 50000' "$CONFIG_PATH" 2>/dev/null || echo 50000)
  TIMEOUT=$(jq -r '.task_timeout_seconds // 600' "$CONFIG_PATH" 2>/dev/null || echo 600)

  # Build contract without hash first
  CONTRACT_BODY=$(jq -n \
    --arg phase_id "phase-${PHASE}" \
    --arg plan_id "phase-${PHASE}-plan-${PLAN}" \
    --argjson phase "$PHASE" \
    --argjson plan "$PLAN" \
    --arg objective "$TITLE" \
    --argjson task_ids "$TID_JSON" \
    --argjson task_count "$TASK_COUNT" \
    --argjson allowed_paths "$AP_JSON" \
    --argjson forbidden_paths "$FP_JSON" \
    --argjson depends_on "$DEP_JSON" \
    --argjson must_haves "$MH_JSON" \
    --argjson verification_checks "$VC_JSON" \
    --argjson max_token_budget "$TOKEN_BUDGET" \
    --argjson timeout_seconds "$TIMEOUT" \
    '{
      phase_id: $phase_id,
      plan_id: $plan_id,
      phase: $phase,
      plan: $plan,
      objective: $objective,
      task_ids: $task_ids,
      task_count: $task_count,
      allowed_paths: $allowed_paths,
      forbidden_paths: $forbidden_paths,
      depends_on: $depends_on,
      must_haves: $must_haves,
      verification_checks: $verification_checks,
      max_token_budget: $max_token_budget,
      timeout_seconds: $timeout_seconds
    }' 2>/dev/null) || exit 0

  # Compute SHA-256 hash of the contract body
  CONTRACT_HASH=$(echo "$CONTRACT_BODY" | shasum -a 256 | cut -d' ' -f1) || CONTRACT_HASH=""

  # Write final contract with hash
  echo "$CONTRACT_BODY" | jq --arg hash "$CONTRACT_HASH" '. + {contract_hash: $hash}' > "$CONTRACT_FILE" 2>/dev/null || exit 0

echo "$CONTRACT_FILE"
