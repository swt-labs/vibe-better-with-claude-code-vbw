#!/usr/bin/env bash
set -euo pipefail

# qa-result-gate.sh — Deterministic QA result evaluator
#
# Reads VERIFICATION.md and outputs an unambiguous routing directive.
# The orchestrator follows the directive literally — no judgment, no rationalization.
#
# Usage: qa-result-gate.sh <phase-dir> [verif-name]
#   phase-dir:  path to the phase directory (required)
#   verif-name: VERIFICATION.md filename (optional, defaults to VERIFICATION.md)
#
# Output (key=value, always exits 0):
#   qa_gate_writer=<value>           — writer field from frontmatter (or "missing")
#   qa_gate_result=<value>           — result field from frontmatter (or "missing"/"unreadable")
#   qa_gate_fail_count=<N>           — count of FAIL rows in body
#   qa_gate_deviation_count=<N>      — count of non-placeholder deviations across SUMMARY.md files
#   qa_gate_known_issue_count=<N>    — unresolved phase known issues tracked on disk
#   qa_gate_plan_count=<N>           — count of *-PLAN.md files in phase dir
#   qa_gate_plans_verified_count=<N> — count of plans_verified entries in VERIFICATION.md frontmatter
#   qa_gate_routing=<DIRECTIVE>      — the routing decision
#
# Optional override diagnostics (only present when an override fires):
#   qa_gate_deviation_override=true  — PASS overridden because deviations exist but no FAIL checks
#   qa_gate_metadata_only_override=true — PASS overridden because remediation round changed only metadata
#   qa_gate_known_issues_override=true — PASS overridden because unresolved known issues remain
#   qa_gate_phase_deviation_count=<N> — deviations in phase-root SUMMARYs (metadata-only override)
#   qa_gate_plan_coverage=N/M        — plans verified vs plans expected
#
# Routing values:
#   PROCEED_TO_UAT       — QA passed cleanly, safe to enter UAT
#   REMEDIATION_REQUIRED — code has failures, needs plan→execute→verify cycle
#   QA_RERUN_REQUIRED    — no trustworthy QA result, re-spawn QA (not code remediation)

PHASE_DIR="${1:-}"
VERIF_NAME="${2:-}"
EXPLICIT_VERIF_NAME=false
if [ -n "$VERIF_NAME" ]; then
  EXPLICIT_VERIF_NAME=true
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE_VERIF_SCRIPT="$SCRIPT_DIR/resolve-verification-path.sh"

# Extract YAML-frontmatter array items from either block-list form:
#   key:
#     - value
# or flow-style form:
#   key: ["value", 'other value']
extract_frontmatter_array_items() {
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

normalize_recorded_path() {
  local path="${1:-}"
  local leading_char=""
  local trailing_char=""
  local squote="'"
  local dquote='"'
  local bquote='`'

  path=$(printf '%s' "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/,$//')
  if [ -n "$path" ]; then
    leading_char=${path%"${path#?}"}
    case "$leading_char" in
      "$squote"|"$dquote"|"$bquote") path="${path#?}" ;;
    esac
  fi
  if [ -n "$path" ]; then
    trailing_char=${path#"${path%?}"}
    case "$trailing_char" in
      "$squote"|"$dquote"|"$bquote") path="${path%?}" ;;
    esac
  fi
  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done
  printf '%s' "$path"
}

path_is_recorded_non_code_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$base" in
    SOURCE-UAT.md|PLAN.md|SUMMARY.md|VERIFICATION.md|RESEARCH.md|CONTEXT.md|UAT.md|STATE.md|ROADMAP.md|PROJECT.md|REQUIREMENTS.md|RESUME.md|SHIPPED.md|*-PLAN.md|*-SUMMARY.md|*-VERIFICATION.md|*-RESEARCH.md|*-CONTEXT.md|*-UAT.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_is_implementation_asset_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$path" in
    docs/*|*/docs/*)
      return 1
      ;;
  esac
  case "$path" in
    assets/*|*/assets/*|asset/*|*/asset/*|resources/*|*/resources/*|resource/*|*/resource/*|public/*|*/public/*|static/*|*/static/*|*/Assets.xcassets/*|Assets.xcassets/*)
      case "$base" in
        *.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp|*.txt|Contents.json)
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

path_is_documentation_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$path" in
    docs/*|*/docs/*)
      return 0
      ;;
  esac
  if path_is_implementation_asset_artifact "$path"; then
    return 1
  fi
  case "$base" in
    AGENTS.md|README|README.*|CHANGELOG|CHANGELOG.*|CONTRIBUTING|CONTRIBUTING.*|LICENSE|LICENSE.*|*.md|*.mdx|*.txt|*.rst|*.adoc|*.asciidoc|*.pdf|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_is_repo_hygiene_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$base" in
    .gitignore|.gitattributes|.editorconfig|.prettierignore|.eslintignore|.npmignore|.dockerignore|.stylelintignore|.markdownlint.json|.markdownlint.yaml|.markdownlint.yml|VERSION)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_is_metadata_artifact() {
  local path="${1:-}"
  case "$path" in
    .vbw-planning/*|.claude/*)
      return 0
      ;;
  esac
  if path_is_recorded_non_code_artifact "$path"; then
    return 0
  fi
  path_is_documentation_artifact "$path"
}

path_is_code_fix_support_artifact() {
  local path="${1:-}"
  case "$path" in
    .vbw-planning/*|.claude/*|.claude-plugin/*)
      return 0
      ;;
  esac
  if path_is_recorded_non_code_artifact "$path"; then
    return 0
  fi
  if path_is_documentation_artifact "$path"; then
    return 0
  fi
  path_is_repo_hygiene_artifact "$path"
}

path_is_process_exception_evidence_artifact() {
  local phase_dir="${1:-}"
  local path="${2:-}"
  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1
  if [ -n "$phase_dir" ]; then
    path=$(canonicalize_phase_path "$path" "$phase_dir")
  fi
  if path_is_qa_remediation_round_artifact "$path"; then
    return 0
  fi
  path_is_original_plan_artifact "$path" "$phase_dir"
}

path_is_qa_remediation_round_artifact() {
  local path="${1:-}"
  # Match remediation/qa/round-NN/RNN-{PLAN,SUMMARY}.md with digits-only round IDs
  [[ "$path" =~ (^|/)remediation/qa/round-[0-9]+/R[0-9]+-(PLAN|SUMMARY)\.md$ ]]
}

resolve_existing_path_target() {
  local path="${1:-}"
  local max_hops=40
  local hop=0
  local path_dir=""
  local path_base=""
  local target=""

  [ -n "$path" ] || return 1
  [ -e "$path" ] || return 1

  while [ -L "$path" ]; do
    if [ "$hop" -ge "$max_hops" ]; then
      return 1
    fi
    path_dir="${path%/*}"
    path_base="${path##*/}"
    [ -n "$path_dir" ] || path_dir="."
    path_dir="$(cd "$path_dir" 2>/dev/null && pwd -P || return 1)"
    target="$(readlink "$path_dir/$path_base" 2>/dev/null || true)"
    [ -n "$target" ] || return 1
    case "$target" in
      /*) path="$target" ;;
      *) path="$path_dir/$target" ;;
    esac
    hop=$((hop + 1))
  done

  path_dir="${path%/*}"
  path_base="${path##*/}"
  [ -n "$path_dir" ] || path_dir="."
  path_dir="$(cd "$path_dir" 2>/dev/null && pwd -P || return 1)"
  [ -e "$path_dir/$path_base" ] || return 1
  printf '%s' "$path_dir/$path_base"
}

