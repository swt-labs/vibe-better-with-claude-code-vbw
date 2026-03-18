#!/usr/bin/env bash
set -u

# contract-revision.sh <old-contract-path> <plan-path>
# Detects scope changes and creates contract revisions.
# Archives old contract as {phase}-{plan}.rev{NN}.json, generates new contract,
# logs contract_revision event via log-event.sh.
# v2_hard_contracts graduated — always enabled.

if [ $# -lt 2 ]; then
  echo "Usage: contract-revision.sh <old-contract-path> <plan-path>" >&2
  exit 0
fi

OLD_CONTRACT="$1"
PLAN_PATH="$2"

# shellcheck disable=SC2034 # PLANNING_DIR used by convention across VBW scripts
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# v2_hard_contracts graduated — always enabled

[ ! -f "$OLD_CONTRACT" ] && exit 0
[ ! -f "$PLAN_PATH" ] && exit 0

# Read old contract hash
OLD_HASH=$(jq -r '.contract_hash // ""' "$OLD_CONTRACT" 2>/dev/null) || OLD_HASH=""
[ -z "$OLD_HASH" ] && exit 0

# Generate new contract (to temp location)
TMP_CONTRACT=$(mktemp)
# Temporarily write new contract by running generate-contract
NEW_CONTRACT_PATH=$(bash "${SCRIPT_DIR}/generate-contract.sh" "$PLAN_PATH" 2>/dev/null) || { rm -f "$TMP_CONTRACT"; exit 0; }
[ -z "$NEW_CONTRACT_PATH" ] && { rm -f "$TMP_CONTRACT"; exit 0; }
[ ! -f "$NEW_CONTRACT_PATH" ] && { rm -f "$TMP_CONTRACT"; exit 0; }

# Read new hash
NEW_HASH=$(jq -r '.contract_hash // ""' "$NEW_CONTRACT_PATH" 2>/dev/null) || NEW_HASH=""

# Compare hashes
if [ "$OLD_HASH" = "$NEW_HASH" ]; then
  # No change
  rm -f "$TMP_CONTRACT"
  echo "no_change"
  exit 0
fi

# Scope changed — archive old contract
CONTRACT_DIR=$(dirname "$OLD_CONTRACT")
BASE=$(basename "$OLD_CONTRACT" .json)

# Find next revision number
REV=1
while [ -f "${CONTRACT_DIR}/${BASE}.rev${REV}.json" ]; do
  REV=$((REV + 1))
done

ARCHIVE_PATH="${CONTRACT_DIR}/${BASE}.rev${REV}.json"
cp "$OLD_CONTRACT" "$ARCHIVE_PATH" 2>/dev/null || true

# Extract phase and plan for event logging
PHASE=$(jq -r '.phase // 0' "$NEW_CONTRACT_PATH" 2>/dev/null) || PHASE=0
PLAN=$(jq -r '.plan // 0' "$NEW_CONTRACT_PATH" 2>/dev/null) || PLAN=0

# Log contract_revision event
if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
  bash "${SCRIPT_DIR}/log-event.sh" "contract_revision" "$PHASE" "$PLAN" \
    "old_hash=${OLD_HASH:0:16}" "new_hash=${NEW_HASH:0:16}" "revision=${REV}" 2>/dev/null || true
fi

# Log to metrics
if [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
  bash "${SCRIPT_DIR}/collect-metrics.sh" "contract_revision" "$PHASE" "$PLAN" \
    "old_hash=${OLD_HASH:0:16}" "new_hash=${NEW_HASH:0:16}" "revision=${REV}" 2>/dev/null || true
fi

rm -f "$TMP_CONTRACT"
echo "revised:${ARCHIVE_PATH}"
