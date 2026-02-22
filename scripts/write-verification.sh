#!/usr/bin/env bash
# write-verification.sh — Convert qa_verdict JSON to deterministic VERIFICATION.md
# Usage: echo '{"payload":{...}}' | write-verification.sh <output-path>
# Input: qa_verdict JSON on stdin (full envelope or just payload)
# Output: Writes VERIFICATION.md to $1
# Exit 1 on invalid JSON or missing required fields
set -euo pipefail

output_path="${1:-}"
if [[ -z "$output_path" ]]; then
  echo "Usage: write-verification.sh <output-path>" >&2
  exit 1
fi

# Check jq availability
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not found in PATH" >&2
  exit 1
fi

# Read stdin
json=$(cat)

# Validate JSON
if ! echo "$json" | jq empty 2>/dev/null; then
  echo "Error: invalid JSON on stdin" >&2
  exit 1
fi

# Extract payload — support both full envelope and bare payload
payload=$(echo "$json" | jq -r 'if .payload then .payload else . end')
phase_envelope=$(echo "$json" | jq -r '.phase // empty')

# Validate required fields
tier=$(echo "$payload" | jq -r '.tier // empty')
result=$(echo "$payload" | jq -r '.result // empty')
checks_passed=$(echo "$payload" | jq -r '.checks.passed // empty')
checks_failed=$(echo "$payload" | jq -r '.checks.failed // empty')
checks_total=$(echo "$payload" | jq -r '.checks.total // empty')

if [[ -z "$tier" || -z "$result" ]]; then
  echo "Error: missing required fields (tier, result)" >&2
  exit 1
fi

if [[ -z "$checks_passed" || -z "$checks_total" ]]; then
  echo "Error: missing required fields (checks.passed, checks.total)" >&2
  exit 1
fi

# Default failed to 0 if not present
if [[ -z "$checks_failed" ]]; then
  checks_failed=0
fi

# Phase from envelope or payload
phase=$(echo "$payload" | jq -r '.phase // empty')
if [[ -z "$phase" && -n "$phase_envelope" ]]; then
  phase="$phase_envelope"
fi
if [[ -z "$phase" ]]; then
  phase="unknown"
fi

date_val=$(date -u +%Y-%m-%d)

# Check if checks_detail exists and is a valid array
has_checks_detail="false"
detail_type=$(echo "$payload" | jq -r '.checks_detail | type // "null"' 2>/dev/null)
if [[ "$detail_type" == "array" ]]; then
  detail_len=$(echo "$payload" | jq -r '.checks_detail | length')
  if [[ "$detail_len" -gt 0 ]]; then
    has_checks_detail="true"
  fi
elif [[ "$detail_type" != "null" && "$detail_type" != "" ]]; then
  echo "Error: checks_detail must be an array, got $detail_type" >&2
  exit 1
fi

# Validate checks_detail entries have required fields
if [[ "$has_checks_detail" == "true" ]]; then
  invalid_entries=$(echo "$payload" | jq '[.checks_detail[] | select(.id == null or .id == "" or .status == null or .status == "")] | length')
  if [[ "$invalid_entries" -gt 0 ]]; then
    echo "Error: checks_detail entries must have id and status fields" >&2
    exit 1
  fi
fi

# Write to temp file first, then move atomically to prevent partial writes
tmp_output=$(mktemp "${output_path}.tmp.XXXXXX")
trap 'rm -f "$tmp_output"' EXIT

# Write frontmatter
{
  echo "---"
  echo "phase: $phase"
  echo "tier: $tier"
  echo "result: $result"
  echo "passed: $checks_passed"
  echo "failed: $checks_failed"
  echo "total: $checks_total"
  echo "date: $date_val"
  echo "---"
  echo ""
} > "$tmp_output"