resolve_original_plan_artifact_path() {
  local path="${1:-}"
  local phase_dir="${2:-}"
  local phase_dir_abs=""
  local repo_root_abs=""
  local phase_dir_rel=""
  local candidate=""
  local candidate_dir=""
  local candidate_base=""

  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1
  [ -n "$phase_dir" ] || return 1

  phase_dir_abs="$(cd "$phase_dir" 2>/dev/null && pwd -P || printf '%s' "$phase_dir")"
  repo_root_abs="$(git -C "$phase_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root_abs" ] && [[ "$phase_dir_abs" == "$repo_root_abs/"* ]]; then
    phase_dir_rel="${phase_dir_abs#"$repo_root_abs"/}"
  fi

  case "$path" in
    ../*|*/../*|*/./*) return 1 ;;
    */remediation/*) return 1 ;;
  esac

  if [[ "$path" == /* ]]; then
    candidate="$path"
  elif [ -n "$phase_dir_rel" ] && [[ "$path" == "$phase_dir_rel/"* ]]; then
    candidate="$repo_root_abs/$path"
  elif [[ "$path" != */* ]] && { [[ "$path" == *-PLAN.md ]] || [[ "$path" == PLAN.md ]]; }; then
    candidate="$phase_dir_abs/$path"
  else
    return 1
  fi

  candidate_dir="${candidate%/*}"
  candidate_base="${candidate##*/}"
  if [ -d "$candidate_dir" ]; then
    candidate_dir="$(cd "$candidate_dir" 2>/dev/null && pwd -P || printf '%s' "$candidate_dir")"
    candidate="$candidate_dir/$candidate_base"
  fi

  candidate="$(resolve_existing_path_target "$candidate" 2>/dev/null || true)"
  [ -n "$candidate" ] || return 1
  candidate_dir="${candidate%/*}"
  candidate_base="${candidate##*/}"

  [ "$candidate_dir" = "$phase_dir_abs" ] || return 1

  # Exclude remediation round plans (digits-only round IDs like R01, R100)
  if [[ "$candidate_base" =~ ^R[0-9]+(-.*)?-PLAN\.md$ ]]; then
    return 1
  fi
  case "$candidate_base" in
    *-PLAN.md|PLAN.md) ;;
    *) return 1 ;;
  esac

  [ -f "$candidate" ] || return 1
  printf '%s' "$candidate"
}

path_is_original_plan_artifact() {
  local path="${1:-}"
  local phase_dir="${2:-}"
  resolve_original_plan_artifact_path "$path" "$phase_dir" >/dev/null 2>&1
}

canonicalize_phase_path() {
  local path="${1:-}"
  local phase_dir="${2:-}"
  local phase_dir_abs=""
  local repo_root_abs=""
  local phase_dir_rel=""
  local path_dir=""
  local path_base=""

  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1

  if [[ "$path" == /* ]]; then
    path_dir="${path%/*}"
    path_base="${path##*/}"
    if [ -d "$path_dir" ]; then
      path_dir="$(cd "$path_dir" 2>/dev/null && pwd -P || printf '%s' "$path_dir")"
      path="$path_dir/$path_base"
    fi
  elif [[ "$path" == */* ]] && [ -n "$phase_dir" ]; then
    path_dir="${path%/*}"
    path_base="${path##*/}"
    if [ -d "$phase_dir/$path_dir" ]; then
      path_dir="$(cd "$phase_dir/$path_dir" 2>/dev/null && pwd -P || printf '%s' "$phase_dir/$path_dir")"
      path="$path_dir/$path_base"
    fi
  fi

  phase_dir_abs="$(cd "$phase_dir" 2>/dev/null && pwd -P || printf '%s' "$phase_dir")"
  repo_root_abs="$(git -C "$phase_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root_abs" ] && [[ "$phase_dir_abs" == "$repo_root_abs/"* ]]; then
    phase_dir_rel="${phase_dir_abs#"$repo_root_abs"/}"
  fi

  if [ -n "$repo_root_abs" ] && [[ "$path" == "$repo_root_abs/"* ]]; then
    printf '%s' "${path#"$repo_root_abs"/}"
    return 0
  fi

  if [ -n "$phase_dir_abs" ] && [[ "$path" == "$phase_dir_abs/"* ]]; then
    if [ -n "$repo_root_abs" ] && [[ "$path" == "$repo_root_abs/"* ]]; then
      printf '%s' "${path#"$repo_root_abs"/}"
    else
      printf '%s' "$path"
    fi
    return 0
  fi

  if [ -n "$phase_dir_rel" ] && [[ "$path" == "$phase_dir_rel/"* ]]; then
    printf '%s' "$path"
    return 0
  fi

  if [ -f "$phase_dir/$path" ]; then
    if [ -n "$phase_dir_rel" ]; then
      printf '%s' "$phase_dir_rel/$path"
    else
      printf '%s' "$phase_dir_abs/$path"
    fi
    return 0
  fi

  printf '%s' "$path"
}

canonicalize_recorded_paths() {
  local phase_dir="${1:-}"
  local path=""
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if [ -n "$phase_dir" ]; then
      path=$(canonicalize_phase_path "$path" "$phase_dir")
    fi
    [ -n "$path" ] || continue
    printf '%s\n' "$path"
  done | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u)
}

intersect_canonical_paths() {
  local candidate_paths="${1:-}"
  local reference_paths="${2:-}"
  local path=""
  [ -n "$candidate_paths" ] || return 0
  [ -n "$reference_paths" ] || return 0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if printf '%s\n' "$reference_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
    fi
  done <<< "$candidate_paths" | (sort -u 2>/dev/null || sort -u)
}

paths_include_original_plan_artifact() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if path_is_original_plan_artifact "$path" "$phase_dir"; then
      return 0
    fi
  done
  return 1
}

paths_include_non_metadata() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if [ -n "$phase_dir" ]; then
      path=$(canonicalize_phase_path "$path" "$phase_dir")
    fi
    if ! path_is_metadata_artifact "$path"; then
      return 0
    fi
  done
  return 1
}

paths_include_code_fix_evidence() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if [ -n "$phase_dir" ]; then
      path=$(canonicalize_phase_path "$path" "$phase_dir")
    fi
    if ! path_is_code_fix_support_artifact "$path"; then
      return 0
    fi
  done
  return 1
}

paths_include_process_exception_evidence() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if path_is_process_exception_evidence_artifact "$phase_dir" "$path"; then
      return 0
    fi
  done
  return 1
}

path_is_allowed_worktree_evidence_artifact() {
  local phase_dir="${1:-}"
  local path="${2:-}"
  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1
  if [ -n "$phase_dir" ]; then
    path=$(canonicalize_phase_path "$path" "$phase_dir")
  fi
  if path_is_qa_remediation_round_artifact "$path"; then
    return 0
  fi
  path_is_original_plan_artifact "$path" "$phase_dir"
}

resolve_corroborated_recorded_paths() {
  local phase_dir="${1:-}"
  local recorded_paths="${2:-}"
  local committed_paths="${3:-}"
  local worktree_paths="${4:-}"
  local ignored_worktree_paths="${5:-}"
  local path=""

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if printf '%s\n' "$committed_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
      continue
    fi
    if path_is_allowed_worktree_evidence_artifact "$phase_dir" "$path" \
      && printf '%s\n' "$worktree_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
      continue
    fi
    # Fallback: gitignored metadata artifacts present on disk (e.g.,
    # .vbw-planning/ paths when planning_tracking=ignore).
    if [ -n "$ignored_worktree_paths" ] \
      && path_is_metadata_artifact "$path" \
      && path_is_allowed_worktree_evidence_artifact "$phase_dir" "$path" \
      && printf '%s\n' "$ignored_worktree_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
    fi
  done <<< "$recorded_paths" | (sort -u 2>/dev/null || sort -u)
}

recorded_paths_are_fully_corroborated() {
  local recorded_paths="${1:-}"
  local corroborated_paths="${2:-}"
  local recorded_count corroborated_count
  recorded_count=$(printf '%s\n' "$recorded_paths" | awk 'NF { count++ } END { print count + 0 }')
  corroborated_count=$(printf '%s\n' "$corroborated_paths" | awk 'NF { count++ } END { print count + 0 }')
  [ "$recorded_count" -eq "$corroborated_count" ] 2>/dev/null
}

