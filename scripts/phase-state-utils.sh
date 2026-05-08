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

roadmap_checklist_duplicate_phase_nums() {
  local roadmap_file="$1"
  local seen="" emitted="" line num

  [ -f "$roadmap_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    if num=$(roadmap_checklist_phase_num_from_line "$line"); then
      case " $seen " in
        *" $num "*)
          case " $emitted " in
            *" $num "*) ;;
            *)
              printf '%s\n' "$num"
              emitted="$emitted $num"
              ;;
          esac
          ;;
      esac
      seen="$seen $num"
    fi
  done < "$roadmap_file"
}

roadmap_checklist_has_duplicate_phase_nums() {
  local roadmap_file="$1"
  local seen="" line num

  [ -f "$roadmap_file" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    if num=$(roadmap_checklist_phase_num_from_line "$line"); then
      case " $seen " in
        *" $num "*) return 0 ;;
      esac
      seen="$seen $num"
    fi
  done < "$roadmap_file"

  return 1
}

roadmap_phase_dir_prefix_num() {
  local phase_dir="$1" num
  num=$(basename "$phase_dir" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
  normalize_roadmap_phase_num "$num"
}

roadmap_duplicate_phase_dir_prefix_details() {
  local phases_dir="$1"
  local seen="" emitted="" dir num dup_dir dup_num names base

  [ -d "$phases_dir" ] || return 0

  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    num=$(roadmap_phase_dir_prefix_num "$dir")
    case " $seen " in
      *" $num "*)
        case " $emitted " in
          *" $num "*) ;;
          *)
            names=""
            while IFS= read -r dup_dir; do
              [ -n "$dup_dir" ] || continue
              dup_num=$(roadmap_phase_dir_prefix_num "$dup_dir")
              [ "$dup_num" = "$num" ] || continue
              base=$(basename "$dup_dir")
              names="${names:+$names, }$base"
            done < <(list_canonical_phase_dirs "$phases_dir")
            printf 'duplicate phase directory prefix %s is ambiguous across %s; ROADMAP numbering cannot be safely reconciled\n' "$num" "$names"
            emitted="$emitted $num"
            ;;
        esac
        ;;
    esac
    seen="$seen $num"
  done < <(list_canonical_phase_dirs "$phases_dir")
}

roadmap_phase_dir_prefixes_have_duplicates() {
  local detail

  while IFS= read -r detail; do
    [ -n "$detail" ] && return 0
  done < <(roadmap_duplicate_phase_dir_prefix_details "$1")

  return 1
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

_roadmap_unique_count() {
  local sequence="$1" seen="" count=0 num

  while IFS= read -r num; do
    [ -n "$num" ] || continue
    case " $seen " in *" $num "*) continue ;; esac
    seen="$seen $num"
    count=$((count + 1))
  done <<< "$sequence"

  printf '%s\n' "$count"
}

_roadmap_sequence_contains_all_unique_in_order() {
  local checklist_seq="$1" expected_seq="$2"
  local expected_count score

  expected_count=$(_roadmap_unique_count "$expected_seq")
  [ "$expected_count" -gt 0 ] || return 1
  score=$(_roadmap_candidate_score "$checklist_seq" "$expected_seq")
  [ "$score" -eq "$expected_count" ]
}

_roadmap_sequence_is_exact_ordinal() {
  local checklist_seq="$1" expected_count="$2"
  local idx=0 num

  [ "$expected_count" -gt 0 ] || return 1
  while IFS= read -r num; do
    [ -n "$num" ] || continue
    idx=$((idx + 1))
    [ "$num" = "$idx" ] || return 1
  done <<< "$checklist_seq"

  [ "$idx" -eq "$expected_count" ]
}

