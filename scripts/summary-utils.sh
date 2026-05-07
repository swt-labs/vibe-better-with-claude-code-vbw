#!/bin/bash
# summary-utils.sh -- shared helpers for status-aware SUMMARY.md checking
# Source this from scripts that need status-based completion detection.
# All functions are portable bash (3.2+) with no external process dependencies
# on the hot path. This keeps summary counting stable under heavily parallel
# BATS runs where frequent fork/exec can intermittently fail.

trim_summary_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

extract_summary_status() {
  local f="$1"
  local line value
  local in_fm=false
  local saw_content=false
  local bom=$'\357\273\277'

  [ -f "$f" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"

    if [ "$saw_content" = false ]; then
      line="${line#"$bom"}"
      value=$(trim_summary_value "$line")
      if [ -z "$value" ]; then
        continue
      fi
      saw_content=true
      if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
        in_fm=true
        continue
      fi
      return 0
    fi

    if [ "$in_fm" = true ]; then
      if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
        return 0
      fi
      if [[ "$line" =~ ^[[:space:]]*status: ]]; then
        value="${line#*:}"
        value=$(trim_summary_value "$value")
        case "$value" in
          \"*\") value="${value#\"}"; value="${value%\"}" ;;
          \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        value=$(trim_summary_value "$value")
        printf '%s\n' "$value"
        return 0
      fi
    fi
  done < "$f"

  return 0
}

# is_summary_complete FILE_PATH
# Returns 0 if SUMMARY exists and has terminal-complete status, 1 otherwise.
# "complete" and "completed" are both accepted as terminal-complete.
# "partial" and "failed" are terminal but NOT complete.
is_summary_complete() {
  local f="$1"
  local status
  [ -f "$f" ] || return 1
  status=$(extract_summary_status "$f")
  case "$status" in
    complete|completed) return 0 ;;
    *) return 1 ;;
  esac
}

# is_summary_terminal FILE_PATH
# Returns 0 if SUMMARY exists and has any terminal status (complete|completed|partial|failed).
is_summary_terminal() {
  local f="$1"
  local status
  [ -f "$f" ] || return 1
  status=$(extract_summary_status "$f")
  case "$status" in
    complete|completed|partial|failed) return 0 ;;
    *) return 1 ;;
  esac
}

# is_valid_summary_status STATUS
# Returns 0 only for canonical runtime SUMMARY statuses.
# Brownfield "completed" is accepted by file-level helpers above, but runtime
# execution state should canonicalize it to "complete" before validation.
is_valid_summary_status() {
  local status
  status=$(trim_summary_value "${1:-}")
  case "$status" in
    complete|partial|failed) return 0 ;;
    *) return 1 ;;
  esac
}

# is_execution_progress_status STATUS
# Returns 0 for statuses that satisfy Execute dependency progression.
is_execution_progress_status() {
  local status
  status=$(trim_summary_value "${1:-}")
  case "$status" in
    complete|partial) return 0 ;;
    *) return 1 ;;
  esac
}

# count_complete_summaries DIR
# Returns count of SUMMARY.md files with terminal-complete status in DIR.
count_complete_summaries() {
  local dir="$1"
  local count=0
  local f
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_complete "$f"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

# count_done_summaries DIR
# Returns count of SUMMARY.md files considered "done" for Execute/statusline
# reconciliation: complete, completed, or partial. Runtime execution state
# preserves partial as partial; it is progression-satisfied but not strict-complete.
count_done_summaries() {
  local dir="$1"
  local count=0
  local f st
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    st=$(extract_summary_status "$f")
    case "$st" in complete|completed|partial) count=$((count + 1)) ;; esac
  done
  echo "$count"
}

# count_terminal_summaries DIR
# Returns count of SUMMARY.md files with any terminal status in DIR.
count_terminal_summaries() {
  local dir="$1"
  local count=0
  local f
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    if is_summary_terminal "$f"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

summary_extract_frontmatter_array_items() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0
  awk -v key="$key_name" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    function strip_quotes(v, first, last) {
      first = substr(v, 1, 1)
      last = substr(v, length(v), 1)
      if ((first == "\"" && last == "\"") || (first == squote && last == squote)) {
        return substr(v, 2, length(v) - 2)
      }
      return v
    }
    function emit_value(v) {
      v = trim(v)
      if (v == "") return
      v = strip_quotes(v)
      if (v != "") print v
    }
    function parse_flow_array(rest, i, ch, current, quote) {
      rest = trim(rest)
      if (rest !~ /^\[/) return 0
      sub(/^\[/, "", rest)
      sub(/\][[:space:]]*$/, "", rest)
      current = ""
      quote = ""
      for (i = 1; i <= length(rest); i++) {
        ch = substr(rest, i, 1)
        if (quote == "") {
          if (ch == "\"" || ch == squote) {
            quote = ch
            current = current ch
            continue
          }
          if (ch == ",") {
            emit_value(current)
            current = ""
            continue
          }
        } else if (ch == quote) {
          quote = ""
          current = current ch
          continue
        }
        current = current ch
      }
      emit_value(current)
      return 1
    }
    BEGIN {
      in_fm = 0
      in_arr = 0
      squote = sprintf("%c", 39)
    }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") {
      rest = $0
      sub("^" key ":[[:space:]]*", "", rest)
      if (parse_flow_array(rest)) exit
      in_arr = 1
      next
    }
    in_fm && in_arr && /^[[:space:]]+- / {
      line = $0
      sub(/^[[:space:]]+- /, "", line)
      emit_value(line)
      next
    }
    in_fm && in_arr && /^[^[:space:]]/ { exit }
  ' "$file_path" 2>/dev/null
}

summary_extract_body_deviation_items() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk '
    BEGIN { found=0; in_comment=0 }
    /^## Deviations/ || /^### Deviations/ { found=1; in_comment=0; next }
    found && (/^## / || /^### /) { found=0; next }
    found && /^[[:space:]]*$/ { next }
    found && /^[[:space:]]*<!--/ {
      in_comment=1
      if ($0 ~ /-->/) in_comment=0
      next
    }
    found && in_comment {
      if ($0 ~ /-->/) in_comment=0
      next
    }
    found { print }
  ' "$file_path" 2>/dev/null
}

normalize_summary_deviation_item() {
  awk '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    {
      line = $0
      sub(/^[[:space:]]*- /, "", line)
      line = trim(line)
      if (tolower(line) ~ /^\*\*n(one|\/a|a)\*\*/ || tolower(line) ~ /^\*\*no deviations\*\*/) next
      sub(/^\*\*[^*]+\*\*:?[[:space:]]*/, "", line)
      line = trim(line)
      if (line == "") next
      lc = tolower(line)
      if (lc ~ /^none(\.[[:space:]].*|\.?)$/ || lc ~ /^n\/a(\.[[:space:]].*|\.?)$/ || lc ~ /^na(\.[[:space:]].*|\.?)$/ || lc ~ /^no deviations($|[.:].*)/) next
      if (!(line in seen)) {
        seen[line] = 1
        print line
      }
    }
  '
}

# extract_summary_deviations FILE_PATH
# Emits one normalized non-placeholder deviation per line, merging YAML
# frontmatter and body sections in stable order. Frontmatter no longer masks
# body deviations; duplicates across both sources are emitted once.
extract_summary_deviations() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  {
    summary_extract_frontmatter_array_items "$file_path" deviations
    summary_extract_body_deviation_items "$file_path"
  } | normalize_summary_deviation_item
}