commit_hashes_to_changed_files() {
  local repo_root="${1:-}"
  local commit_hashes="${2:-}"
  [ -n "$repo_root" ] || return 0
  [ -n "$commit_hashes" ] || return 0
  while IFS= read -r commit_hash; do
    commit_hash=$(printf '%s' "$commit_hash" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//;s/^['\"]//;s/['\"]$//")
    [ -n "$commit_hash" ] || continue
    git -C "$repo_root" show --name-only --format= "$commit_hash" 2>/dev/null || true
  done <<< "$commit_hashes"
}

commit_hashes_resolve_cleanly() {
  local repo_root="${1:-}"
  local commit_hashes="${2:-}"
  local commit_hash
  [ -n "$repo_root" ] || return 1
  [ -n "$commit_hashes" ] || return 1
  while IFS= read -r commit_hash; do
    commit_hash=$(printf '%s' "$commit_hash" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//;s/^['\"]//;s/['\"]$//")
    [ -n "$commit_hash" ] || continue
    git -C "$repo_root" cat-file -e "${commit_hash}^{commit}" 2>/dev/null || return 1
  done <<< "$commit_hashes"
  return 0
}

commit_hashes_are_round_local() {
  local repo_root="${1:-}"
  local round_anchor_commit="${2:-}"
  local commit_hashes="${3:-}"
  local head_commit=""
  local commit_hash
  [ -n "$repo_root" ] || return 1
  [ -n "$round_anchor_commit" ] || return 1
  [ -n "$commit_hashes" ] || return 1
  git -C "$repo_root" cat-file -e "${round_anchor_commit}^{commit}" 2>/dev/null || return 1
  head_commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)
  [ -n "$head_commit" ] || return 1
  while IFS= read -r commit_hash; do
    commit_hash=$(printf '%s' "$commit_hash" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//;s/^['\"]//;s/['\"]$//")
    [ -n "$commit_hash" ] || continue
    git -C "$repo_root" cat-file -e "${commit_hash}^{commit}" 2>/dev/null || return 1
    [ "$commit_hash" != "$round_anchor_commit" ] || return 1
    git -C "$repo_root" merge-base --is-ancestor "$round_anchor_commit" "$commit_hash" 2>/dev/null || return 1
    git -C "$repo_root" merge-base --is-ancestor "$commit_hash" "$head_commit" 2>/dev/null || return 1
  done <<< "$commit_hashes"
  return 0
}

git_diff_paths_since_commit() {
  local repo_root="${1:-}"
  local anchor_commit="${2:-}"
  [ -n "$repo_root" ] || return 0
  [ -n "$anchor_commit" ] || return 0
  git -C "$repo_root" cat-file -e "${anchor_commit}^{commit}" 2>/dev/null || return 0
  git -C "$repo_root" diff --name-only "$anchor_commit"..HEAD 2>/dev/null || true
}

git_current_worktree_paths() {
  local repo_root="${1:-}"
  [ -n "$repo_root" ] || return 0
  git -C "$repo_root" diff --name-only HEAD 2>/dev/null || true
  git -C "$repo_root" ls-files --others --exclude-standard 2>/dev/null || true
}

# Return gitignored files that exist on disk and are metadata artifacts.
# Used as a third evidence source when planning_tracking=ignore puts
# .vbw-planning/ in .gitignore — the normal diff/worktree sets exclude
# these paths, but they are valid evidence for plan-amendment rounds.
git_ignored_metadata_worktree_paths() {
  local repo_root="${1:-}"
  local path
  [ -n "$repo_root" ] || return 0
  # Use pathspec to limit git's scan to metadata prefixes only, avoiding
  # enumeration of large ignored trees like node_modules/.
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if path_is_metadata_artifact "$path"; then
      printf '%s\n' "$path"
    fi
  done < <(git -C "$repo_root" ls-files --others --ignored --exclude-standard \
    -- .vbw-planning .claude 2>/dev/null || true)
}

commit_is_ancestor_or_same() {
  local repo_root="${1:-}"
  local ancestor_commit="${2:-}"
  local descendant_commit="${3:-}"
  [ -n "$repo_root" ] || return 1
  [ -n "$ancestor_commit" ] || return 1
  [ -n "$descendant_commit" ] || return 1
  git -C "$repo_root" cat-file -e "${ancestor_commit}^{commit}" 2>/dev/null || return 1
  git -C "$repo_root" cat-file -e "${descendant_commit}^{commit}" 2>/dev/null || return 1
  git -C "$repo_root" merge-base --is-ancestor "$ancestor_commit" "$descendant_commit" 2>/dev/null
}

extract_verified_at_commit() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^verified_at_commit:/ {
      sub(/^verified_at_commit:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$file_path" 2>/dev/null
}

extract_fail_classification_types() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    BEGIN {
      in_fm = 0
      in_fc = 0
      squote = sprintf("%c", 39)
    }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^fail_classifications:/ {
      rest = $0
      sub(/^fail_classifications:[[:space:]]*/, "", rest)
      if (rest ~ /^\[/) {
        while (match(rest, /type:[[:space:]]*[^,}\]]+/)) {
          type = substr(rest, RSTART, RLENGTH)
          sub(/^type:[[:space:]]*/, "", type)
          gsub(/[",}]/, "", type)
          gsub(squote, "", type)
          type = trim(type)
          if (type != "") print type
          rest = substr(rest, RSTART + RLENGTH)
        }
        exit
      }
      in_fc = 1
      next
    }
    in_fm && in_fc && /^[[:space:]]+- / {
      line = $0
      if (match(line, /type:[[:space:]]*[^,}]+/)) {
        type = substr(line, RSTART, RLENGTH)
        sub(/^type:[[:space:]]*/, "", type)
        gsub(/[",}]/, "", type)
        gsub(squote, "", type)
        type = trim(type)
        if (type != "") print type
      }
      next
    }
    in_fm && in_fc && /^[[:space:]]+type:/ {
      line = $0
      sub(/^[[:space:]]+type:[[:space:]]*/, "", line)
      gsub(/[",}]/, "", line)
      gsub(squote, "", line)
      line = trim(line)
      if (line != "") print line
      next
    }
    in_fm && in_fc && /^[^[:space:]]/ { exit }
  ' "$file_path" 2>/dev/null
}

extract_fail_classification_ids() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    BEGIN {
      in_fm = 0
      in_fc = 0
      squote = sprintf("%c", 39)
    }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^fail_classifications:/ {
      rest = $0
      sub(/^fail_classifications:[[:space:]]*/, "", rest)
      if (rest ~ /^\[/) {
        while (match(rest, /id:[[:space:]]*[^,}\]]+/)) {
          id = substr(rest, RSTART, RLENGTH)
          sub(/^id:[[:space:]]*/, "", id)
          gsub(/[",}]/, "", id)
          gsub(squote, "", id)
          id = trim(id)
          if (id != "") print id
          rest = substr(rest, RSTART + RLENGTH)
        }
        exit
      }
      in_fc = 1
      next
    }
    in_fm && in_fc && /^[[:space:]]+- / {
      line = $0
      if (match(line, /id:[[:space:]]*[^,}]+/)) {
        id = substr(line, RSTART, RLENGTH)
        sub(/^id:[[:space:]]*/, "", id)
        gsub(/[",}]/, "", id)
        gsub(squote, "", id)
        id = trim(id)
        if (id != "") print id
      }
      next
    }
    in_fm && in_fc && /^[[:space:]]+id:/ {
      line = $0
      sub(/^[[:space:]]+id:[[:space:]]*/, "", line)
      gsub(/[",}]/, "", line)
      gsub(squote, "", line)
      line = trim(line)
      if (line != "") print line
      next
    }
    in_fm && in_fc && /^[^[:space:]]/ { exit }
  ' "$file_path" 2>/dev/null
}

collect_fail_classification_types_in_dir() {
  local scan_dir="${1:-}"
  [ -d "$scan_dir" ] || return 0
  while IFS= read -r _cfc_plan; do
    [ -f "$_cfc_plan" ] || continue
    extract_fail_classification_types "$_cfc_plan"
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}

collect_fail_classification_ids_in_dir() {
  local scan_dir="${1:-}"
  [ -d "$scan_dir" ] || return 0
  while IFS= read -r _cfc_plan; do
    [ -f "$_cfc_plan" ] || continue
    extract_fail_classification_ids "$_cfc_plan"
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}

extract_fail_classification_source_plans() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    BEGIN {
      in_fm = 0
      in_fc = 0
      squote = sprintf("%c", 39)
    }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^fail_classifications:/ {
      rest = $0
      sub(/^fail_classifications:[[:space:]]*/, "", rest)
      if (rest ~ /^\[/) {
        while (match(rest, /source_plan:[[:space:]]*[^,}\]]+/)) {
          source_plan = substr(rest, RSTART, RLENGTH)
          sub(/^source_plan:[[:space:]]*/, "", source_plan)
          gsub(/[",}]/, "", source_plan)
          gsub(squote, "", source_plan)
          source_plan = trim(source_plan)
          if (source_plan != "") print source_plan
          rest = substr(rest, RSTART + RLENGTH)
        }
        exit
      }
      in_fc = 1
      next
    }
    in_fm && in_fc && /^[[:space:]]+- / {
      line = $0
      if (match(line, /source_plan:[[:space:]]*[^,}]+/)) {
        source_plan = substr(line, RSTART, RLENGTH)
        sub(/^source_plan:[[:space:]]*/, "", source_plan)
        gsub(/[",}]/, "", source_plan)
        gsub(squote, "", source_plan)
        source_plan = trim(source_plan)
        if (source_plan != "") print source_plan
      }
      next
    }
    in_fm && in_fc && /^[[:space:]]+source_plan:/ {
      line = $0
      sub(/^[[:space:]]+source_plan:[[:space:]]*/, "", line)
      gsub(/[",}]/, "", line)
      gsub(squote, "", line)
      line = trim(line)
      if (line != "") print line
      next
    }
    in_fm && in_fc && /^[^[:space:]]/ { exit }
  ' "$file_path" 2>/dev/null
}

collect_fail_classification_source_plans_in_dir() {
  local scan_dir="${1:-}"
  [ -d "$scan_dir" ] || return 0
  while IFS= read -r _cfc_plan; do
    [ -f "$_cfc_plan" ] || continue
    extract_fail_classification_source_plans "$_cfc_plan"
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}

plan_amendment_source_plans_are_valid() {
  local phase_dir="${1:-}"
  local source_plan canonical_plan
  while IFS= read -r source_plan; do
    source_plan=$(normalize_recorded_path "$source_plan")
    [ -n "$source_plan" ] || return 1
    canonical_plan=$(canonicalize_phase_path "$source_plan" "$phase_dir")
    if ! path_is_original_plan_artifact "$canonical_plan" "$phase_dir"; then
      return 1
    fi
  done
  return 0
}

paths_cover_required_original_plan_artifacts() {
  local phase_dir="${1:-}"
  local required_paths="${2:-}"
  local recorded_paths required_path required_canonical recorded_path recorded_canonical found

  recorded_paths=$(cat)
  while IFS= read -r required_path; do
    required_path=$(normalize_recorded_path "$required_path")
    [ -n "$required_path" ] || return 1
    required_canonical=$(canonicalize_phase_path "$required_path" "$phase_dir")
    [ -n "$required_canonical" ] || return 1

    found=false
    while IFS= read -r recorded_path; do
      recorded_path=$(normalize_recorded_path "$recorded_path")
      [ -n "$recorded_path" ] || continue
      recorded_canonical=$(canonicalize_phase_path "$recorded_path" "$phase_dir")
      if [ "$recorded_canonical" = "$required_canonical" ]; then
        found=true
        break
      fi
    done <<< "$recorded_paths"

    [ "$found" = true ] || return 1
  done <<< "$required_paths"

  return 0
}

fail_classification_types_are_valid() {
  local saw_type=false
  while IFS= read -r classification_type; do
    [ -n "$classification_type" ] || continue
    saw_type=true
    case "$classification_type" in
      code-fix|plan-amendment|process-exception) ;;
      *) return 1 ;;
    esac
  done
  [ "$saw_type" = true ]
}

extract_fail_ids_from_verification() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    !/^\|/ { header_found = 0; next }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      if (!header_found) {
        status_col = 0
        id_col = 0
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") status_col = i
          if (cell == "ID") id_col = i
        }
        if (status_col > 0) header_found = 1
        next
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") {
          fail_index++
          fail_id = (id_col > 0) ? trim($(id_col)) : ""
          if (fail_id == "") fail_id = sprintf("FAIL-ROW-%02d", fail_index)
          print fail_id
        }
      }
    }
  ' "$file_path" 2>/dev/null
}

count_fail_rows_in_verification() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || { echo 0; return; }
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    !/^\|/ { header_found = 0; next }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      if (!header_found) {
        status_col = 0
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") status_col = i
        }
        if (status_col > 0) header_found = 1
        next
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") count++
      }
    }
    END { print count + 0 }
  ' "$file_path" 2>/dev/null
}

classification_ids_cover_source_fail_ids() {
  local source_fail_ids="${1:-}"
  local classified_ids="${2:-}"
  while IFS= read -r source_fail_id; do
    [ -n "$source_fail_id" ] || continue
    if ! printf '%s\n' "$classified_ids" | grep -Fx -- "$source_fail_id" >/dev/null 2>&1; then
      return 1
    fi
  done <<< "$source_fail_ids"
  return 0
}

extract_frontmatter_json_object_array() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  local kind="${3:-issue}"
  local item=""
  local tmp_file=""
  [ -f "$file_path" ] || { echo '[]'; return 0; }
  [ -n "$key_name" ] || { echo '[]'; return 0; }

  tmp_file=$(mktemp)
  while IFS= read -r item; do
    item=$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -n "$item" ] || continue
    case "$kind" in
      issue)
        printf '%s' "$item" | jq -ce '
          select(
            type == "object"
            and (.test | type == "string")
            and (.file | type == "string")
            and (.error | type == "string")
          )
        ' >> "$tmp_file" 2>/dev/null || true
        ;;
      resolution|outcome)
        printf '%s' "$item" | jq -ce '
          select(
            type == "object"
            and (.test | type == "string")
            and (.file | type == "string")
            and (.error | type == "string")
            and (.disposition | type == "string")
            and (.rationale | type == "string")
            and (
              .disposition == "resolved"
              or .disposition == "accepted-process-exception"
              or .disposition == "unresolved"
            )
          )
        ' >> "$tmp_file" 2>/dev/null || true
        ;;
    esac
  done < <(extract_frontmatter_array_items "$file_path" "$key_name")

  if [ ! -s "$tmp_file" ]; then
    rm -f "$tmp_file"
    echo '[]'
    return 0
  fi

  jq -sc 'unique_by(.test, .file, .error) | sort_by(.test, .file, .error)' "$tmp_file"
  rm -f "$tmp_file"
}

