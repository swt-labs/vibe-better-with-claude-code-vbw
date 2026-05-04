#!/bin/bash
# phase-state-utils.sh -- shared helpers for phase directory enumeration and
# status derivation from plan/summary artifacts.

list_canonical_phase_dirs() {
  local parent="$1"
  [ -d "$parent" ] || return 0

  # Collect phase dirs via bash glob (avoids find pipeline under parallel
  # fd contention). Only match NN-slug pattern (canonical phase dirs).
  local dirs=() d base
  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    base="${d%/}"
    base="${base##*/}"
    case "$base" in [0-9]*-*) dirs+=("${d%/}") ;; esac
  done
  [ ${#dirs[@]} -gt 0 ] || return 0
  printf '%s\n' "${dirs[@]}" | sort -V 2>/dev/null || \
    printf '%s\n' "${dirs[@]}" | awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-
}

count_phase_plans() {
  local dir="$1"
  local count=0
  local f
  for f in "$dir"/[0-9]*-PLAN.md "$dir"/PLAN.md; do
    [ -f "$f" ] && count=$((count + 1))
  done
  echo "$count"
}

phase_dir_display_name() {
  local dir="$1"
  local base

  base=$(basename "$dir")
  base=$(echo "$base" | sed 's/^[0-9]*-//')
  printf '%s' "$base" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
}

phase_dir_position() {
  local phase_dir="$1"
  local phases_parent="${2:-$(dirname "$phase_dir")}"
  local idx=0 dir

  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    idx=$((idx + 1))
    if [ "${dir%/}" = "${phase_dir%/}" ]; then
      echo "$idx"
      return 0
    fi
  done < <(list_canonical_phase_dirs "$phases_parent")

  echo ""
}

normalize_roadmap_phase_num() {
  local num="$1"
  num=$(printf '%s' "$num" | sed 's/^0*//')
  printf '%s\n' "${num:-0}"
}

roadmap_checklist_phase_num_from_line() {
  local line="$1" raw_num
  if [[ "$line" =~ ^-\ \[.\]\ \[?Phase\ ([0-9][0-9]*): ]]; then
    raw_num="${BASH_REMATCH[1]}"
    normalize_roadmap_phase_num "$raw_num"
    return 0
  fi
  return 1
}

roadmap_phase_dir_prefix_num() {
  local phase_dir="$1" num
  num=$(basename "$phase_dir" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
  normalize_roadmap_phase_num "$num"
}

_roadmap_index_in_sequence() {
  local wanted="$1" sequence="$2" idx=0 candidate

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    idx=$((idx + 1))
    if [ "$candidate" = "$wanted" ]; then
      printf '%s\n' "$idx"
      return 0
    fi
  done <<< "$sequence"

  return 1
}

_roadmap_candidate_score() {
  local checklist_seq="$1" expected_seq="$2"
  local seen="" last_idx=0 score=0 num expected_idx

  [ -n "$expected_seq" ] || { printf '%s\n' "0"; return 0; }

  while IFS= read -r num; do
    [ -n "$num" ] || continue
    case " $seen " in *" $num "*) continue ;; esac
    seen="$seen $num"

    if expected_idx=$(_roadmap_index_in_sequence "$num" "$expected_seq"); then
      if [ "$expected_idx" -le "$last_idx" ]; then
        printf '%s\n' "0"
        return 0
      fi
      last_idx="$expected_idx"
      score=$((score + 1))
    fi
  done <<< "$checklist_seq"

  printf '%s\n' "$score"
}

roadmap_numbering_scheme() {
  local roadmap_file="$1" phases_dir="$2"
  local checklist_nums=() prefix_nums=() ordinal_nums=()
  local line num dir idx checklist_seq prefix_seq ordinal_seq prefix_score ordinal_score

  [ -f "$roadmap_file" ] || { printf '%s\n' "unknown"; return 0; }
  [ -d "$phases_dir" ] || { printf '%s\n' "unknown"; return 0; }

  while IFS= read -r line || [ -n "$line" ]; do
    if num=$(roadmap_checklist_phase_num_from_line "$line"); then
      checklist_nums+=("$num")
    fi
  done < "$roadmap_file"

  idx=0
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    idx=$((idx + 1))
    prefix_nums+=("$(roadmap_phase_dir_prefix_num "$dir")")
    ordinal_nums+=("$idx")
  done < <(list_canonical_phase_dirs "$phases_dir")

  if [ "${#prefix_nums[@]}" -eq 0 ]; then
    printf '%s\n' "unknown"
    return 0
  fi
  if [ "${#checklist_nums[@]}" -eq 0 ]; then
    printf '%s\n' "prefix"
    return 0
  fi

  checklist_seq=$(printf '%s\n' "${checklist_nums[@]}")
  prefix_seq=$(printf '%s\n' "${prefix_nums[@]}")
  ordinal_seq=$(printf '%s\n' "${ordinal_nums[@]}")
  prefix_score=$(_roadmap_candidate_score "$checklist_seq" "$prefix_seq")
  ordinal_score=$(_roadmap_candidate_score "$checklist_seq" "$ordinal_seq")

  if [ "$prefix_score" -le 0 ] && [ "$ordinal_score" -le 0 ]; then
    printf '%s\n' "unknown"
  elif [ "$prefix_seq" = "$ordinal_seq" ]; then
    printf '%s\n' "prefix"
  elif [ "$prefix_score" -gt 0 ] && [ "$ordinal_score" -le 0 ]; then
    printf '%s\n' "prefix"
  elif [ "$ordinal_score" -gt 0 ] && [ "$prefix_score" -le 0 ]; then
    printf '%s\n' "ordinal"
  elif [ "$prefix_score" -gt "$ordinal_score" ]; then
    printf '%s\n' "prefix"
  elif [ "$ordinal_score" -gt "$prefix_score" ]; then
    printf '%s\n' "ordinal"
  else
    printf '%s\n' "unknown"
  fi
}

roadmap_phase_num_for_dir() {
  local scheme="$1" phase_dir="$2" phases_dir
  phases_dir="${3:-$(dirname "$phase_dir")}"

  case "$scheme" in
    prefix)
      roadmap_phase_dir_prefix_num "$phase_dir"
      ;;
    ordinal)
      phase_dir_position "$phase_dir" "$phases_dir"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

roadmap_phase_dir_for_num() {
  local scheme="$1" phases_dir="$2" phase_num="$3"
  local wanted dir idx dir_num

  wanted=$(normalize_roadmap_phase_num "$phase_num")
  [ -n "$wanted" ] || return 1
  [ "$wanted" != "0" ] || return 1

  idx=0
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    idx=$((idx + 1))
    case "$scheme" in
      prefix)
        dir_num=$(roadmap_phase_dir_prefix_num "$dir")
        ;;
      ordinal)
        dir_num="$idx"
        ;;
      *)
        return 1
        ;;
    esac
    if [ "$dir_num" = "$wanted" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done < <(list_canonical_phase_dirs "$phases_dir")

  return 1
}

