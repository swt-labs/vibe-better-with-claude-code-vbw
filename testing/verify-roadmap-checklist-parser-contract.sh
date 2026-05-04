#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; exit 1; }

function_body() {
  local file="$1" fn="$2"
  awk -v fn="$fn" '
    $0 ~ "^" fn "\\(\\)[[:space:]]*\\{" { in_fn = 1; depth = 0 }
    in_fn {
      print
      opens = gsub(/\{/, "{")
      closes = gsub(/\}/, "}")
      depth += opens - closes
      if (started && depth <= 0) exit
      started = 1
    }
  ' "$file"
}

assert_contains_literal() {
  local body="$1" needle="$2" label="$3"
  if grep -Fq -- "$needle" <<< "$body"; then
    pass "$label"
  else
    fail "$label"
  fi
}

assert_not_contains_literal() {
  local body="$1" needle="$2" label="$3"
  if grep -Fq -- "$needle" <<< "$body"; then
    fail "$label"
  else
    pass "$label"
  fi
}

verify_phase_number_consumer() {
  local file="$1" fn="$2" label="$3" body
  body=$(function_body "$ROOT_DIR/$file" "$fn")
  [ -n "$body" ] || fail "$label: function body found"
  pass "$label: function body found"
  assert_contains_literal "$body" "roadmap_checklist_phase_num_from_line" "$label: uses shared checklist parser"
  assert_not_contains_literal "$body" "BASH_REMATCH[1]" "$label: no BASH_REMATCH phase extraction"
  assert_not_contains_literal "$body" "Phase \\([0-9][0-9]*\\)" "$label: no sed phase extraction"
  assert_not_contains_literal "$body" "grep -iE '^\\- \\[(x| )\\]" "$label: no grep checklist phase filter"
}

verify_checklist_counter() {
  local file="$1" fn="$2" label="$3" body
  body=$(function_body "$ROOT_DIR/$file" "$fn")
  [ -n "$body" ] || fail "$label: function body found"
  pass "$label: function body found"
  assert_contains_literal "$body" "roadmap_checklist_phase_num_from_line" "$label: checklist count uses shared parser"
  assert_not_contains_literal "$body" "grep -cE '^\\- \\[.\\] (\\[)?Phase [0-9]+:'" "$label: no grep checklist count parser"
}

verify_phase_number_consumer "scripts/verify-state-consistency.sh" "run_check_roadmap_vs_summaries" "verify-state-consistency run_check_roadmap_vs_summaries"
verify_checklist_counter "scripts/verify-state-consistency.sh" "run_check_state_vs_roadmap" "verify-state-consistency run_check_state_vs_roadmap"
verify_phase_number_consumer "scripts/reconcile-state-md.sh" "rewrite_roadmap_checklist_projection" "reconcile-state-md rewrite_roadmap_checklist_projection"
verify_phase_number_consumer "scripts/state-updater.sh" "rewrite_roadmap_checkboxes_for_phase" "state-updater rewrite_roadmap_checkboxes_for_phase"

printf '\nAll ROADMAP checklist parser contract checks passed.\n'