collect_frontmatter_json_object_array_in_dir() {
  local scan_dir="${1:-}"
  local file_glob_mode="${2:-plan}"
  local key_name="${3:-}"
  local kind="${4:-issue}"
  local scan_file=""
  local tmp_file=""
  [ -d "$scan_dir" ] || { echo '[]'; return 0; }
  [ -n "$key_name" ] || { echo '[]'; return 0; }

  tmp_file=$(mktemp)
  case "$file_glob_mode" in
    summary)
      while IFS= read -r scan_file; do
        [ -f "$scan_file" ] || continue
        extract_frontmatter_json_object_array "$scan_file" "$key_name" "$kind" | jq -c '.[]' >> "$tmp_file" 2>/dev/null || true
      done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
      ;;
    *)
      while IFS= read -r scan_file; do
        [ -f "$scan_file" ] || continue
        extract_frontmatter_json_object_array "$scan_file" "$key_name" "$kind" | jq -c '.[]' >> "$tmp_file" 2>/dev/null || true
      done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
      ;;
  esac

  if [ ! -s "$tmp_file" ]; then
    rm -f "$tmp_file"
    echo '[]'
    return 0
  fi

  jq -sc 'unique_by(.test, .file, .error) | sort_by(.test, .file, .error)' "$tmp_file"
  rm -f "$tmp_file"
}

json_object_array_length() {
  local json_array="${1:-[]}"
  printf '%s' "$json_array" | jq 'length' 2>/dev/null || echo 0
}