roadmap_checklist_phase_nums() {
  local roadmap_file="$1" line num

  [ -f "$roadmap_file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if num=$(roadmap_checklist_phase_num_from_line "$line"); then
      printf '%s\n' "$num"
    fi
  done < "$roadmap_file"
}

roadmap_checklist_count() {
  local roadmap_file="$1" count=0 num

  while IFS= read -r num; do
    [ -n "$num" ] || continue
    count=$((count + 1))
  done < <(roadmap_checklist_phase_nums "$roadmap_file")

  printf '%s\n' "$count"
}

roadmap_numbering_scheme() {
  local roadmap_file="$1" phases_dir="$2"
  local checklist_nums=() prefix_nums=()
  local line num dir idx checklist_seq prefix_seq dir_count

  [ -f "$roadmap_file" ] || { printf '%s\n' "unknown"; return 0; }
  [ -d "$phases_dir" ] || { printf '%s\n' "unknown"; return 0; }
  if roadmap_checklist_has_duplicate_phase_nums "$roadmap_file"; then
    printf '%s\n' "unknown"
    return 0
  fi

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
  done < <(list_canonical_phase_dirs "$phases_dir")

  if [ "${#prefix_nums[@]}" -eq 0 ]; then
    printf '%s\n' "unknown"
    return 0
  fi
  if roadmap_phase_dir_prefixes_have_duplicates "$phases_dir"; then
    printf '%s\n' "unknown"
    return 0
  fi
  if [ "${#checklist_nums[@]}" -eq 0 ]; then
    printf '%s\n' "prefix"
    return 0
  fi

  checklist_seq=$(printf '%s\n' "${checklist_nums[@]}")
  prefix_seq=$(printf '%s\n' "${prefix_nums[@]}")

  dir_count=${#prefix_nums[@]}
  if _roadmap_sequence_contains_all_unique_in_order "$checklist_seq" "$prefix_seq"; then
    printf '%s\n' "prefix"
  elif _roadmap_sequence_is_exact_ordinal "$checklist_seq" "$dir_count"; then
    printf '%s\n' "ordinal"
  else
    printf '%s\n' "unknown"
  fi
}

roadmap_numbering_mismatch_details() {
  local roadmap_file="$1" phases_dir="$2" scheme="${3:-}"
  local checklist_seen="" num dir dir_num base

  [ -f "$roadmap_file" ] || return 0
  [ -d "$phases_dir" ] || return 0
  [ -n "$scheme" ] || scheme=$(roadmap_numbering_scheme "$roadmap_file" "$phases_dir")

  if [ "$scheme" = "unknown" ]; then
    printf '%s\n' "ROADMAP checklist numbering scheme is mixed or unresolvable; skipping numbering-dependent rewrite"
    roadmap_duplicate_phase_dir_prefix_details "$phases_dir"
    return 0
  fi

  if [ "$scheme" = "ordinal" ]; then
    local idx=0 mismatch_count=0 first_position="" first_base="" first_prefix=""
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      idx=$((idx + 1))
      dir_num=$(roadmap_phase_dir_prefix_num "$dir")
      if [ "$dir_num" != "$idx" ]; then
        mismatch_count=$((mismatch_count + 1))
        if [ -z "$first_position" ]; then
          first_position="$idx"
          first_base=$(basename "$dir")
          first_prefix="$dir_num"
        fi
      fi
    done < <(list_canonical_phase_dirs "$phases_dir")
    if [ "$mismatch_count" -gt 0 ]; then
      if [ "$mismatch_count" -gt 1 ]; then
        printf 'legacy ordinal ROADMAP numbering is in use because phase directory prefixes diverge from the Phase 1..N checklist; position %s -> %s (prefix %s), plus %s more divergent phase dir(s)\n' "$first_position" "$first_base" "$first_prefix" "$((mismatch_count - 1))"
      else
        printf 'legacy ordinal ROADMAP numbering is in use because phase directory prefixes diverge from the Phase 1..N checklist; position %s -> %s (prefix %s)\n' "$first_position" "$first_base" "$first_prefix"
      fi
    fi
    return 0
  fi

  while IFS= read -r num; do
    [ -n "$num" ] || continue
    checklist_seen="$checklist_seen $num"
    if [ "$scheme" = "prefix" ] && ! roadmap_phase_dir_for_num "prefix" "$phases_dir" "$num" >/dev/null 2>&1; then
      printf 'ROADMAP phase %s has no matching %s-* phase directory; using prefix numbering and preserving missing phase slot\n' "$num" "$num"
    fi
  done < <(roadmap_checklist_phase_nums "$roadmap_file")

  if [ "$scheme" = "prefix" ]; then
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      dir_num=$(roadmap_phase_dir_prefix_num "$dir")
      case " $checklist_seen " in
        *" $dir_num "*) ;;
        *)
          base=$(basename "$dir")
          printf 'phase directory %s exists on disk but ROADMAP has no matching Phase %s entry; using prefix numbering\n' "$base" "$dir_num"
          ;;
      esac
    done < <(list_canonical_phase_dirs "$phases_dir")
  fi
}

phase_state_log_warning() {
  local planning_root="$1" detail="$2"
  local log ts lc

  [ -n "$planning_root" ] || return 0
  [ -d "$planning_root" ] || return 0
  [ -n "$detail" ] || return 0

  log="$planning_root/.hook-errors.log"
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '[%s] state-numbering-warning: %s\n' "$ts" "$detail" >> "$log" 2>/dev/null || return 0
  if [ -f "$log" ]; then
    lc=$(wc -l < "$log" 2>/dev/null | tr -d ' ')
    [ "${lc:-0}" -gt 50 ] && { tail -30 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; } 2>/dev/null
  fi
}

phase_state_log_numbering_warnings() {
  local planning_root="$1" roadmap_file="$2" phases_dir="$3" scheme="${4:-}"
  local detail

  while IFS= read -r detail; do
    [ -n "$detail" ] || continue
    phase_state_log_warning "$planning_root" "$detail"
  done < <(roadmap_numbering_mismatch_details "$roadmap_file" "$phases_dir" "$scheme")
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
  local wanted dir idx dir_num match_dir match_count

  wanted=$(normalize_roadmap_phase_num "$phase_num")
  [ -n "$wanted" ] || return 1
  [ "$wanted" != "0" ] || return 1

  idx=0
  match_dir=""
  match_count=0
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
      if [ "$scheme" = "prefix" ]; then
        match_dir="$dir"
        match_count=$((match_count + 1))
      else
        printf '%s\n' "$dir"
        return 0
      fi
    fi
  done < <(list_canonical_phase_dirs "$phases_dir")

  if [ "$scheme" = "prefix" ] && [ "$match_count" -eq 1 ]; then
    printf '%s\n' "$match_dir"
    return 0
  fi

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