#!/usr/bin/env bash
set -euo pipefail

# verify-readme-config-reference.sh — Contract test for issue #513
#
# Validates that the README configuration reference stays in sync with
# config/defaults.json and that linked detail sections cover the documented
# settings semantics.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$ROOT/README.md"
DEFAULTS_JSON="$ROOT/config/defaults.json"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

echo "=== README Config Reference Contract (Issue #513) ==="

if [ ! -f "$README" ]; then
  fail "README.md missing"
fi

if [ ! -f "$DEFAULTS_JSON" ]; then
  fail "config/defaults.json missing"
fi

extract_default_keys_in_source_order() {
  grep -E '^  "[a-z0-9_]+": ' "$DEFAULTS_JSON" | sed -E 's/^  "([^"]+)": .*/\1/'
}

extract_readme_default_rows() {
  sed -n '/^### All defaults$/,/^### Optional extension hooks$/p' "$README" |
    awk -F'|' '
      /^\| `[^`]+` \|/ {
        key=$2
        def=$3
        section=$4
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", def)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", section)
        gsub(/`/, "", key)
        gsub(/`/, "", def)
        print key "\t" def "\t" section
      }
    '
}

declare -a default_keys=()
while IFS= read -r key; do
  [ -n "$key" ] || continue
  default_keys+=("$key")
done < <(extract_default_keys_in_source_order)

if [ "${#default_keys[@]}" -gt 0 ]; then
  pass "Extracted defaults.json keys in source-file order"
else
  fail "Could not extract defaults.json keys in source-file order"
fi

declare -a table_keys=()
declare -A table_defaults=()
declare -A table_sections=()
declare -A table_counts=()

while IFS=$'\t' read -r key default_value section; do
  [ -n "${key:-}" ] || continue
  table_keys+=("$key")
  table_defaults["$key"]="$default_value"
  table_sections["$key"]="$section"
  table_counts["$key"]=$(( ${table_counts["$key"]:-0} + 1 ))
done < <(extract_readme_default_rows)

if [ "${#table_keys[@]}" -gt 0 ]; then
  pass "Extracted README All defaults table rows"
else
  fail "Could not extract README All defaults table rows"
fi

default_key_list="$(printf '%s\n' "${default_keys[@]}")"

echo ""
echo "--- Check: defaults.json keys appear exactly once in README table ---"
for key in "${default_keys[@]}"; do
  count="${table_counts[$key]:-0}"
  if [ "$count" -eq 1 ]; then
    pass "README All defaults includes '$key' exactly once"
  else
    fail "README All defaults includes '$key' $count times (expected exactly once)"
  fi
done

echo ""
echo "--- Check: README All defaults has no unexpected keys ---"
for key in "${!table_counts[@]}"; do
  if grep -Fxq "$key" <<< "$default_key_list"; then
    pass "README key '$key' exists in defaults.json"
  elif [ "$key" = "bash_guard" ]; then
    pass "README-only key 'bash_guard' is the intentional exception"
  else
    fail "README All defaults contains unexpected key '$key'"
  fi
done

echo ""
echo "--- Check: README default values match defaults.json ---"
for key in "${default_keys[@]}"; do
  if [ "$key" = "agent_max_turns" ]; then
    if [ "${table_defaults[$key]:-}" = "{...}" ]; then
      pass "README uses documented shorthand for agent_max_turns"
    else
      fail "README agent_max_turns default must use '{...}' shorthand"
    fi
    continue
  fi

  if [ "${table_counts[$key]:-0}" -ne 1 ]; then
    continue
  fi

  expected_value="$(jq -c --arg k "$key" '.[$k]' "$DEFAULTS_JSON")"
  actual_value="${table_defaults[$key]}"

  if [ "$expected_value" = "$actual_value" ]; then
    pass "README default for '$key' matches defaults.json"
  else
    fail "README default mismatch for '$key': defaults.json='$expected_value' README='$actual_value'"
  fi
done

echo ""
echo "--- Check: README All defaults order matches defaults.json source order ---"
expected_order="$(printf '%s\n' "${default_keys[@]}")"
actual_order="$(printf '%s\n' "${table_keys[@]}" | grep -vx 'bash_guard' || true)"
if [ "$expected_order" = "$actual_order" ]; then
  pass "README All defaults order matches defaults.json source-file order"
else
  fail "README All defaults order does not match defaults.json source-file order"
fi

echo ""
echo "--- Check: caveman rows link to the caveman section ---"
for key in caveman_style caveman_commit caveman_review; do
  if [ "${table_sections[$key]:-}" = "[Caveman language mode](#caveman-language-mode)" ]; then
    pass "README row '$key' links to the caveman section"
  else
    fail "README row '$key' must link to [Caveman language mode](#caveman-language-mode)"
  fi
done

echo ""
echo "--- Check: Skills and discovery documents discussion_mode semantics ---"
skills_section="$(sed -n '/^### Skills and discovery$/,/^### Model routing and cost$/p' "$README")"

if grep -Fq '| `discussion_mode` | string | `questions` | `questions` / `assumptions` / `auto` |' <<< "$skills_section"; then
  pass "Skills and discovery table documents discussion_mode"
else
  fail "Skills and discovery table missing discussion_mode row"
fi

if grep -Fq '`questions` asks clarifying questions from scratch.' <<< "$skills_section"; then
  pass "discussion_mode prose documents questions mode"
else
  fail "discussion_mode prose missing questions mode semantics"
fi

if grep -Fq '`assumptions` uses existing codebase map data to propose evidence-backed assumptions first, then falls back to questions if no map exists.' <<< "$skills_section"; then
  pass "discussion_mode prose documents assumptions fallback semantics"
else
  fail "discussion_mode prose missing assumptions fallback semantics"
fi

if grep -Fq '`auto` picks `assumptions` when `.vbw-planning/codebase/META.md` exists and otherwise uses `questions`.' <<< "$skills_section"; then
  pass "discussion_mode prose documents auto mode semantics"
else
  fail "discussion_mode prose missing auto mode semantics"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1