json_object_array_covers_full_issue_objects() {
  local required_json="${1:-[]}"
  local candidate_json="${2:-[]}"
  local test_name=""
  local file_path=""
  local error_msg=""

  while IFS=$'\t' read -r test_name file_path error_msg; do
    [ -n "$test_name" ] || continue
    printf '%s' "$candidate_json" | jq -e --arg test "$test_name" --arg file "$file_path" --arg error "$error_msg" '.[] | select(.test == $test and .file == $file and .error == $error)' >/dev/null 2>&1 || return 1
  done < <(printf '%s' "$required_json" | jq -r '.[] | [.test, .file, .error] | @tsv' 2>/dev/null)

  return 0
}

load_known_issue_registry_json() {
  local registry_path="${1:-}"
  [ -n "$registry_path" ] || { echo '[]'; return 0; }
  [ -f "$registry_path" ] || { echo '[]'; return 0; }
  jq -c 'select(type == "object" and (.issues | type == "array")) | .issues' "$registry_path" 2>/dev/null || echo '[]'
}

json_object_array_dispositions_match() {
  local expected_json="${1:-[]}"
  local actual_json="${2:-[]}"
  local test_name=""
  local file_path=""
  local error_msg=""
  local disposition=""

  while IFS=$'\t' read -r test_name file_path error_msg disposition; do
    [ -n "$test_name" ] || continue
    printf '%s' "$actual_json" | jq -e --arg test "$test_name" --arg file "$file_path" --arg error "$error_msg" --arg disposition "$disposition" '.[] | select(.test == $test and .file == $file and .error == $error and .disposition == $disposition)' >/dev/null 2>&1 || return 1
  done < <(printf '%s' "$expected_json" | jq -r '.[] | [.test, .file, .error, .disposition] | @tsv' 2>/dev/null)

  return 0
}

json_object_array_has_disposition() {
  local json_array="${1:-[]}"
  local disposition="${2:-}"
  [ -n "$disposition" ] || return 1
  printf '%s' "$json_array" | jq -e --arg disposition "$disposition" '.[] | select(.disposition == $disposition)' >/dev/null 2>&1
}

if [ -z "$PHASE_DIR" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# Auto-resolve VERIFICATION.md filename using the same convention as
# phase-detect.sh and hard-gate.sh: {NN}-VERIFICATION.md is the primary
# convention, with plain VERIFICATION.md as a brownfield fallback.
if [ -z "$VERIF_NAME" ]; then
  VERIF_PATH=$(bash "$RESOLVE_VERIF_SCRIPT" phase "$PHASE_DIR" 2>/dev/null || true)
  if [ -n "$VERIF_PATH" ]; then
    VERIF_NAME=$(basename "$VERIF_PATH")
  else
    PHASE_NUM=$(basename "$PHASE_DIR" | grep -oE '^[0-9]+' 2>/dev/null || true)
    VERIF_NAME="${PHASE_NUM:-01}-VERIFICATION.md"
    VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
  fi
else
  VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
fi

# Detect active QA remediation — deviation override is suppressed during remediation
# because SUMMARY.md deviations are historical (the code has been fixed)
IN_REMEDIATION="false"
PLAN_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level plans
SUMMARY_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level summaries
if [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]; then
  _gate_stage=$(grep '^stage=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_stage="${_gate_stage:-none}"
  case "$_gate_stage" in
    plan|execute|verify|done) IN_REMEDIATION="true" ;;
    *) _gate_stage="none" ;;
  esac
  _gate_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_round="${_gate_round:-01}"
  # Defensive: ensure round is numeric before arithmetic
  if ! [[ "$_gate_round" =~ ^[0-9]+$ ]]; then
    _gate_round="01"
  fi
  # Defensive zero-padding (consistent with phase-detect.sh)
  _gate_round=$(printf '%02d' "$((10#${_gate_round}))")
  _gate_round_dir="$PHASE_DIR/remediation/qa/round-${_gate_round}"
  _gate_round_verif="${_gate_round_dir}/R${_gate_round}-VERIFICATION.md"
  if [ "$EXPLICIT_VERIF_NAME" = false ]; then
    case "$_gate_stage" in
      verify)
        VERIF_PATH="$_gate_round_verif"
        VERIF_NAME=$(basename "$VERIF_PATH")
        ;;
      done)
        _gate_authoritative_verif=$(bash "$RESOLVE_VERIF_SCRIPT" authoritative "$PHASE_DIR" 2>/dev/null || true)
        if [ -n "${_gate_authoritative_verif:-}" ]; then
          VERIF_PATH="$_gate_authoritative_verif"
          VERIF_NAME=$(basename "$VERIF_PATH")
        fi
        ;;
    esac
  fi
  if [ "$VERIF_PATH" = "$_gate_round_verif" ]; then
    PLAN_SCOPE_DIR="$_gate_round_dir"
    SUMMARY_SCOPE_DIR="$_gate_round_dir"
  fi
fi