find_phase_dir_by_ref() {
  local planning_dir="$1"
  local phase_ref="$2"
  local prefix_match

  [ -d "$planning_dir/phases" ] || return 0
  [ -n "$phase_ref" ] || return 0
  echo "$phase_ref" | grep -qE '^[0-9]+$' || return 0

  prefix_match=$(ls -d "$planning_dir/phases/$(printf '%02d' "$phase_ref")"-*/ 2>/dev/null | head -1)
  if [ -n "$prefix_match" ]; then
    echo "$prefix_match"
    return 0
  fi

  list_canonical_phase_dirs "$planning_dir/phases" | sed -n "${phase_ref}p"
}

phase_status_label() {
  local dir="$1"
  local phase_idx="$2"
  local plans complete terminal

  plans=$(count_phase_plans "$dir")
  complete=$(count_complete_summaries "$dir")
  terminal=$(count_terminal_summaries "$dir")

  if [ "$plans" -gt 0 ] && [ "$complete" -ge "$plans" ]; then
    echo "Complete"
  elif [ "$terminal" -gt 0 ]; then
    echo "In progress"
  elif [ "$plans" -gt 0 ]; then
    echo "Planned"
  elif [ "$phase_idx" -eq 1 ]; then
    echo "Pending planning"
  else
    echo "Pending"
  fi
}

resolve_phase_number_from_phase_dir() {
  local dir="$1"
  local base num artifact uat_file

  base=$(basename "$dir")
  num=$(printf '%s' "$base" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
  if [ -n "$num" ] && echo "$num" | grep -qE '^[0-9]+$'; then
    echo "$num"
    return 0
  fi

  artifact=$(find "$dir" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-PLAN.md' -o -name '[0-9]*-SUMMARY.md' -o -name '[0-9]*-UAT.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort) | head -1)
  if [ -n "$artifact" ]; then
    num=$(basename "$artifact" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
    if [ -n "$num" ] && echo "$num" | grep -qE '^[0-9]+$'; then
      echo "$num"
      return 0
    fi
  fi

  uat_file=$(find "$dir" -maxdepth 1 ! -name '.*' -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' 2>/dev/null | (sort -V 2>/dev/null || sort) | head -1)
  if [ -n "$uat_file" ] && [ -f "$uat_file" ]; then
    num=$(awk '
      NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm {
        lower = tolower($0)
        if (lower ~ /^phase:[[:space:]]*[0-9]+[[:space:]]*$/) {
          value = $0
          sub(/^[^:]*:[[:space:]]*/, "", value)
          gsub(/[[:space:]]+$/, "", value)
          print value
          exit
        }
      }
    ' "$uat_file" 2>/dev/null || true)
    if [ -n "$num" ] && echo "$num" | grep -qE '^[0-9]+$'; then
      echo "$num"
      return 0
    fi
  fi

  # Round-dir / active UAT fallback: when a non-canonical phase dir uses legacy
  # root artifacts but the current UAT lives at remediation/uat/round-*/R*-UAT.md,
  # recover the phase number from that current UAT frontmatter.
  if type current_uat &>/dev/null; then
    uat_file=$(current_uat "$dir")
  else
    uat_file=""
  fi
  if [ -n "$uat_file" ] && [ -f "$uat_file" ]; then
    num=$(awk '
      NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm {
        lower = tolower($0)
        if (lower ~ /^phase:[[:space:]]*[0-9]+[[:space:]]*$/) {
          value = $0
          sub(/^[^:]*:[[:space:]]*/, "", value)
          gsub(/[[:space:]]+$/, "", value)
          print value
          exit
        }
      }
    ' "$uat_file" 2>/dev/null || true)
    if [ -n "$num" ] && echo "$num" | grep -qE '^[0-9]+$'; then
      echo "$num"
      return 0
    fi
  fi

  echo ""
}