if [[ "$has_checks_detail" == "true" ]]; then
  # Deterministic output from checks_detail

  # Known categories in canonical order (Bash 3.2 compatible — no associative arrays)
  KNOWN_CATEGORIES="must_have artifact key_link anti_pattern convention requirement"

  # Helper: get heading and column name for a known category
  category_heading() {
    case "$1" in
      must_have)    echo "Must-Have Checks" ;;
      artifact)     echo "Artifact Checks" ;;
      key_link)     echo "Key Link Checks" ;;
      anti_pattern) echo "Anti-Pattern Scan" ;;
      convention)   echo "Convention Compliance" ;;
      requirement)  echo "Requirement Mapping" ;;
    esac
  }
  category_col() {
    case "$1" in
      must_have)    echo "Truth/Condition" ;;
      artifact)     echo "Artifact" ;;
      key_link)     echo "Link" ;;
      anti_pattern) echo "Pattern" ;;
      convention)   echo "Convention" ;;
      requirement)  echo "Requirement" ;;
    esac
  }

  # Helper: escape pipe characters and newlines for markdown table cells
  escape_pipes() {
    printf '%s' "$1" | tr '\n' ' ' | sed 's/|/\&#124;/g'
  }

  # Helper: emit a table for a given category
  emit_section() {
    local category="$1"
    local heading="$2"
    local col_name="$3"

    local items
    items=$(echo "$payload" | jq -c --arg cat "$category" '[.checks_detail[] | select(.category == $cat)]')
    local count
    count=$(echo "$items" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
      return
    fi

    echo "## $heading"
    echo ""
    echo "| # | ID | $col_name | Status | Evidence |"
    echo "|---|-----|$(printf '%0.s-' $(seq 1 ${#col_name}))--|--------|----------|"

    # Emit rows with pipe escaping
    local i=0
    while IFS= read -r row; do
      i=$((i + 1))
      local rid rdesc rstatus revidence
      rid=$(echo "$row" | jq -r '.id // "-"')
      rdesc=$(escape_pipes "$(echo "$row" | jq -r '.description // "-"')")
      rstatus=$(echo "$row" | jq -r '.status // "-"')
      revidence=$(escape_pipes "$(echo "$row" | jq -r '.evidence // "-"')")
      echo "| $i | $rid | $rdesc | $rstatus | $revidence |"
    done < <(echo "$items" | jq -c '.[]')

    echo ""
  }

  # Emit known sections in canonical order
  for cat in $KNOWN_CATEGORIES; do
    emit_section "$cat" "$(category_heading "$cat")" "$(category_col "$cat")" >> "$tmp_output"
  done

  # Emit unknown-category items under "Other Checks" catch-all
  unknown_items=$(echo "$payload" | jq -c --arg known "$KNOWN_CATEGORIES" \
    '[.checks_detail[] | select(.category as $c | ($known | split(" ") | index($c)) == null)]')
  unknown_count=$(echo "$unknown_items" | jq 'length')
  if [[ "$unknown_count" -gt 0 ]]; then
    {
      echo "## Other Checks"
      echo ""
      echo "| # | ID | Check | Status | Evidence |"
      echo "|---|-----|-------|--------|----------|"
      ui=0
      while IFS= read -r row; do
        ui=$((ui + 1))
        uid=$(echo "$row" | jq -r '.id // "-"')
        udesc=$(escape_pipes "$(echo "$row" | jq -r '.description // "-"')")
        ustatus=$(echo "$row" | jq -r '.status // "-"')
        uevidence=$(escape_pipes "$(echo "$row" | jq -r '.evidence // "-"')")
        echo "| $ui | $uid | $udesc | $ustatus | $uevidence |"
      done < <(echo "$unknown_items" | jq -c '.[]')
      echo ""
    } >> "$tmp_output"
  fi

  # Pre-existing issues
  pre_existing=$(echo "$payload" | jq -c '.pre_existing_issues // []')
  pre_count=$(echo "$pre_existing" | jq 'length')
  if [[ "$pre_count" -gt 0 ]]; then
    {
      echo "## Pre-existing Issues"
      echo ""
      echo "| Test | File | Error |"
      echo "|------|------|-------|"
      while IFS= read -r pe_row; do
        pe_test=$(escape_pipes "$(echo "$pe_row" | jq -r '.test // "-"')")
        pe_file=$(escape_pipes "$(echo "$pe_row" | jq -r '.file // "-"')")
        pe_error=$(escape_pipes "$(echo "$pe_row" | jq -r '.error // "-"')")
        echo "| $pe_test | $pe_file | $pe_error |"
      done < <(echo "$pre_existing" | jq -c '.[]')
      echo ""
    } >> "$tmp_output"
  fi

  # Summary
  {
    echo "## Summary"
    echo ""
    echo "**Tier:** $tier"
    echo "**Result:** $result"
    echo "**Passed:** ${checks_passed}/${checks_total}"

    # Failed list from checks_detail
    failed_list=$(echo "$payload" | jq -r '[.checks_detail[] | select(.status == "FAIL") | .id] | join(", ")')
    if [[ -n "$failed_list" ]]; then
      echo "**Failed:** $failed_list"
    else
      echo "**Failed:** None"
    fi
  } >> "$tmp_output"

  # Atomic move
  mv "$tmp_output" "$output_path"

else
  # Fallback: no checks_detail — use body field if present
  body=$(echo "$payload" | jq -r '.body // empty')

  if [[ -n "$body" ]]; then
    echo "$body" >> "$tmp_output"
  else
    # Minimal summary from structured fields only
    {
      echo "## Summary"
      echo ""
      echo "**Tier:** $tier"
      echo "**Result:** $result"
      echo "**Passed:** ${checks_passed}/${checks_total}"

      failures=$(echo "$payload" | jq -r '[.failures[]? | .check] | join(", ")')
      if [[ -n "$failures" ]]; then
        echo "**Failed:** $failures"
      else
        echo "**Failed:** None"
      fi
    } >> "$tmp_output"
  fi

  # Atomic move
  mv "$tmp_output" "$output_path"
fi
