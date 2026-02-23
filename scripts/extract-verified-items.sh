#!/usr/bin/env bash
# extract-verified-items.sh — Extract compact QA-verified items from VERIFICATION.md
# Usage: extract-verified-items.sh <phase-dir>
# Output: One line per verified item (check ID + short description), plus verdict.
#         Empty output if no VERIFICATION.md exists.
# Purpose: Feed into verify.md so the LLM knows what QA already confirmed
#          and avoids generating redundant UAT checkpoints.
set -euo pipefail

phase_dir="${1:-}"
if [[ -z "$phase_dir" || ! -d "$phase_dir" ]]; then
  exit 0
fi

# Find VERIFICATION.md files in the phase directory
# Supports: NN-VERIFICATION.md, NN-VERIFICATION-waveN.md
verif_files=()
while IFS= read -r f; do
  verif_files+=("$f")
done < <(ls "$phase_dir"/*-VERIFICATION*.md 2>/dev/null)

if [[ ${#verif_files[@]} -eq 0 ]]; then
  exit 0
fi

echo "QA-VERIFIED ITEMS (do NOT generate UAT checkpoints for these):"

for vf in "${verif_files[@]}"; do
  # Try deterministic format first: parse YAML frontmatter
  result=""
  passed=""
  failed=""
  total=""
  tier=""
  in_frontmatter=false
  fm_count=0

  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      fm_count=$((fm_count + 1))
      if [[ $fm_count -eq 1 ]]; then
        in_frontmatter=true
        continue
      elif [[ $fm_count -eq 2 ]]; then
        in_frontmatter=false
        break
      fi
    fi
    if [[ "$in_frontmatter" == true ]]; then
      case "$line" in
        result:*) result=$(echo "$line" | sed 's/^result: *//') ;;
        passed:*) passed=$(echo "$line" | sed 's/^passed: *//') ;;
        failed:*) failed=$(echo "$line" | sed 's/^failed: *//') ;;
        total:*)  total=$(echo "$line" | sed 's/^total: *//') ;;
        tier:*)   tier=$(echo "$line" | sed 's/^tier: *//') ;;
      esac
    fi
  done < "$vf"

  # Try deterministic table format: look for any known section heading with ID column
  deterministic=false
  if grep -qE '^## (Must-Have Checks|Artifact Checks|Key Link Checks|Anti-Pattern Scan|Convention Compliance|Requirement Mapping|Skill-Augmented Checks|Other Checks)' "$vf" 2>/dev/null; then
    # Check if the table has the deterministic format (ID column)
    if grep -q '| # | ID |' "$vf" 2>/dev/null; then
      deterministic=true
    fi
  fi

  if [[ "$deterministic" == true ]]; then
    # Parse deterministic table rows: | N | ID | Description | Status | Evidence |
    # Extract from all check sections
    current_section=""
    while IFS= read -r line; do
      case "$line" in
        "## Must-Have Checks"*) current_section="must_have" ;;
        "## Artifact Checks"*) current_section="artifact" ;;
        "## Key Link Checks"*) current_section="key_link" ;;
        "## Anti-Pattern Scan"*) current_section="anti_pattern" ;;
        "## Convention Compliance"*) current_section="convention" ;;
        "## Requirement Mapping"*) current_section="requirement" ;;
        "## Skill-Augmented Checks"*) current_section="skill_augmented" ;;
        "## Other Checks"*) current_section="other" ;;
        "## Pre-existing"*|"## Summary"*) current_section="" ;;
        "| "*)
          # Skip header and separator rows
          if [[ "$line" == *"---|"* ]] || [[ "$line" == *"| # |"* ]] || [[ "$line" == *"| ID |"* ]]; then
            continue
          fi
          if [[ -n "$current_section" ]]; then
            # Handle escaped pipes (&#124;) by temporarily replacing them
            safe_line=$(echo "$line" | sed 's/\&#124;/__PIPE__/g')
            check_id=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}')
            description=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $4); print $4}' | sed 's/__PIPE__/|/g')
            # Status column position: 5-col tables (6 pipes) → $5; 6-col tables (7 pipes) → per-section
            col_count=$(echo "$safe_line" | tr -cd '|' | wc -c | tr -d ' ')
            if [[ "$col_count" -eq 7 ]]; then
              case "$current_section" in
                convention)
                  status=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $6); print $6}') ;;
                *)
                  status=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $7); print $7}') ;;
              esac
            else
              status=$(echo "$safe_line" | awk -F'|' '{gsub(/^ +| +$/, "", $5); print $5}')
            fi
            if [[ -n "$check_id" && -n "$status" ]]; then
              echo "  $status $check_id: $description"
            fi
          fi
          ;;
      esac
    done < "$vf"
  else
    # Brownfield fallback: try old ✓ ** / ⚠ ** patterns
    if grep -qE '^✓ \*\*|^⚠ \*\*' "$vf" 2>/dev/null; then
      grep -E '^✓ \*\*' "$vf" 2>/dev/null | sed 's/\*\*//g; s/ — .*//' | while IFS= read -r line; do
        echo "  $line"
      done
      grep -E '^⚠ \*\*' "$vf" 2>/dev/null | sed 's/\*\*//g; s/ — .*//' | while IFS= read -r line; do
        echo "  $line"
      done
    fi

    # Try old Total row pattern
    total_line=$(grep -E '^\| \*\*Total\*\*' "$vf" 2>/dev/null | head -1 || true)
    if [[ -n "$total_line" ]]; then
      old_passed=$(echo "$total_line" | sed 's/\*\*//g' | awk -F'|' '{print $3}' | tr -d ' ')
      old_failed=$(echo "$total_line" | sed 's/\*\*//g' | awk -F'|' '{print $4}' | tr -d ' ')
      old_warned=$(echo "$total_line" | sed 's/\*\*//g' | awk -F'|' '{print $5}' | tr -d ' ')
      echo "  QA totals: ${old_passed} passed, ${old_failed} failed, ${old_warned} warned"
    fi
  fi

  # Print summary from frontmatter (works for both formats)
  if [[ -n "$result" && -n "$total" ]]; then
    echo ""
    echo "  QA: $result (${passed:-0}/${total} passed${failed:+, ${failed} failed}${tier:+, tier: $tier})"
  else
    # Last resort: grep for Verdict line
    verdict=$(grep -i 'Verdict' "$vf" 2>/dev/null | sed 's/^#* *//; s/\*\*//g' | head -1)
    if [[ -n "$verdict" ]]; then
      echo ""
      echo "  $verdict"
    fi
  fi
done