GIT_ROOT=$(git -C "$PHASE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
KNOWN_ISSUES_STATUS="missing"
KNOWN_ISSUES_COUNT=0
if [ -f "$SCRIPT_DIR/track-known-issues.sh" ]; then
  _known_issues_meta=$(bash "$SCRIPT_DIR/track-known-issues.sh" status "$PHASE_DIR" 2>/dev/null || true)
  KNOWN_ISSUES_STATUS=$(printf '%s\n' "${_known_issues_meta:-}" | awk -F= '/^known_issues_status=/{print $2; exit}')
  KNOWN_ISSUES_COUNT=$(printf '%s\n' "${_known_issues_meta:-}" | awk -F= '/^known_issues_count=/{print $2; exit}')
fi
KNOWN_ISSUES_STATUS="${KNOWN_ISSUES_STATUS:-missing}"
KNOWN_ISSUES_COUNT="${KNOWN_ISSUES_COUNT:-0}"

# Count non-placeholder deviations across SUMMARY.md files in a given directory.
# Uses the same AWK extraction logic as execute-protocol.md Step 4.
# Arguments: $1 = directory to scan for SUMMARY.md files
count_deviations_in_dir() {
  local scan_dir="${1:-}"
  local total=0
  [ -d "$scan_dir" ] || { echo 0; return; }
  while IFS= read -r _cdf_file; do
    [ -f "$_cdf_file" ] || continue
    local _cdf_devs
    _cdf_devs=$(extract_frontmatter_array_items "$_cdf_file" deviations | awk '
      BEGIN { count=0 }
      {
        lc = tolower($0)
        if (lc ~ /^none\.?$/ || lc ~ /^n\/a\.?$/ || lc ~ /^na\.?$/ || lc ~ /^no deviations/) next
        count++
      }
      END { print count }
    ' 2>/dev/null)
    if [ "${_cdf_devs:-0}" -eq 0 ]; then
      _cdf_devs=$(awk '
        BEGIN { count=0; found=0 }
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
        found {
          line=$0
          sub(/^- /, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          if (tolower(line) ~ /^\*\*n(one|\/a|a)\*\*/ || tolower(line) ~ /^\*\*no deviations\*\*/) next
          sub(/^\*\*[^*]+\*\*:?[[:space:]]*/, "", line)
          if (line == "") next
          lc = tolower(line)
          if (lc ~ /^none(\.[[:space:]].*|\.?)$/ || lc ~ /^n\/a(\.[[:space:]].*|\.?)$/ || lc ~ /^na(\.[[:space:]].*|\.?)$/ || lc ~ /^no deviations($|[.:].*)/) next
          count++
        }
        END { print count }
      ' "$_cdf_file" 2>/dev/null)
    fi
    total=$((total + ${_cdf_devs:-0}))
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
  echo "$total"
}

# 1. File doesn't exist
if [ ! -f "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_known_issue_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 2. File unreadable
if [ ! -r "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=unreadable"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_known_issue_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# Parse frontmatter fields
WRITER=$(awk '
  BEGIN { in_fm=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^writer:/ { sub(/^writer:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
' "$VERIF_PATH" 2>/dev/null)

RESULT=$(awk '
  BEGIN { in_fm=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^result:/ { sub(/^result:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
' "$VERIF_PATH" 2>/dev/null)

# Body FAIL count (defense-in-depth cross-check)
FAIL_COUNT=$(count_fail_rows_in_verification "$VERIF_PATH")

# Deviation count — scan SUMMARY.md files for non-placeholder deviations
DEVIATION_COUNT=$(count_deviations_in_dir "$SUMMARY_SCOPE_DIR")

ROUND_SOURCE_VERIFICATION_MISSING="false"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  if [ -n "${_gate_round:-}" ] && [ "$((10#${_gate_round}))" -gt 1 ] 2>/dev/null; then
    _expected_source_round=$(printf '%02d' "$((10#${_gate_round} - 1))")
    _expected_source_verification="$PHASE_DIR/remediation/qa/round-${_expected_source_round}/R${_expected_source_round}-VERIFICATION.md"
    if [ ! -r "$_expected_source_verification" ]; then
      ROUND_SOURCE_VERIFICATION_MISSING="true"
    fi
  else
    _phase_source_verification=$(bash "$SCRIPT_DIR/resolve-verification-path.sh" phase "$PHASE_DIR" 2>/dev/null || true)
    if [ -z "$_phase_source_verification" ] || [ ! -r "$_phase_source_verification" ]; then
      ROUND_SOURCE_VERIFICATION_MISSING="true"
    fi
  fi
fi

SOURCE_VERIFICATION_PATH=""
SOURCE_VERIFIED_AT_COMMIT=""
SOURCE_FAIL_IDS=""
SOURCE_FAIL_ROW_COUNT=0
ROUND_STARTED_AT_COMMIT=""
ROUND_STARTED_AFTER_SOURCE="true"
ROUND_ACTUAL_DIFF_PATHS=""
ROUND_ACTUAL_DIFF_PATHS_AVAILABLE="false"
ROUND_ACTUAL_DIFF_PATHS_CANONICAL=""
ROUND_WORKTREE_PATHS_CANONICAL=""
ROUND_IGNORED_WORKTREE_PATHS_CANONICAL=""
ROUND_INPUT_MODE="none"
ROUND_KNOWN_ISSUE_BACKLOG_PATH=""
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  _qa_remediation_state=$(bash "$SCRIPT_DIR/qa-remediation-state.sh" get "$PHASE_DIR" 2>/dev/null || true)
  SOURCE_VERIFICATION_PATH=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^source_verification_path=/{print $2; exit}')
  ROUND_STARTED_AT_COMMIT=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^round_started_at_commit=/{print $2; exit}')
  ROUND_INPUT_MODE=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^input_mode=/{print $2; exit}')
  ROUND_KNOWN_ISSUE_BACKLOG_PATH=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^known_issues_path=/{print $2; exit}')
  if [ -z "$SOURCE_VERIFICATION_PATH" ] || [ ! -r "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="true"
  fi
  if [ "${ROUND_INPUT_MODE:-none}" = "known-issues" ] && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi
  if [ "${_gate_stage:-none}" = "done" ] && [ "${ROUND_INPUT_MODE:-none}" = "none" ] && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi
  if [ -n "$SOURCE_VERIFICATION_PATH" ] && [ -r "$SOURCE_VERIFICATION_PATH" ]; then
    SOURCE_VERIFIED_AT_COMMIT=$(extract_verified_at_commit "$SOURCE_VERIFICATION_PATH")
    SOURCE_FAIL_IDS=$(extract_fail_ids_from_verification "$SOURCE_VERIFICATION_PATH")
    SOURCE_FAIL_ROW_COUNT=$(count_fail_rows_in_verification "$SOURCE_VERIFICATION_PATH")
  fi
  if [ -n "$SOURCE_VERIFIED_AT_COMMIT" ] && [ -n "$ROUND_STARTED_AT_COMMIT" ] && ! commit_is_ancestor_or_same "$GIT_ROOT" "$SOURCE_VERIFIED_AT_COMMIT" "$ROUND_STARTED_AT_COMMIT"; then
    ROUND_STARTED_AFTER_SOURCE="false"
  fi
  if [ -n "$GIT_ROOT" ] && [ -n "$ROUND_STARTED_AT_COMMIT" ] && git -C "$GIT_ROOT" cat-file -e "${ROUND_STARTED_AT_COMMIT}^{commit}" 2>/dev/null; then
    ROUND_ACTUAL_DIFF_PATHS_AVAILABLE="true"
    ROUND_ACTUAL_DIFF_PATHS=$(git_diff_paths_since_commit "$GIT_ROOT" "$ROUND_STARTED_AT_COMMIT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
    ROUND_ACTUAL_DIFF_PATHS_CANONICAL=$(printf '%s\n' "$ROUND_ACTUAL_DIFF_PATHS" | canonicalize_recorded_paths "$PHASE_DIR")
    ROUND_WORKTREE_PATHS_CANONICAL=$(git_current_worktree_paths "$GIT_ROOT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u) | canonicalize_recorded_paths "$PHASE_DIR")
    ROUND_IGNORED_WORKTREE_PATHS_CANONICAL=$(git_ignored_metadata_worktree_paths "$GIT_ROOT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u) | canonicalize_recorded_paths "$PHASE_DIR")
  fi
fi

# Metadata-only round detection — if remediation round modified only
# .vbw-planning/ files (no production code), phase-level deviations
# are still unresolved and the override must fire.
METADATA_ONLY_ROUND="false"
ROUND_SUMMARY_MISSING="false"
ROUND_PLAN_MISSING="false"
ROUND_CHANGE_EVIDENCE_UNAVAILABLE="false"
ROUND_CHANGE_EVIDENCE_EMPTY="false"
ROUND_IGNORED_EVIDENCE_USED="false"
ROUND_SUMMARY_NONTERMINAL="false"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  # Scan round SUMMARY.md files_modified for non-metadata paths. When
  # files_modified is absent (older summaries / partial installs), fall back to
  # commit_hashes only when they can be proven to belong to this round's history
  # after the round-start anchor and, when available, the source verification's
  # verified_at_commit.
  _mo_has_code_changes="false"
  _mo_found_summary="false"
  _mo_all_recorded_paths=""
  _mo_effective_files=""
  while IFS= read -r _mo_summary; do
    [ -f "$_mo_summary" ] || continue
    _mo_found_summary="true"
    _mo_status=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }
    ' "$_mo_summary" 2>/dev/null)
    case "${_mo_status:-}" in
      complete|completed|partial|failed) ;;
      *) ROUND_SUMMARY_NONTERMINAL="true" ;;
    esac
    _mo_files=$(extract_frontmatter_array_items "$_mo_summary" files_modified)
    _mo_recorded_files=$(printf '%s\n' "$_mo_files" | canonicalize_recorded_paths "$PHASE_DIR")
    _mo_commit_hashes=$(extract_frontmatter_array_items "$_mo_summary" commit_hashes)
    _mo_commits=$(printf '%s\n' "$_mo_commit_hashes" | awk 'NF { count++ } END { print count + 0 }')
    _mo_commits="${_mo_commits:-0}"
    if [ -z "$_mo_files" ] && [ "$_mo_commits" -eq 0 ] 2>/dev/null; then
      ROUND_CHANGE_EVIDENCE_EMPTY="true"
    fi
    if [ -n "$_mo_files" ]; then
      if [ -z "$_mo_recorded_files" ]; then
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      elif [ -n "$GIT_ROOT" ]; then
        if [ "$ROUND_STARTED_AFTER_SOURCE" != "true" ] || [ "$ROUND_ACTUAL_DIFF_PATHS_AVAILABLE" != "true" ]; then
          ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
          break
        fi
        _mo_effective_files=$(resolve_corroborated_recorded_paths "$PHASE_DIR" "$_mo_recorded_files" "$ROUND_ACTUAL_DIFF_PATHS_CANONICAL" "$ROUND_WORKTREE_PATHS_CANONICAL" "$ROUND_IGNORED_WORKTREE_PATHS_CANONICAL")
        if [ -z "$_mo_effective_files" ] || ! recorded_paths_are_fully_corroborated "$_mo_recorded_files" "$_mo_effective_files"; then
          ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
          break
        fi
        # Detect whether gitignored-metadata evidence was needed for corroboration
        if [ "$ROUND_IGNORED_EVIDENCE_USED" != "true" ] && [ -n "$ROUND_IGNORED_WORKTREE_PATHS_CANONICAL" ]; then
          _mo_without_ignored=$(resolve_corroborated_recorded_paths "$PHASE_DIR" "$_mo_recorded_files" "$ROUND_ACTUAL_DIFF_PATHS_CANONICAL" "$ROUND_WORKTREE_PATHS_CANONICAL" "")
          if ! recorded_paths_are_fully_corroborated "$_mo_recorded_files" "$_mo_without_ignored"; then
            ROUND_IGNORED_EVIDENCE_USED="true"
          fi
        fi
      else
        _mo_effective_files="$_mo_recorded_files"
      fi
      _mo_all_recorded_paths=$(printf '%s\n%s\n' "${_mo_all_recorded_paths:-}" "$_mo_effective_files")
      if paths_include_non_metadata "$PHASE_DIR" <<< "$_mo_effective_files"; then
        _mo_has_code_changes="true"
      fi
    elif [ "$_mo_commits" -gt 0 ] 2>/dev/null; then
      if ! commit_hashes_resolve_cleanly "$GIT_ROOT" "$_mo_commit_hashes" \
        || [ "$ROUND_STARTED_AFTER_SOURCE" != "true" ] \
        || ! commit_hashes_are_round_local "$GIT_ROOT" "$ROUND_STARTED_AT_COMMIT" "$_mo_commit_hashes"; then
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      fi
      _mo_commit_files="$(commit_hashes_to_changed_files "$GIT_ROOT" "$_mo_commit_hashes" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))"
      if [ -n "$_mo_commit_files" ]; then
        _mo_all_recorded_paths=$(printf '%s\n%s\n' "${_mo_all_recorded_paths:-}" "$_mo_commit_files")
        if paths_include_non_metadata "$PHASE_DIR" <<< "$_mo_commit_files"; then
          _mo_has_code_changes="true"
        fi
      else
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      fi
    fi
    [ "$_mo_has_code_changes" = "true" ] && break
  done < <(find "$SUMMARY_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
  # Only flag metadata-only when a round SUMMARY.md exists — if no summary was
  # found, the remediation round is structurally incomplete and PASS must not
  # proceed without the artifact that carries change evidence.
  if [ "$_mo_found_summary" = "false" ]; then
    ROUND_SUMMARY_MISSING="true"
  elif [ "$_mo_has_code_changes" = "false" ]; then
    METADATA_ONLY_ROUND="true"
  fi
fi

# Plan coverage — count PLAN.md files and plans_verified entries
PLAN_COUNT=0
while IFS= read -r plan_file; do
  [ -f "$plan_file" ] || continue
  PLAN_COUNT=$((PLAN_COUNT + 1))
done < <(find "$PLAN_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))

# Parse plans_verified from VERIFICATION.md frontmatter (YAML array)
PLANS_VERIFIED_COUNT=$(extract_frontmatter_array_items "$VERIF_PATH" plans_verified | awk '
  {
    if (!seen[$0]++) count++
  }
  END { print count + 0 }
' 2>/dev/null)
PLANS_VERIFIED_COUNT="${PLANS_VERIFIED_COUNT:-0}"

if [ "$IN_REMEDIATION" = "true" ] && [ "$PLAN_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$PLAN_COUNT" -eq 0 ] 2>/dev/null; then
  ROUND_PLAN_MISSING="true"
fi

ROUND_ALL_RECORDED_PATHS=$(printf '%s\n' "${_mo_all_recorded_paths:-}" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
ROUND_CLASSIFICATION_TYPES=""
ROUND_CLASSIFICATION_IDS=""
ROUND_CLASSIFICATION_TYPE_COUNT=0
ROUND_CLASSIFICATION_ID_COUNT=0
ROUND_CODE_FIX_COUNT=0
ROUND_PLAN_AMENDMENT_COUNT=0
ROUND_PLAN_AMENDMENT_SOURCE_PLANS=""
ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT=0
ROUND_CLASSIFICATIONS_VALID=true
ROUND_KNOWN_ISSUE_INPUTS_JSON='[]'
ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON='[]'
ROUND_KNOWN_ISSUE_OUTCOMES_JSON='[]'
ROUND_CARRIED_KNOWN_ISSUES_JSON='[]'
ROUND_KNOWN_ISSUE_INPUT_COUNT=0
ROUND_KNOWN_ISSUE_RESOLUTION_COUNT=0
ROUND_KNOWN_ISSUE_OUTCOME_COUNT=0
ROUND_CARRIED_KNOWN_ISSUE_COUNT=0
ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED="false"
ROUND_KNOWN_ISSUES_VALID=true
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  ROUND_CLASSIFICATION_TYPES=$(collect_fail_classification_types_in_dir "$PLAN_SCOPE_DIR")
  ROUND_CLASSIFICATION_IDS=$(collect_fail_classification_ids_in_dir "$PLAN_SCOPE_DIR" | (sort -u 2>/dev/null || sort -u))
  ROUND_CLASSIFICATION_TYPE_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk 'NF { count++ } END { print count + 0 }')
  ROUND_CLASSIFICATION_ID_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_IDS" | awk 'NF { count++ } END { print count + 0 }')
  ROUND_CODE_FIX_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk '$0 == "code-fix" { count++ } END { print count + 0 }')
  ROUND_PLAN_AMENDMENT_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk '$0 == "plan-amendment" { count++ } END { print count + 0 }')
  ROUND_PLAN_AMENDMENT_SOURCE_PLANS=$(collect_fail_classification_source_plans_in_dir "$PLAN_SCOPE_DIR")
  ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT=$(printf '%s\n' "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" | awk 'NF { count++ } END { print count + 0 }')

  if [ "$ROUND_CLASSIFICATION_ID_COUNT" -ne "$ROUND_CLASSIFICATION_TYPE_COUNT" ] 2>/dev/null; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -gt 0 ] 2>/dev/null && ! fail_classification_types_are_valid <<< "$ROUND_CLASSIFICATION_TYPES"; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$METADATA_ONLY_ROUND" = "true" ] && [ "$SOURCE_FAIL_ROW_COUNT" -gt 0 ] 2>/dev/null && [ "$ROUND_CLASSIFICATION_ID_COUNT" -eq 0 ] 2>/dev/null; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$SOURCE_FAIL_ROW_COUNT" -gt 0 ] 2>/dev/null && {
    [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -ne "$SOURCE_FAIL_ROW_COUNT" ] 2>/dev/null \
      || ! classification_ids_cover_source_fail_ids "$SOURCE_FAIL_IDS" "$ROUND_CLASSIFICATION_IDS";
  }; then
    ROUND_CLASSIFICATIONS_VALID=false
  fi
  if [ -z "$GIT_ROOT" ] && { [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null || [ "$ROUND_PLAN_AMENDMENT_COUNT" -gt 0 ] 2>/dev/null; }; then
    ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
  fi

  ROUND_KNOWN_ISSUE_INPUTS_JSON=$(collect_frontmatter_json_object_array_in_dir "$PLAN_SCOPE_DIR" plan known_issues_input issue)
  ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON=$(collect_frontmatter_json_object_array_in_dir "$PLAN_SCOPE_DIR" plan known_issue_resolutions resolution)
  ROUND_KNOWN_ISSUE_OUTCOMES_JSON=$(collect_frontmatter_json_object_array_in_dir "$SUMMARY_SCOPE_DIR" summary known_issue_outcomes outcome)
  ROUND_CARRIED_KNOWN_ISSUES_JSON=$(load_known_issue_registry_json "$ROUND_KNOWN_ISSUE_BACKLOG_PATH")
  ROUND_KNOWN_ISSUE_INPUT_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_INPUTS_JSON")
  ROUND_KNOWN_ISSUE_RESOLUTION_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON")
  ROUND_KNOWN_ISSUE_OUTCOME_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON")
  ROUND_CARRIED_KNOWN_ISSUE_COUNT=$(json_object_array_length "$ROUND_CARRIED_KNOWN_ISSUES_JSON")

  if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_KNOWN_ISSUE_RESOLUTION_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_CARRIED_KNOWN_ISSUE_COUNT" -gt 0 ] 2>/dev/null \
    || [ "${ROUND_INPUT_MODE:-none}" = "known-issues" ] \
    || [ "${ROUND_INPUT_MODE:-none}" = "both" ]; then
    ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED="true"
  fi

  if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ]; then
    if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -eq 0 ] 2>/dev/null; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif [ "$ROUND_CARRIED_KNOWN_ISSUE_COUNT" -gt 0 ] 2>/dev/null && ! json_object_array_covers_full_issue_objects "$ROUND_CARRIED_KNOWN_ISSUES_JSON" "$ROUND_KNOWN_ISSUE_INPUTS_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_covers_full_issue_objects "$ROUND_KNOWN_ISSUE_INPUTS_JSON" "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_covers_full_issue_objects "$ROUND_KNOWN_ISSUE_INPUTS_JSON" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_dispositions_match "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" && [ "$KNOWN_ISSUES_COUNT" -eq 0 ] 2>/dev/null; then
      ROUND_KNOWN_ISSUES_VALID=false
    fi
  fi

  if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -gt 0 ] 2>/dev/null && [ "$SOURCE_FAIL_ROW_COUNT" -eq 0 ] 2>/dev/null && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi
fi

# Output diagnostic fields
echo "qa_gate_writer=${WRITER:-missing}"
echo "qa_gate_result=${RESULT:-missing}"
echo "qa_gate_fail_count=$FAIL_COUNT"
echo "qa_gate_deviation_count=$DEVIATION_COUNT"
echo "qa_gate_known_issue_count=$KNOWN_ISSUES_COUNT"
echo "qa_gate_plan_count=$PLAN_COUNT"
echo "qa_gate_plans_verified_count=$PLANS_VERIFIED_COUNT"
if [ "$ROUND_IGNORED_EVIDENCE_USED" = "true" ]; then
  echo "qa_gate_planning_ignored_evidence=true"
fi

# 3. Writer provenance check
if [ -z "$WRITER" ] || [ "$WRITER" != "write-verification.sh" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 4. Result field empty
if [ -z "$RESULT" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 5-7. Route based on result + fail count + deviation cross-check + plan coverage + metadata-only
case "$RESULT" in
  PASS)
    if [ "$FAIL_COUNT" -gt 0 ] 2>/dev/null; then
      # 6. PASS with FAIL rows → defense-in-depth override
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SUMMARY_NONTERMINAL" = "true" ]; then
      echo "qa_gate_round_summary_nonterminal=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SOURCE_VERIFICATION_MISSING" = "true" ]; then
      echo "qa_gate_source_verification_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SUMMARY_MISSING" = "true" ]; then
      echo "qa_gate_round_summary_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_PLAN_MISSING" = "true" ]; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_CHANGE_EVIDENCE_UNAVAILABLE" = "true" ]; then
      echo "qa_gate_round_change_evidence_unavailable=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_CHANGE_EVIDENCE_EMPTY" = "true" ]; then
      echo "qa_gate_round_change_evidence_empty=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] \
      && [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
      && [ "$ROUND_KNOWN_ISSUES_VALID" != "true" ]; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$ROUND_CLASSIFICATIONS_VALID" != "true" ]; then
      if [ "$METADATA_ONLY_ROUND" = "true" ]; then
        PHASE_DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR")
        echo "qa_gate_metadata_only_override=true"
        echo "qa_gate_phase_deviation_count=$PHASE_DEVIATION_COUNT"
      fi
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$METADATA_ONLY_ROUND" != "true" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null && ! paths_include_code_fix_evidence "$PHASE_DIR" <<< "$ROUND_ALL_RECORDED_PATHS"; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$ROUND_PLAN_AMENDMENT_COUNT" -gt 0 ] 2>/dev/null && {
      [ "$ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT" -ne "$ROUND_PLAN_AMENDMENT_COUNT" ] 2>/dev/null \
        || ! plan_amendment_source_plans_are_valid "$PHASE_DIR" <<< "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" \
        || ! paths_cover_required_original_plan_artifacts "$PHASE_DIR" "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" <<< "$ROUND_ALL_RECORDED_PATHS";
    }; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$DEVIATION_COUNT" -gt 0 ] && { [ "$IN_REMEDIATION" = "false" ] || [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; }; then
      # 5a. PASS but deviations exist without FAIL checks → QA rationalized deviations.
      # During remediation, phase-root SUMMARY.md deviations are historical and must
      # not override a fresh PASS. Current-round SUMMARY.md deviations are still real
      # and must be reflected as FAIL checks, so scoped round summaries keep the override.
      echo "qa_gate_deviation_override=true"
      # Also check plan coverage so both diagnostics surface simultaneously
      if [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      fi
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$METADATA_ONLY_ROUND" = "true" ]; then
      # 5c. Remediation round made no implementation/config changes — only
      # metadata/planning/documentation updates. Re-check phase-level deviations.
      # Metadata-only rounds are invalid when they still claim a code-fix path.
      # Pure plan-amendment rounds can resolve cleanly when the original plan was
      # actually updated. Pure process-exception rounds can resolve cleanly only
      # when the recorded evidence includes planning/remediation artifacts rather
      # than delivered docs/README changes alone. Semantic correctness of a
      # process-exception (i.e. whether it is truly non-fixable) is still enforced
      # by remediation QA re-verifying the original FAILs; this deterministic gate
      # only validates structural evidence.
      PHASE_DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR")
      if [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
        echo "qa_gate_metadata_only_override=true"
        echo "qa_gate_phase_deviation_count=$PHASE_DEVIATION_COUNT"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$ROUND_PLAN_AMENDMENT_COUNT" -eq 0 ] 2>/dev/null \
        && [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -gt 0 ] 2>/dev/null \
        && ! paths_include_process_exception_evidence "$PHASE_DIR" <<< "$ROUND_ALL_RECORDED_PATHS"; then
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
        echo "qa_gate_routing=QA_RERUN_REQUIRED"
      elif [ "$KNOWN_ISSUES_STATUS" = "present" ] && [ "$KNOWN_ISSUES_COUNT" -gt 0 ] 2>/dev/null; then
        # Metadata-only round claims clean, but known issues exist in registry.
        # Apply the same coverage guard as the non-metadata-only known-issues path:
        # outcomes must cover every live registry entry, not just the carried snapshot.
        _live_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
        if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
           && [ "$ROUND_KNOWN_ISSUES_VALID" = "true" ] \
           && [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
           && ! json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" \
           && json_object_array_covers_full_issue_objects "$_live_registry_json" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
          echo "qa_gate_known_issues_all_addressed=true"
          echo "qa_gate_routing=PROCEED_TO_UAT"
        else
          echo "qa_gate_known_issues_override=true"
          echo "qa_gate_routing=REMEDIATION_REQUIRED"
        fi
      else
        echo "qa_gate_routing=PROCEED_TO_UAT"
      fi
    elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
      # 5b. PASS but incomplete plan coverage → QA skipped some plans
      echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$KNOWN_ISSUES_STATUS" = "malformed" ]; then
      echo "qa_gate_known_issues_override=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$KNOWN_ISSUES_STATUS" = "present" ] && [ "$KNOWN_ISSUES_COUNT" -gt 0 ] 2>/dev/null; then
      # Known issues exist in the registry. If this remediation round properly
      # addressed all of them (contract valid, outcomes recorded, none unresolved,
      # AND outcomes cover every live registry entry — not just carried snapshot),
      # allow proceeding rather than blocking on stale registry entries.
      _live_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
      if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
         && [ "$ROUND_KNOWN_ISSUES_VALID" = "true" ] \
         && [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
         && ! json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" \
         && json_object_array_covers_full_issue_objects "$_live_registry_json" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
        echo "qa_gate_known_issues_all_addressed=true"
        echo "qa_gate_routing=PROCEED_TO_UAT"
      else
        echo "qa_gate_known_issues_override=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      fi
    else
      # 5. Clean PASS
      echo "qa_gate_routing=PROCEED_TO_UAT"
    fi
    ;;
  FAIL|PARTIAL)
    # 7. Explicit failure
    echo "qa_gate_routing=REMEDIATION_REQUIRED"
    ;;
  *)
    # Unknown result value — treat as untrustworthy
    echo "qa_gate_routing=QA_RERUN_REQUIRED"
    ;;
esac

exit 0
