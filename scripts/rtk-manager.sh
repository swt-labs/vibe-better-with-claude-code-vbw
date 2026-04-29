#!/usr/bin/env bash
set -euo pipefail

# rtk-manager.sh — Explicit, opt-in RTK management for VBW.
#
# Default status is intentionally read-only and offline. Network access is
# limited to explicit install/update/check-updates flows. Mutating operations
# require --yes or --dry-run so VBW never changes global RTK/Claude Code state
# as an incidental side effect of status, doctor, SessionStart, or normal use.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=resolve-claude-dir.sh
. "$SCRIPT_DIR/resolve-claude-dir.sh"

RTK_REPO_API="${RTK_REPO_API:-https://api.github.com/repos/rtk-ai/rtk/releases/latest}"
VBW_RTK_DIR="${VBW_RTK_DIR:-$CLAUDE_DIR/vbw}"
RTK_RECEIPT_FILE="${RTK_RECEIPT_FILE:-$VBW_RTK_DIR/rtk-install.json}"
RTK_LATEST_CACHE="${RTK_LATEST_CACHE:-$VBW_RTK_DIR/rtk-latest-release.json}"
RTK_PROOF_FILE="${RTK_PROOF_FILE:-$VBW_RTK_DIR/rtk-compatibility-proof.json}"
RTK_PENDING_SMOKE_FILE="${RTK_PENDING_SMOKE_FILE:-$VBW_RTK_DIR/rtk-compatibility-smoke-pending.json}"
RTK_LAST_SMOKE_FAILURE_FILE="${RTK_LAST_SMOKE_FAILURE_FILE:-$VBW_RTK_DIR/rtk-compatibility-smoke-last-failure.json}"
RTK_BACKUP_DIR="${RTK_BACKUP_DIR:-$VBW_RTK_DIR/backups}"
RTK_SETTINGS_JSON="${RTK_SETTINGS_JSON:-$CLAUDE_DIR/settings.json}"
RTK_GLOBAL_MD="${RTK_GLOBAL_MD:-$CLAUDE_DIR/RTK.md}"
RTK_CLAUDE_MD="${RTK_CLAUDE_MD:-$CLAUDE_DIR/CLAUDE.md}"
RTK_INSTALL_DIR_DEFAULT="${RTK_INSTALL_DIR:-$HOME/.local/bin}"
RTK_LEGACY_CLAUDE_DIR="${RTK_LEGACY_CLAUDE_DIR:-${HOME}/.claude}"
RTK_CURL_MAX_TIME="${RTK_CURL_MAX_TIME:-15}"
RTK_TEMP_DIR=""

cleanup_temp_dir() {
  [ -n "${RTK_TEMP_DIR:-}" ] || return 0
  rm -rf "$RTK_TEMP_DIR" 2>/dev/null || true
}

usage() {
  cat <<'EOF'
Usage: rtk-manager.sh <command> [options]

Commands:
  status --json [--check-updates] [--stats]
  doctor-json
  install [--dry-run] [--yes] [--allow-missing-checksum]
  update [--dry-run] [--yes] [--allow-missing-checksum]
  init [--dry-run] [--yes] [--hook-only]
  verify [--json]
  smoke-start
  smoke-finish
  uninstall [--dry-run] [--yes] [--deactivate-hook]

Mutating commands require --yes. Use --dry-run to inspect planned effects.
Smoke helpers are explicit runtime verification internals used by /vbw:rtk verify.
EOF
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown"
}

die() {
  local code="$1"
  shift
  echo "RTK: $*" >&2
  exit "$code"
}

bool_to_json() {
  if [ "${1:-false}" = "true" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

normalize_version() {
  local value="$1"
  value="${value#v}"
  awk -v s="$value" 'BEGIN { if (match(s, /[0-9]+([.][0-9]+)+/)) print substr(s, RSTART, RLENGTH); }'
}

version_gt() {
  local left right
  left="$(normalize_version "$1")"
  right="$(normalize_version "$2")"
  [ -n "$left" ] && [ -n "$right" ] || return 1
  awk -v a="$left" -v b="$right" '
    BEGIN {
      split(a, av, "."); split(b, bv, ".");
      for (i = 1; i <= 4; i++) {
        ai = (av[i] == "" ? 0 : av[i] + 0);
        bi = (bv[i] == "" ? 0 : bv[i] + 0);
        if (ai > bi) exit 0;
        if (ai < bi) exit 1;
      }
      exit 1;
    }
  '
}

path_contains_dir() {
  local dir="$1"
  case ":${PATH:-}:" in
    *":$dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

canonical_executable_path() {
  local path="$1" dir base dir_real
  [ -n "$path" ] || return 0
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if dir_real="$(cd "$dir" 2>/dev/null && pwd -P)"; then
    printf '%s/%s\n' "$dir_real" "$base"
  else
    printf '%s\n' "$path"
  fi
}

same_executable_path() {
  local left="$1" right="$2" left_real right_real
  [ -n "$left" ] && [ -n "$right" ] || return 1
  left_real="$(canonical_executable_path "$left")"
  right_real="$(canonical_executable_path "$right")"
  [ "$left_real" = "$right_real" ]
}

command_path() {
  command -v "$1" 2>/dev/null || true
}

platform_os() {
  uname -s 2>/dev/null || echo unknown
}

preferred_install_method_detect() {
  if [ "$(platform_os)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    echo "homebrew"
  else
    echo "github-release"
  fi
}

rtk_config_path() {
  case "$(platform_os)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/rtk/config.toml"
      ;;
    *)
      if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        printf '%s\n' "$XDG_CONFIG_HOME/rtk/config.toml"
      else
        printf '%s\n' "$HOME/.config/rtk/config.toml"
      fi
      ;;
  esac
}

rtk_config_state() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "missing"
  elif [ ! -s "$path" ]; then
    echo "config_error"
  else
    echo "present"
  fi
}

rtk_path_from_receipt() {
  if [ -f "$RTK_RECEIPT_FILE" ] && jq empty "$RTK_RECEIPT_FILE" >/dev/null 2>&1; then
    jq -r '.binary_path // empty' "$RTK_RECEIPT_FILE" 2>/dev/null || true
  fi
}

rtk_path_detect() {
  local path
  path="$(command_path rtk)"
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
  fi
}

shell_first_word_unquote() {
  local input="$1" len i ch next quote="" started=false word=""
  len=${#input}
  i=0
  while [ "$i" -lt "$len" ]; do
    ch="${input:i:1}"
    if [ -z "$quote" ]; then
      case "$ch" in
        [[:space:]])
          if [ "$started" = "true" ]; then
            break
          fi
          ;;
        "'")
          started=true
          quote="single"
          ;;
        '"')
          started=true
          quote="double"
          ;;
        "\\")
          started=true
          if [ $((i + 1)) -lt "$len" ]; then
            next="${input:i+1:1}"
            word+="$next"
            i=$((i + 1))
          else
            word+="$ch"
          fi
          ;;
        *)
          started=true
          word+="$ch"
          ;;
      esac
    elif [ "$quote" = "single" ]; then
      if [ "$ch" = "'" ]; then
        quote=""
      else
        word+="$ch"
      fi
    else
      if [ "$ch" = '"' ]; then
        quote=""
      elif [ "$ch" = "\\" ] && [ $((i + 1)) -lt "$len" ]; then
        next="${input:i+1:1}"
        word+="$next"
        i=$((i + 1))
      else
        word+="$ch"
      fi
    fi
    i=$((i + 1))
  done
  [ -z "$quote" ] || return 1
  [ "$started" = "true" ] || return 1
  printf '%s\n' "$word"
}

rtk_version_detect() {
  local path="$1" out
  [ -n "$path" ] || return 0
  out="$("$path" --version 2>/dev/null || true)"
  normalize_version "$out"
}

rtk_path_from_hook_command() {
  local command="$1" executable=""
  [ -n "$command" ] || return 0
  executable="$(shell_first_word_unquote "$command" 2>/dev/null || true)"
  case "$executable" in
    rtk) command_path rtk ;;
    */rtk) if [ -x "$executable" ]; then printf '%s\n' "$executable"; fi ;;
    *) return 0 ;;
  esac
}

receipt_managed() {
  [ -f "$RTK_RECEIPT_FILE" ] || return 1
  jq -e '.manager == "vbw"' "$RTK_RECEIPT_FILE" >/dev/null 2>&1
}

receipt_field() {
  local field="$1"
  [ -f "$RTK_RECEIPT_FILE" ] || return 0
  jq -r --arg field "$field" '.[$field] // empty' "$RTK_RECEIPT_FILE" 2>/dev/null || true
}

settings_valid() {
  [ -f "$RTK_SETTINGS_JSON" ] || return 0
  jq empty "$RTK_SETTINGS_JSON" >/dev/null 2>&1
}

settings_hook_command() {
  [ -f "$RTK_SETTINGS_JSON" ] || return 0
  jq -r '
    [
      .hooks.PreToolUse[]? as $group
      | ($group.matcher // "") as $matcher
      | $group.hooks[]?
      | (.command // "") as $command
      | ($command | gsub("[\"'\'' ]"; "")) as $match_command
      | select($match_command | test("(^|/)rtkhookclaude($|[;])|rtk-rewrite[.]sh"))
      | {matcher: $matcher, command: (.command // "")}
    ][0].command // ""
  ' "$RTK_SETTINGS_JSON" 2>/dev/null || true
}

settings_hook_matcher() {
  [ -f "$RTK_SETTINGS_JSON" ] || return 0
  jq -r '
    [
      .hooks.PreToolUse[]? as $group
      | ($group.matcher // "") as $matcher
      | $group.hooks[]?
      | (.command // "") as $command
      | ($command | gsub("[\"'\'' ]"; "")) as $match_command
      | select($match_command | test("(^|/)rtkhookclaude($|[;])|rtk-rewrite[.]sh"))
      | {matcher: $matcher, command: (.command // "")}
    ][0].matcher // ""
  ' "$RTK_SETTINGS_JSON" 2>/dev/null || true
}

settings_bash_hook_count() {
  [ -f "$RTK_SETTINGS_JSON" ] || { echo 0; return 0; }
  jq -r '
    [
      .hooks.PreToolUse[]?
      | select((.matcher // "") == "Bash" or (.matcher // "") == "")
      | .hooks[]?
      | select((.type // "command") == "command" and (.command // "") != "")
    ] | length
  ' "$RTK_SETTINGS_JSON" 2>/dev/null || echo 0
}

legacy_hook_present() {
  [ -f "$CLAUDE_DIR/hooks/rtk-rewrite.sh" ] || [ -f "$RTK_LEGACY_CLAUDE_DIR/hooks/rtk-rewrite.sh" ]
}

global_claude_ref_present() {
  [ -f "$RTK_CLAUDE_MD" ] || return 1
  grep -Fq '@RTK.md' "$RTK_CLAUDE_MD" 2>/dev/null
}

project_local_present() {
  [ -d ".rtk" ] || [ -f ".rtk/filters.toml" ]
}

vbw_bash_hook_present() {
  local hooks_json="$SCRIPT_DIR/../hooks/hooks.json"
  [ -f "$hooks_json" ] || return 1
  jq -e '
    .. | objects
    | select((.matcher? // "") == "Bash" or ((.command? // "") | contains("bash-guard.sh")))
  ' "$hooks_json" >/dev/null 2>&1
}

checksum_tool() {
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum"
  elif command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  fi
}

sha256_file() {
  local file="$1" tool
  tool="$(checksum_tool)"
  [ -n "$tool" ] || die 1 "no SHA-256 tool found (need shasum or sha256sum)"
  case "$tool" in
    shasum) shasum -a 256 "$file" | awk '{print $1}' ;;
    sha256sum) sha256sum "$file" | awk '{print $1}' ;;
  esac
}

sha256_text() {
  local tool
  tool="$(checksum_tool)"
  [ -n "$tool" ] || return 0
  case "$tool" in
    shasum) shasum -a 256 | awk '{print $1}' ;;
    sha256sum) sha256sum | awk '{print $1}' ;;
  esac
}

os_arch_target() {
  local os arch
  os="$(uname -s 2>/dev/null || echo unknown)"
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$arch" in
    arm64|aarch64) arch="aarch64" ;;
    x86_64|amd64) arch="x86_64" ;;
  esac
  case "$os:$arch" in
    Darwin:aarch64) echo "aarch64-apple-darwin" ;;
    Darwin:x86_64) echo "x86_64-apple-darwin" ;;
    Linux:aarch64) echo "aarch64-unknown-linux-gnu" ;;
    Linux:x86_64) echo "x86_64-unknown-linux-musl" ;;
    *) echo "" ;;
  esac
}

curl_bounded() {
  curl -fsSL --max-time "$RTK_CURL_MAX_TIME" "$@"
}

curl_json() {
  local url="$1"
  curl_bounded "$url"
}

fetch_latest_release() {
  local release_json tag version target asset_name asset_url checksums_url checked
  release_json="$(curl_json "$RTK_REPO_API")" || die 1 "failed to query latest RTK release metadata"
  tag="$(printf '%s' "$release_json" | jq -r '.tag_name // .tagName // empty')"
  version="$(normalize_version "$tag")"
  target="$(os_arch_target)"
  [ -n "$target" ] || die 1 "unsupported platform for VBW-managed RTK release install"
  asset_name="$(printf '%s' "$release_json" | jq -r --arg target "$target" '[.assets[]? | select((.name | contains($target)) and (.name | endswith(".tar.gz")))][0].name // empty')"
  asset_url="$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" '[.assets[]? | select(.name == $name)][0].browser_download_url // empty')"
  checksums_url="$(printf '%s' "$release_json" | jq -r '[.assets[]? | select(.name == "checksums.txt")][0].browser_download_url // empty')"
  [ -n "$tag" ] && [ -n "$version" ] || die 1 "latest RTK release metadata did not include a tag"
  [ -n "$asset_name" ] && [ -n "$asset_url" ] || die 1 "latest RTK release has no asset for target $target"
  checked="$(now_utc)"
  jq -n \
    --arg tag "$tag" \
    --arg version "$version" \
    --arg checked_at "$checked" \
    --arg target "$target" \
    --arg asset_name "$asset_name" \
    --arg asset_url "$asset_url" \
    --arg checksums_url "$checksums_url" \
    '{tag:$tag, version:$version, checked_at:$checked_at, target:$target, asset_name:$asset_name, asset_url:$asset_url, checksums_url:$checksums_url}'
}

cache_latest_release() {
  local metadata="$1" tmp
  mkdir -p "$VBW_RTK_DIR"
  tmp="$(mktemp "$VBW_RTK_DIR/rtk-latest.XXXXXX")"
  printf '%s\n' "$metadata" > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$RTK_LATEST_CACHE"
}

query_latest_release() {
  local metadata
  metadata="$(fetch_latest_release)"
  cache_latest_release "$metadata"
  cat "$RTK_LATEST_CACHE"
}

latest_from_cache() {
  [ -f "$RTK_LATEST_CACHE" ] || return 0
  jq empty "$RTK_LATEST_CACHE" >/dev/null 2>&1 || return 0
  cat "$RTK_LATEST_CACHE"
}

release_metadata() {
  local check_updates="$1" metadata
  if [ "$check_updates" = "true" ]; then
    query_latest_release
    return 0
  fi
  metadata="$(latest_from_cache)"
  [ -n "$metadata" ] && printf '%s\n' "$metadata"
  return 0
}

valid_runtime_smoke_proof() {
  local proof_file="$1" current_version="$2" active_hook_command="$3"
  [ -f "$proof_file" ] || return 1
  [ -n "$current_version" ] || return 1
  [ -n "$active_hook_command" ] || return 1
  jq -e \
    --arg current_version "$current_version" \
    --arg active_hook_command "$active_hook_command" '
      type == "object"
      and (((.proof_type // .type // .source // "") | ascii_downcase) | test("runtime.*smoke|smoke.*runtime|manual.*smoke"))
      and ((.verified == true) or (((.status // .result // .verdict // "") | ascii_downcase) | test("pass|verified")))
      and (((.timestamp // .verified_at // .ts // "") | type) == "string")
      and ((.timestamp // .verified_at // .ts // "") | length > 0)
      and ((.updated_input_verified // .updatedInput_verified // false) == true)
      and ((.rtk_rewrite_observed // .rewrite_observed // false) == true)
      and ((.vbw_bash_guard_verified // .bash_guard_verified // false) == true)
      and (((.rtk_version // "") | type) == "string")
      and ((.rtk_version // "") == $current_version)
      and (((.hook_command // "") | type) == "string")
      and ((.hook_command // "") == $active_hook_command)
      and (
        (((.commands // .smoke_commands // .results // []) | type) == "array" and ((.commands // .smoke_commands // .results // []) | length > 0))
        or ((((.summary // .evidence // "") | type) == "string") and ((.summary // .evidence // "") | length > 0))
      )
    ' "$proof_file" >/dev/null 2>&1
}

rtk_history_snapshot() {
  local rtk_path="$1"
  [ -n "$rtk_path" ] && [ -x "$rtk_path" ] || return 0
  "$rtk_path" gain --history 2>/dev/null || true
}

rtk_history_total() {
  awk '
    match($0, /(Total|total)[^0-9]{0,40}[0-9]+/) {
      part = substr($0, RSTART, RLENGTH)
      if (match(part, /[0-9]+$/)) { print substr(part, RSTART, RLENGTH); exit }
    }
    match($0, /[0-9]+[[:space:]]+(commands|command|entries|entry)/) {
      part = substr($0, RSTART, RLENGTH)
      if (match(part, /^[0-9]+/)) { print substr(part, RSTART, RLENGTH); exit }
    }
    match($0, /(commands|Commands|entries|Entries)[^0-9]{0,40}[0-9]+/) {
      part = substr($0, RSTART, RLENGTH)
      if (match(part, /[0-9]+$/)) { print substr(part, RSTART, RLENGTH); exit }
    }
  '
}

rtk_history_tail() {
  tail -n 40 2>/dev/null || true
}

rtk_history_has_command() {
  local history="$1" command_key="$2"
  case "$command_key" in
    ls)
      printf '%s\n' "$history" | grep -Eq '(^|[^[:alnum:]_/.-])rtk[[:space:]]+ls[[:space:]]+-la[[:space:]]+[.]([^[:alnum:]_/.-]|$)'
      ;;
    status)
      printf '%s\n' "$history" | grep -Eq '(^|[^[:alnum:]_/.-])rtk[[:space:]]+git[[:space:]]+status[[:space:]]+--short([^[:alnum:]_-]|$)'
      ;;
    log)
      printf '%s\n' "$history" | grep -Eq '(^|[^[:alnum:]_/.-])rtk[[:space:]]+git[[:space:]]+log[[:space:]]+(-n[[:space:]]+2|-[0-9A-Za-z]*n[[:space:]]*2)([[:space:]]+--oneline)?([^[:alnum:]_-]|$)'
      ;;
    *)
      return 1
      ;;
  esac
}

write_smoke_failure() {
  local reason="$1" detail="${2:-}" tmp
  mkdir -p "$VBW_RTK_DIR"
  tmp="$(mktemp "$VBW_RTK_DIR/rtk-smoke-failure.XXXXXX")"
  jq -n \
    --arg status "fail" \
    --arg timestamp "$(now_utc)" \
    --arg reason "$reason" \
    --arg detail "$detail" \
    '{status:$status,timestamp:$timestamp,reason:$reason,detail:$detail}' > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$RTK_LAST_SMOKE_FAILURE_FILE"
}

smoke_fail() {
  local code="$1" reason="$2" detail="${3:-}"
  write_smoke_failure "$reason" "$detail" || true
  echo "RTK smoke failed: $reason${detail:+: $detail}" >&2
  exit "$code"
}

smoke_status_preconditions() {
  local payload="$1" field
  for field in rtk_present config_state global_hook_present global_hook_command active_hook_rtk_path active_hook_rtk_version; do
    if ! printf '%s' "$payload" | jq -e --arg field "$field" '.[$field] != null and (.[$field] | tostring | length > 0)' >/dev/null 2>&1; then
      smoke_fail 1 "missing smoke precondition" "$field"
    fi
  done
  printf '%s' "$payload" | jq -e '.rtk_present == true' >/dev/null 2>&1 || smoke_fail 1 "RTK binary missing"
  printf '%s' "$payload" | jq -e '.config_state == "present"' >/dev/null 2>&1 || smoke_fail 1 "RTK config is not present" "run /vbw:rtk install or /vbw:rtk init first"
  printf '%s' "$payload" | jq -e '.global_hook_present == true' >/dev/null 2>&1 || smoke_fail 1 "RTK settings hook inactive"
  local hook_path
  hook_path="$(printf '%s' "$payload" | jq -r '.active_hook_rtk_path // empty')"
  [ -x "$hook_path" ] || smoke_fail 1 "active RTK hook binary is not runnable" "$hook_path"
}

smoke_start() {
  local status_payload hook_path hook_command hook_version history history_total history_tail history_hash tmp
  status_payload="$(status_json false false)"
  smoke_status_preconditions "$status_payload"
  if printf '%s' "$status_payload" | jq -e '.compatibility == "verified" and ((.proof_source // "") != "")' >/dev/null 2>&1; then
    smoke_fail 1 "runtime compatibility already verified" "proof_source=$(printf '%s' "$status_payload" | jq -r '.proof_source')"
  fi
  hook_path="$(printf '%s' "$status_payload" | jq -r '.active_hook_rtk_path')"
  hook_command="$(printf '%s' "$status_payload" | jq -r '.global_hook_command')"
  hook_version="$(printf '%s' "$status_payload" | jq -r '.active_hook_rtk_version')"
  history="$(rtk_history_snapshot "$hook_path")"
  history_total="$(printf '%s\n' "$history" | rtk_history_total || true)"
  history_tail="$(printf '%s\n' "$history" | rtk_history_tail)"
  history_hash="$(printf '%s' "$history_tail" | sha256_text || true)"
  mkdir -p "$VBW_RTK_DIR"
  tmp="$(mktemp "$VBW_RTK_DIR/rtk-smoke-pending.XXXXXX")"
  jq -n \
    --arg proof_type "runtime_smoke_pending" \
    --arg status "pending" \
    --arg timestamp "$(now_utc)" \
    --arg rtk_version "$hook_version" \
    --arg hook_command "$hook_command" \
    --arg active_hook_rtk_path "$hook_path" \
    --arg active_hook_rtk_version "$hook_version" \
    --arg history_before_total "$history_total" \
    --arg history_before_tail "$history_tail" \
    --arg history_before_sha256 "$history_hash" \
    '{
      proof_type:$proof_type,
      status:$status,
      timestamp:$timestamp,
      rtk_version:$rtk_version,
      hook_command:$hook_command,
      active_hook_rtk_path:$active_hook_rtk_path,
      active_hook_rtk_version:$active_hook_rtk_version,
      history_before_total: (if $history_before_total == "" then null else ($history_before_total | tonumber) end),
      history_before_total_available: ($history_before_total != ""),
      history_before_tail:$history_before_tail,
      history_before_sha256:$history_before_sha256,
      expected_unprefixed_commands:["ls -la .","git status --short","git log -n 2 --oneline"]
    }' > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$RTK_PENDING_SMOKE_FILE"
  jq -n --arg status "pending" --arg pending_file "$RTK_PENDING_SMOKE_FILE" --arg rtk_version "$hook_version" --arg hook_command "$hook_command" '{status:$status,pending_file:$pending_file,rtk_version:$rtk_version,hook_command:$hook_command}'
}

verify_bash_guard_smoke() {
  local status
  set +e
  printf '%s\n' '{"tool_input":{"command":"python manage.py flush"}}' | bash "$SCRIPT_DIR/bash-guard.sh" >/dev/null 2>&1
  status=$?
  set -e
  [ "$status" -eq 2 ]
}

write_runtime_smoke_proof() {
  local status_payload="$1" pending_payload="$2" history_after_total="$3" count_evidence="$4" tmp
  local hook_command hook_version
  hook_command="$(printf '%s' "$status_payload" | jq -r '.global_hook_command')"
  hook_version="$(printf '%s' "$status_payload" | jq -r '.active_hook_rtk_version')"
  mkdir -p "$VBW_RTK_DIR"
  tmp="$(mktemp "$VBW_RTK_DIR/rtk-proof.XXXXXX")"
  jq -n \
    --arg proof_type "runtime_smoke" \
    --arg status "pass" \
    --arg timestamp "$(now_utc)" \
    --arg rtk_version "$hook_version" \
    --arg hook_command "$hook_command" \
    --arg compatibility_basis "runtime_smoke_passed" \
    --arg upstream_caveat "anthropics/claude-code#15897" \
    --argjson history_before_total "$(printf '%s' "$pending_payload" | jq '.history_before_total // null')" \
    --arg history_after_total "$history_after_total" \
    --arg count_evidence "$count_evidence" \
    '{
      proof_type:$proof_type,
      status:$status,
      verified:true,
      timestamp:$timestamp,
      rtk_version:$rtk_version,
      hook_command:$hook_command,
      updated_input_verified:true,
      rtk_rewrite_observed:true,
      vbw_bash_guard_verified:true,
      commands:[
        {expected:"ls -la .", observed:"rtk ls -la ."},
        {expected:"git status --short", observed:"rtk git status --short"},
        {expected:"git log -n 2 --oneline", observed:"rtk git log -n 2 --oneline"}
      ],
      history_before_total:$history_before_total,
      history_after_total:(if $history_after_total == "" then null else ($history_after_total | tonumber) end),
      history_count_evidence:$count_evidence,
      compatibility_basis:$compatibility_basis,
      upstream_caveat:$upstream_caveat
    }' > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$RTK_PROOF_FILE"
}

smoke_finish() {
  local pending_payload status_payload hook_path hook_command hook_version pending_hook_command pending_hook_version
  local history history_after_total history_before_total count_evidence
  [ -f "$RTK_PENDING_SMOKE_FILE" ] || smoke_fail 1 "pending smoke file missing" "$RTK_PENDING_SMOKE_FILE"
  jq empty "$RTK_PENDING_SMOKE_FILE" >/dev/null 2>&1 || smoke_fail 1 "pending smoke file is malformed" "$RTK_PENDING_SMOKE_FILE"
  pending_payload="$(cat "$RTK_PENDING_SMOKE_FILE")"
  printf '%s' "$pending_payload" | jq -e '.status == "pending" and .proof_type == "runtime_smoke_pending"' >/dev/null 2>&1 || smoke_fail 1 "pending smoke file has invalid state"
  status_payload="$(status_json false false)"
  smoke_status_preconditions "$status_payload"
  hook_path="$(printf '%s' "$status_payload" | jq -r '.active_hook_rtk_path')"
  hook_command="$(printf '%s' "$status_payload" | jq -r '.global_hook_command')"
  hook_version="$(printf '%s' "$status_payload" | jq -r '.active_hook_rtk_version')"
  pending_hook_command="$(printf '%s' "$pending_payload" | jq -r '.hook_command')"
  pending_hook_version="$(printf '%s' "$pending_payload" | jq -r '.active_hook_rtk_version')"
  [ "$hook_command" = "$pending_hook_command" ] || smoke_fail 1 "RTK hook command changed during smoke" "$pending_hook_command -> $hook_command"
  [ "$hook_version" = "$pending_hook_version" ] || smoke_fail 1 "RTK hook version changed during smoke" "$pending_hook_version -> $hook_version"

  history="$(rtk_history_snapshot "$hook_path")"
  rtk_history_has_command "$history" ls || smoke_fail 1 "missing RTK history evidence" "rtk ls -la ."
  rtk_history_has_command "$history" status || smoke_fail 1 "missing RTK history evidence" "rtk git status --short"
  rtk_history_has_command "$history" log || smoke_fail 1 "missing RTK history evidence" "rtk git log -n 2 --oneline"
  history_after_total="$(printf '%s\n' "$history" | rtk_history_total || true)"
  history_before_total="$(printf '%s' "$pending_payload" | jq -r '.history_before_total // empty')"
  count_evidence="unavailable"
  if [ -n "$history_before_total" ] && [ -n "$history_after_total" ]; then
    if [ $((history_after_total - history_before_total)) -lt 3 ]; then
      smoke_fail 1 "RTK history count did not increase by at least 3" "before=$history_before_total after=$history_after_total"
    fi
    count_evidence="before=$history_before_total after=$history_after_total delta=$((history_after_total - history_before_total))"
  fi
  verify_bash_guard_smoke || smoke_fail 1 "VBW Bash guard smoke verification failed" "expected scripts/bash-guard.sh to block synthetic destructive command with exit 2"
  write_runtime_smoke_proof "$status_payload" "$pending_payload" "$history_after_total" "$count_evidence"
  rm -f "$RTK_PENDING_SMOKE_FILE"
  jq -n --arg status "pass" --arg proof_source "$RTK_PROOF_FILE" --arg history_count_evidence "$count_evidence" '{status:$status,proof_source:$proof_source,history_count_evidence:$history_count_evidence}'
}

status_json() {
  local check_updates="${1:-false}" include_stats="${2:-false}"
  local rtk_path rtk_present rtk_version latest_json latest_version latest_checked_at update_available version_source
  local managed_by_vbw install_receipt receipt_binary binary_install_state can_install preferred_install_method
  local config_path config_present config_state
  local settings_json_valid hook_command hook_matcher global_hook_present global_claude_ref global_rtk_md legacy_hook project_local vbw_hook bash_hook_count multiple_bash updated_input_risk
  local settings_hook_state active_hook_rtk_path active_hook_rtk_version proof_source proof_state compatibility compatibility_basis diagnostic_caveat upstream_issue restart_required summary next_action config_next_action stats_json

  rtk_path="$(rtk_path_detect)"
  rtk_present=false
  [ -n "$rtk_path" ] && rtk_present=true
  rtk_version="$(rtk_version_detect "$rtk_path")"

  latest_json="$(release_metadata "$check_updates")"
  latest_version=""
  latest_checked_at=""
  if [ -n "$latest_json" ]; then
    latest_version="$(printf '%s' "$latest_json" | jq -r '.version // empty' 2>/dev/null || true)"
    latest_checked_at="$(printf '%s' "$latest_json" | jq -r '.checked_at // empty' 2>/dev/null || true)"
  fi
  update_available=false
  if [ -n "$latest_version" ] && [ -n "$rtk_version" ] && version_gt "$latest_version" "$rtk_version"; then
    update_available=true
  fi
  version_source="none"
  [ -n "$latest_version" ] && version_source="explicit-check-or-cache"

  managed_by_vbw=false
  if receipt_managed; then managed_by_vbw=true; fi
  install_receipt=""
  [ -f "$RTK_RECEIPT_FILE" ] && install_receipt="$RTK_RECEIPT_FILE"
  receipt_binary="$(rtk_path_from_receipt)"
  binary_install_state="absent"
  if [ "$rtk_present" = "true" ]; then
    binary_install_state="present"
  elif [ -n "$receipt_binary" ] && [ -x "$receipt_binary" ]; then
    binary_install_state="installed_not_on_path"
  elif [ -n "$receipt_binary" ]; then
    binary_install_state="receipt_missing_binary"
  fi

  preferred_install_method="$(preferred_install_method_detect)"
  can_install=true
  command -v jq >/dev/null 2>&1 || can_install=false
  if [ "$preferred_install_method" = "homebrew" ]; then
    command -v brew >/dev/null 2>&1 || can_install=false
  else
    command -v curl >/dev/null 2>&1 || can_install=false
    [ -n "$(checksum_tool)" ] || can_install=false
  fi

  config_path="$(rtk_config_path)"
  config_state="$(rtk_config_state "$config_path")"
  if [ "$config_state" = "present" ] && [ -n "$rtk_path" ] && ! validate_rtk_config_if_possible "$rtk_path"; then
    config_state="config_error"
  fi
  config_present=false
  [ "$config_state" != "missing" ] && config_present=true
  config_next_action="none"

  settings_json_valid=true
  if ! settings_valid; then settings_json_valid=false; fi
  settings_hook_state="inactive"
  hook_command=""
  hook_matcher=""
  if [ "$settings_json_valid" = "true" ]; then
    hook_command="$(settings_hook_command)"
    hook_matcher="$(settings_hook_matcher)"
  else
    settings_hook_state="unknown"
  fi
  global_claude_ref=false
  if global_claude_ref_present; then global_claude_ref=true; fi
  global_rtk_md=false
  [ -f "$RTK_GLOBAL_MD" ] && global_rtk_md=true
  legacy_hook=false
  if legacy_hook_present; then legacy_hook=true; fi
  project_local=false
  if project_local_present; then project_local=true; fi
  vbw_hook=false
  if vbw_bash_hook_present; then vbw_hook=true; fi
  global_hook_present=false
  if [ -n "$hook_command" ]; then
    global_hook_present=true
    settings_hook_state="active"
  fi
  active_hook_rtk_path=""
  active_hook_rtk_version=""
  if [ -n "$hook_command" ]; then
    active_hook_rtk_path="$(rtk_path_from_hook_command "$hook_command")"
    active_hook_rtk_version="$(rtk_version_detect "$active_hook_rtk_path")"
  fi
  bash_hook_count=0
  if [ "$settings_json_valid" = "true" ]; then bash_hook_count="$(settings_bash_hook_count)"; fi
  multiple_bash=false
  if [ "$global_hook_present" = "true" ] && { [ "$vbw_hook" = "true" ] || [ "${bash_hook_count:-0}" -gt 1 ]; }; then
    multiple_bash=true
  fi
  updated_input_risk=false
  [ "$multiple_bash" = "true" ] && updated_input_risk=true

  proof_source=""
  proof_state="none"
  [ -f "$RTK_PROOF_FILE" ] && proof_state="stale_or_invalid"
  if [ -n "$hook_command" ] && [ -n "$active_hook_rtk_path" ] && valid_runtime_smoke_proof "$RTK_PROOF_FILE" "$active_hook_rtk_version" "$hook_command"; then
    proof_source="$RTK_PROOF_FILE"
    proof_state="valid"
  fi

  compatibility="absent"
  compatibility_basis="absent"
  diagnostic_caveat=""
  upstream_issue=""
  restart_required=false
  if [ "$settings_hook_state" = "unknown" ]; then
    compatibility="settings_unreadable"
  elif [ -n "$proof_source" ] && [ "$global_hook_present" = "true" ]; then
    compatibility="verified"
  elif [ "$global_hook_present" = "true" ] && [ "$updated_input_risk" = "true" ]; then
    compatibility="risk"
  elif [ "$global_hook_present" = "true" ]; then
    compatibility="hook_active_unverified"
  elif [ "$rtk_present" = "true" ]; then
    compatibility="binary_only"
  fi
  case "$compatibility" in
    verified)
      compatibility_basis="runtime_smoke_passed"
      ;;
    risk)
      compatibility_basis="manual_runtime_smoke_required"
      ;;
    hook_active_unverified)
      compatibility_basis="hook_active_without_runtime_proof"
      ;;
    binary_only)
      compatibility_basis="binary_present_hook_inactive"
      ;;
    settings_unreadable)
      compatibility_basis="settings_unreadable"
      ;;
  esac
  if [ "$updated_input_risk" = "true" ]; then
    upstream_issue="anthropics/claude-code#15897"
    diagnostic_caveat="Claude Code issue #15897 reports updatedInput can fail when multiple Bash PreToolUse hooks match; local runtime smoke proof is required before normal PASS."
    if [ "$compatibility" = "verified" ]; then
      diagnostic_caveat="Claude Code issue #15897 remains an upstream diagnostic caveat; local runtime smoke proof verifies this RTK/VBW setup."
    fi
  fi
  if [ "$global_hook_present" = "true" ] && [ -z "$proof_source" ]; then
    restart_required=true
  fi

  case "$compatibility" in
    absent)
      if [ "$binary_install_state" = "installed_not_on_path" ]; then
        summary="RTK binary installed by VBW but not on PATH; add $(dirname "$receipt_binary") to PATH before hook activation"
        next_action="path"
      elif [ "$binary_install_state" = "receipt_missing_binary" ]; then
        summary="VBW RTK receipt exists but binary is missing; run /vbw:rtk install or uninstall/manage"
        next_action="repair"
      else
        summary="RTK not installed; optional: /vbw:rtk install"
        next_action="install"
      fi
      ;;
    settings_unreadable)
      summary="Claude settings unreadable; RTK hook state cannot be determined from ${RTK_SETTINGS_JSON}"
      next_action="repair_settings"
      ;;
    binary_only)
      summary="RTK binary installed; Claude Code hook inactive"
      next_action="init"
      ;;
    hook_active_unverified)
      summary="RTK hook active; runtime compatibility unverified"
      next_action="verify"
      ;;
    risk)
      summary="RTK hook active; multiple Bash PreToolUse hooks make updatedInput compatibility risky"
      next_action="verify"
      ;;
    verified)
      summary="RTK/VBW coexistence verified by runtime smoke proof"
      next_action="status"
      ;;
    *)
      summary="RTK status unknown"
      next_action="status"
      ;;
  esac

  if [ "$rtk_present" = "true" ] || [ "$global_hook_present" = "true" ]; then
    case "$config_state" in
      missing)
        summary="${summary}; RTK config missing at ${config_path}"
        if [ "$rtk_present" = "true" ]; then
          config_next_action="init"
        else
          config_next_action="install"
        fi
        case "$next_action" in
          status|install) next_action="$config_next_action" ;;
        esac
        ;;
      config_error)
        summary="${summary}; RTK config unreadable or empty at ${config_path}"
        if [ "$rtk_present" = "true" ]; then
          config_next_action="init"
        else
          config_next_action="install"
        fi
        case "$next_action" in
          status|install) next_action="$config_next_action" ;;
        esac
        ;;
    esac
  fi

  stats_json="null"
  if [ "$include_stats" = "true" ] && [ -n "$rtk_path" ]; then
    stats_json="$("$rtk_path" gain --json 2>/dev/null || echo null)"
    printf '%s' "$stats_json" | jq empty >/dev/null 2>&1 || stats_json="null"
  fi

  jq -n \
    --argjson rtk_present "$(bool_to_json "$rtk_present")" \
    --arg rtk_path "$rtk_path" \
    --arg rtk_version "$rtk_version" \
    --arg latest_version "$latest_version" \
    --arg latest_checked_at "$latest_checked_at" \
    --argjson update_available "$(bool_to_json "$update_available")" \
    --arg version_source "$version_source" \
    --argjson managed_by_vbw "$(bool_to_json "$managed_by_vbw")" \
    --arg install_receipt "$install_receipt" \
    --arg preferred_install_method "$preferred_install_method" \
    --argjson can_install "$(bool_to_json "$can_install")" \
    --arg binary_install_state "$binary_install_state" \
    --argjson config_present "$(bool_to_json "$config_present")" \
    --arg config_path "$config_path" \
    --arg config_state "$config_state" \
    --arg config_next_action "$config_next_action" \
    --argjson settings_json_valid "$(bool_to_json "$settings_json_valid")" \
    --arg settings_hook_state "$settings_hook_state" \
    --argjson global_hook_present "$(bool_to_json "$global_hook_present")" \
    --arg global_hook_command "$hook_command" \
    --arg global_hook_matcher "$hook_matcher" \
    --arg active_hook_rtk_path "$active_hook_rtk_path" \
    --arg active_hook_rtk_version "$active_hook_rtk_version" \
    --argjson global_claude_ref_present "$(bool_to_json "$global_claude_ref")" \
    --argjson global_rtk_md_present "$(bool_to_json "$global_rtk_md")" \
    --argjson legacy_hook_file_present "$(bool_to_json "$legacy_hook")" \
    --argjson project_local_present "$(bool_to_json "$project_local")" \
    --argjson vbw_bash_hook_present "$(bool_to_json "$vbw_hook")" \
    --argjson multiple_bash_pretooluse_hooks_detected "$(bool_to_json "$multiple_bash")" \
    --argjson updated_input_risk "$(bool_to_json "$updated_input_risk")" \
    --arg compatibility "$compatibility" \
    --arg compatibility_basis "$compatibility_basis" \
    --arg proof_state "$proof_state" \
    --arg proof_source "$proof_source" \
    --arg upstream_issue "$upstream_issue" \
    --arg diagnostic_caveat "$diagnostic_caveat" \
    --argjson restart_required "$(bool_to_json "$restart_required")" \
    --arg summary "$summary" \
    --arg next_action "$next_action" \
    --argjson stats "$stats_json" \
    '{
      rtk_present: $rtk_present,
      rtk_path: $rtk_path,
      rtk_version: $rtk_version,
      latest_version: $latest_version,
      latest_checked_at: $latest_checked_at,
      update_available: $update_available,
      version_source: $version_source,
      managed_by_vbw: $managed_by_vbw,
      install_receipt: $install_receipt,
      preferred_install_method: $preferred_install_method,
      can_install: $can_install,
      binary_install_state: $binary_install_state,
      config_present: $config_present,
      config_path: $config_path,
      config_state: $config_state,
      config_next_action: $config_next_action,
      settings_json_valid: $settings_json_valid,
      settings_hook_state: $settings_hook_state,
      global_hook_present: $global_hook_present,
      global_hook_command: $global_hook_command,
      global_hook_matcher: $global_hook_matcher,
      active_hook_rtk_path: $active_hook_rtk_path,
      active_hook_rtk_version: $active_hook_rtk_version,
      global_claude_ref_present: $global_claude_ref_present,
      global_rtk_md_present: $global_rtk_md_present,
      legacy_hook_file_present: $legacy_hook_file_present,
      project_local_present: $project_local_present,
      vbw_bash_hook_present: $vbw_bash_hook_present,
      multiple_bash_pretooluse_hooks_detected: $multiple_bash_pretooluse_hooks_detected,
      updated_input_risk: $updated_input_risk,
      compatibility: $compatibility,
      compatibility_basis: $compatibility_basis,
      proof_state: $proof_state,
      proof_source: $proof_source,
      upstream_issue: $upstream_issue,
      diagnostic_caveat: $diagnostic_caveat,
      restart_required: $restart_required,
      summary: $summary,
      next_action: $next_action,
      stats: $stats
    }'
}

doctor_json() {
  status_json false false | jq '
    . as $s
    | ([
        (if $s.legacy_hook_file_present then "legacy hook file" else empty end),
        (if $s.global_rtk_md_present then "global RTK.md" else empty end),
        (if $s.global_claude_ref_present then "CLAUDE.md @RTK.md reference" else empty end),
        (if $s.project_local_present then "project .rtk files" else empty end),
        (if (($s.install_receipt // "") != "") then "VBW install receipt" else empty end),
        (if (($s.binary_install_state // "absent") != "absent") then "binary state: " + $s.binary_install_state else empty end)
      ]) as $rtk_artifacts
    | .doctor_status = (
        if ($s.settings_json_valid == false) then "WARN"
        elif ($s.config_state == "config_error") then "WARN"
        elif (($s.config_state == "missing") and (($s.rtk_present == true) or ($s.global_hook_present == true))) then "WARN"
        elif ($s.update_available == true) then "WARN"
        elif ($s.compatibility == "verified" and (($s.proof_source // "") != "")) then "PASS"
        elif ($s.compatibility == "absent" and ($rtk_artifacts | length) == 0) then "SKIP"
        else "WARN" end
      )
    | .doctor_detail = (
        if .settings_json_valid == false then "Claude settings unreadable; RTK hook state cannot be determined from settings.json"
        elif .config_state == "config_error" then "RTK config unreadable or empty at " + ($s.config_path // "unknown")
        elif (.config_state == "missing" and ((.rtk_present == true) or (.global_hook_present == true))) then "RTK config missing at " + ($s.config_path // "unknown") + "; run /vbw:rtk install or /vbw:rtk init to repair setup"
        elif .update_available == true then "outdated from cached RTK release check; run /vbw:rtk update"
        elif .doctor_status == "PASS" then "verified by runtime smoke proof: " + ($s.proof_source // "smoke proof")
        elif ($rtk_artifacts | length) > 0 then "RTK artifacts present with no active settings hook: " + ($rtk_artifacts | join(", ")) + "; run /vbw:rtk status or /vbw:rtk uninstall/manage"
        elif .compatibility == "absent" then "not installed; optional: /vbw:rtk install"
        elif .compatibility == "binary_only" then "binary installed; hook inactive"
        elif .compatibility == "risk" then "hook active; PreToolUse updatedInput compatibility unverified"
        else "hook active; compatibility unverified" end
      )'
}

ensure_confirmation() {
  local yes="$1" dry_run="$2" operation="$3"
  [ "$dry_run" = "true" ] && return 0
  [ "$yes" = "true" ] && return 0
  die 2 "$operation requires explicit confirmation; rerun with --dry-run to preview or --yes after user approval"
}

latest_metadata_or_die() {
  local write_cache="${1:-false}" metadata
  metadata="$(fetch_latest_release)"
  [ -n "$metadata" ] || die 1 "latest release metadata unavailable"
  if [ "$write_cache" = "true" ]; then
    cache_latest_release "$metadata"
  fi
  printf '%s\n' "$metadata"
}

print_install_preflight() {
  local operation="$1" method="$2" metadata="$3" install_dir="$4" installed_version="$5"
  local tag asset_name checksums_url path_state next_step risk writes will_run fallback restart method_label
  tag="$(printf '%s' "$metadata" | jq -r '.tag // empty' 2>/dev/null || true)"
  asset_name="$(printf '%s' "$metadata" | jq -r '.asset_name // empty' 2>/dev/null || true)"
  checksums_url="$(printf '%s' "$metadata" | jq -r '.checksums_url // empty' 2>/dev/null || true)"
  path_state="on PATH"
  if ! path_contains_dir "$install_dir"; then
    path_state="not on PATH"
  fi
  if [ "$operation" = "update" ]; then
    restart="No restart required for the binary replacement itself; restart only before a new runtime hook smoke test."
  else
    restart="Restart Claude Code after hook activation before runtime verification."
  fi
  risk="No sudo, no shell profile edits, no curl-pipe-shell. Claude Code issue #15897 can leave multi-hook updatedInput behavior unverified until runtime smoke proof."
  if [ "$method" = "homebrew" ]; then
    method_label="Homebrew (auto-selected on macOS when brew is available)"
    if [ "$operation" = "update" ]; then
      will_run="brew upgrade rtk or no-op if Homebrew reports it is current; rtk --version; rtk gain"
      writes="Homebrew-managed RTK files; receipt ${RTK_RECEIPT_FILE}; backups under ${RTK_BACKUP_DIR}"
      fallback="No-op when Homebrew reports rtk is current."
      next_step="Run /vbw:rtk verify if hook compatibility needs re-checking."
    else
      will_run="brew install rtk; rtk --version; rtk gain; rtk config --create when config is missing; rtk init -g --auto-patch"
      writes="Homebrew-managed RTK files; receipt ${RTK_RECEIPT_FILE}; config $(rtk_config_path); ${RTK_SETTINGS_JSON}, ${RTK_GLOBAL_MD}, ${RTK_CLAUDE_MD} when RTK/VBW patch hooks"
      fallback="Use jq settings patch if RTK auto-patch does not persist the hook; use GitHub release path only when Homebrew is unavailable before mutation."
      next_step="Run /vbw:rtk verify after restart."
    fi
  else
    method_label="GitHub release asset from rtk-ai/rtk (${path_state})"
    if [ "$operation" = "update" ]; then
      will_run="query latest release metadata, download ${asset_name:-matching asset}, download checksums.txt, verify SHA-256, replace the receipt-owned RTK binary, then run rtk --version and rtk gain"
      writes="${install_dir}/rtk (${path_state}); receipt ${RTK_RECEIPT_FILE}; backups under ${RTK_BACKUP_DIR}"
      fallback="No-op when the installed version is current; checksum failure aborts without replacement."
      next_step="Run /vbw:rtk verify if hook compatibility needs re-checking."
    else
      will_run="query latest release metadata, download ${asset_name:-matching asset}, download checksums.txt, verify SHA-256, install rtk, then run the selected binary path through rtk --version, rtk gain, config bootstrap, and rtk init -g --auto-patch"
      writes="${install_dir}/rtk (${path_state}); receipt ${RTK_RECEIPT_FILE}; backups under ${RTK_BACKUP_DIR}; config $(rtk_config_path); ${RTK_SETTINGS_JSON}, ${RTK_GLOBAL_MD}, ${RTK_CLAUDE_MD} when hook setup runs"
      fallback="Use jq settings patch if RTK auto-patch does not persist a usable hook for the selected binary path."
      next_step="Run /vbw:rtk verify after restart; add ${install_dir} to PATH only for future manual rtk shell usage."
    fi
  fi
  echo "RTK ${operation} preflight"
  echo "Installed: ${installed_version:-absent}"
  echo "Latest: ${tag:-unknown}"
  echo "Method: ${method_label}"
  echo "Will run: ${will_run}"
  echo "Writes: ${writes}"
  echo "Fallback: ${fallback}"
  echo "Restart: ${restart}"
  echo "Next step: ${next_step}"
  echo "Risk: ${risk}"
  if [ "$method" = "github-release" ] && [ -z "$checksums_url" ]; then
    echo "Checksum: unavailable; operation will abort unless --allow-missing-checksum is explicitly provided"
  elif [ "$method" = "github-release" ]; then
    echo "Checksum: ${checksums_url}"
  fi
  if [ "$method" = "github-release" ] && ! path_contains_dir "$install_dir"; then
    echo "PATH note: optional for future manual shell use: export PATH=\"${install_dir}:\$PATH\""
  fi
}

backup_if_present() {
  local path="$1" stamp dest
  [ -e "$path" ] || return 0
  mkdir -p "$RTK_BACKUP_DIR"
  stamp="$(now_utc | tr ':T' '--')"
  dest="$RTK_BACKUP_DIR/$(basename "$path").$stamp.bak"
  cp -p "$path" "$dest" 2>/dev/null || cp "$path" "$dest"
}

backup_rtk_global_config_files() {
  backup_if_present "$RTK_SETTINGS_JSON"
  backup_if_present "$RTK_CLAUDE_MD"
  backup_if_present "$RTK_GLOBAL_MD"
}

shell_single_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

verify_rtk_binary() {
  local rtk_path="$1"
  [ -n "$rtk_path" ] && [ -x "$rtk_path" ] || die 1 "RTK binary probe failed; no executable RTK binary found"
  "$rtk_path" --version >/dev/null 2>&1 || die 1 "RTK binary probe failed: $rtk_path --version did not run"
  "$rtk_path" gain >/dev/null 2>&1 || die 1 "RTK binary probe failed: $rtk_path gain did not run; refusing to treat this as the RTK CLI"
}

write_minimal_rtk_config() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
[tracking]
enabled = true
history_days = 90

[display]
colors = true
emoji = true
max_width = 120

[filters]
ignore_dirs = [".git", "node_modules", "target", "__pycache__", ".venv", "vendor"]
ignore_files = ["*.lock", "*.min.js", "*.min.css"]

[tee]
enabled = true
mode = "failures"
max_files = 20

[hooks]
exclude_commands = []
EOF
}

validate_rtk_config_if_possible() {
  local rtk_path="$1" err_file status
  [ -n "$rtk_path" ] && [ -x "$rtk_path" ] || return 0
  err_file="$(mktemp)"
  set +e
  "$rtk_path" config >/dev/null 2>"$err_file"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    rm -f "$err_file"
    return 0
  fi
  if grep -Eiq 'unknown|unsupported|unrecognized|invalid option|usage:' "$err_file" 2>/dev/null; then
    rm -f "$err_file"
    return 0
  fi
  rm -f "$err_file"
  return 1
}

bootstrap_rtk_config() {
  local rtk_path="$1" config_path existed=false status
  config_path="$(rtk_config_path)"
  if [ -e "$config_path" ]; then
    existed=true
  fi
  status="$(rtk_config_state "$config_path")"
  case "$status" in
    present)
      if validate_rtk_config_if_possible "$rtk_path"; then
        echo "Config: present at $config_path"
      else
        echo "Config: config_error at $config_path"
      fi
      return 0
      ;;
    config_error)
      echo "Config: config_error at $config_path (existing file preserved)"
      return 0
      ;;
  esac

  mkdir -p "$(dirname "$config_path")"
  set +e
  "$rtk_path" config --create >/dev/null 2>&1
  status=$?
  set -e
  if [ "$status" -eq 0 ] && [ -s "$config_path" ] && validate_rtk_config_if_possible "$rtk_path"; then
    echo "Config: created_after_missing at $config_path"
    return 0
  fi

  if [ "$existed" = "true" ]; then
    echo "Config: config_error at $config_path (existing file preserved)"
    return 0
  fi

  write_minimal_rtk_config "$config_path"
  if validate_rtk_config_if_possible "$rtk_path"; then
    echo "Config: fallback_created at $config_path"
  else
    echo "Config: config_error at $config_path (fallback preserved for inspection)"
  fi
}

patch_settings_hook() {
  local rtk_path="$1" hook_command settings_dir input_file base_file tmp_file
  settings_valid || return 1
  hook_command="$(shell_single_quote "$rtk_path") hook claude"
  settings_dir="$(dirname "$RTK_SETTINGS_JSON")"
  mkdir -p "$settings_dir"
  input_file="$RTK_SETTINGS_JSON"
  base_file=""
  if [ ! -f "$input_file" ]; then
    base_file="$(mktemp "$settings_dir/settings-base.XXXXXX")"
    printf '{}\n' > "$base_file"
    input_file="$base_file"
  fi
  tmp_file="$(mktemp "$settings_dir/settings.XXXXXX")"
  jq --arg command "$hook_command" '
    if type == "object" then . else {} end
    | .hooks = (if ((.hooks // {}) | type) == "object" then (.hooks // {}) else {} end)
    | .hooks.PreToolUse = (
        ((.hooks.PreToolUse // []) | if type == "array" then . else [] end)
        | map(
            if type == "object" then
              .hooks = (
                ((.hooks // []) | if type == "array" then . else [] end)
                | map(select((((.command // "") | gsub("[\"'\'' ]"; "")) | test("(^|/)rtkhookclaude($|[;])|rtk-rewrite[.]sh")) | not))
              )
            else
              empty
            end
          )
        | map(select(((.hooks // []) | length) > 0))
        | [{matcher:"Bash",hooks:[{type:"command",command:$command}]}] + .
      )
  ' "$input_file" > "$tmp_file"
  backup_if_present "$RTK_SETTINGS_JSON"
  chmod 600 "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$RTK_SETTINGS_JSON"
  [ -z "$base_file" ] || rm -f "$base_file"
}

status_hook_matches_rtk_path() {
  local status_payload="$1" selected_rtk_path="$2" active_hook_rtk_path
  active_hook_rtk_path="$(printf '%s' "$status_payload" | jq -r '.active_hook_rtk_path // ""' 2>/dev/null || true)"
  [ -n "$active_hook_rtk_path" ] || return 1
  [ -x "$active_hook_rtk_path" ] || return 1
  same_executable_path "$active_hook_rtk_path" "$selected_rtk_path"
}

activate_rtk_hook() {
  local rtk_path="$1" hook_only="${2:-false}" stdout_file stderr_file status status_after hook_present recoverable
  local -a init_args=(init -g --auto-patch)
  [ "$hook_only" = "true" ] && init_args+=(--hook-only)
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  backup_rtk_global_config_files
  set +e
  "$rtk_path" "${init_args[@]}" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  status_after="$(status_json false false)"
  hook_present="$(printf '%s' "$status_after" | jq -r '.global_hook_present // false')"
  if [ "$hook_present" = "true" ] && status_hook_matches_rtk_path "$status_after" "$rtk_path"; then
    rm -f "$stdout_file" "$stderr_file"
    echo "Hook: active via rtk init -g --auto-patch"
    return 0
  fi

  recoverable=false
  if [ "$hook_present" = "true" ]; then
    recoverable=true
  elif [ "$status" -eq 0 ]; then
    recoverable=true
  elif grep -Eiq 'settings[.]json|PreToolUse|hook claude|RTK[.]md|manual|auto-patch' "$stdout_file" "$stderr_file" 2>/dev/null; then
    recoverable=true
  elif printf '%s' "$status_after" | jq -e '.global_rtk_md_present == true or .global_claude_ref_present == true' >/dev/null 2>&1; then
    recoverable=true
  fi

  if [ "$recoverable" = "true" ] && settings_valid; then
    patch_settings_hook "$rtk_path"
    status_after="$(status_json false false)"
    hook_present="$(printf '%s' "$status_after" | jq -r '.global_hook_present // false')"
    if [ "$hook_present" = "true" ] && status_hook_matches_rtk_path "$status_after" "$rtk_path"; then
      rm -f "$stdout_file" "$stderr_file"
      echo "Hook: active via VBW settings fallback patch"
      return 0
    fi
  fi

  cat "$stdout_file" 2>/dev/null || true
  cat "$stderr_file" >&2 2>/dev/null || true
  rm -f "$stdout_file" "$stderr_file"
  if ! settings_valid; then
    die 1 "RTK hook activation failed and ${RTK_SETTINGS_JSON} is malformed; settings preserved for manual repair"
  fi
  [ "$status" -eq 0 ] || die "$status" "rtk init -g --auto-patch failed before VBW could verify or patch the settings hook"
  die 1 "rtk init -g --auto-patch completed but no RTK settings hook was found"
}

complete_setup() {
  local rtk_path="$1" hook_only="${2:-false}"
  verify_rtk_binary "$rtk_path"
  echo "Binary: verified $rtk_path"
  bootstrap_rtk_config "$rtk_path"
  activate_rtk_hook "$rtk_path" "$hook_only"
  status_json false false | jq -r '.summary'
}

write_receipt() {
  local operation="$1" method="$2" binary_path="$3" previous_version="$4" installed_version="$5" metadata="$6" checksum="$7" tmp
  mkdir -p "$VBW_RTK_DIR"
  tmp="$(mktemp "$VBW_RTK_DIR/rtk-install.XXXXXX")"
  jq -n \
    --arg manager "vbw" \
    --arg operation "$operation" \
    --arg method "$method" \
    --arg binary_path "$binary_path" \
    --arg previous_version "$previous_version" \
    --arg installed_version "$installed_version" \
    --arg release_tag "$(printf '%s' "$metadata" | jq -r '.tag // empty')" \
    --arg asset_url "$(printf '%s' "$metadata" | jq -r '.asset_url // empty')" \
    --arg checksum_url "$(printf '%s' "$metadata" | jq -r '.checksums_url // empty')" \
    --arg verified_checksum "$checksum" \
    --arg timestamp "$(now_utc)" \
    --arg claude_dir "$CLAUDE_DIR" \
    '{manager:$manager, operation:$operation, method:$method, binary_path:$binary_path, previous_version:$previous_version, installed_version:$installed_version, release_tag:$release_tag, asset_url:$asset_url, checksum_url:$checksum_url, verified_checksum:$verified_checksum, timestamp:$timestamp, claude_dir:$claude_dir}' > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$RTK_RECEIPT_FILE"
}

retire_install_receipt() {
  local stamp dest
  [ -f "$RTK_RECEIPT_FILE" ] || return 0
  mkdir -p "$RTK_BACKUP_DIR"
  stamp="$(now_utc | tr ':T' '--')"
  dest="$RTK_BACKUP_DIR/rtk-install.$stamp.retired.json"
  cp -p "$RTK_RECEIPT_FILE" "$dest" 2>/dev/null || cp "$RTK_RECEIPT_FILE" "$dest"
  rm -f "$RTK_RECEIPT_FILE"
}

verify_download_checksum() {
  local asset="$1" asset_name="$2" checksums="$3" allow_missing="$4" expected actual
  if [ ! -s "$checksums" ]; then
    [ "$allow_missing" = "true" ] || die 1 "checksums.txt unavailable; aborting managed install/update"
    echo ""
    return 0
  fi
  expected="$(awk -v n="$asset_name" '($2 == n || $NF == n) {print $1; exit}' "$checksums")"
  if [ -z "$expected" ]; then
    [ "$allow_missing" = "true" ] || die 1 "checksums.txt did not include $asset_name"
    echo ""
    return 0
  fi
  actual="$(sha256_file "$asset")"
  [ "$actual" = "$expected" ] || die 1 "checksum mismatch for $asset_name"
  echo "$actual"
}

rtk_archive_member_safe() {
  local member="$1"
  [ -n "$member" ] || return 1
  case "$member" in
    /*|..|../*|*/..|*/../*) return 1 ;;
    *) return 0 ;;
  esac
}

validate_rtk_archive_members() {
  local asset="$1" member rtk_member="" rtk_count=0
  while IFS= read -r member; do
    [ -n "$member" ] || continue
    if ! rtk_archive_member_safe "$member"; then
      die 1 "unsafe RTK archive member path: $member"
    fi
    case "$member" in
      */) continue ;;
    esac
    if [ "$(basename "$member")" = "rtk" ]; then
      rtk_member="$member"
      rtk_count=$((rtk_count + 1))
    fi
  done < <(tar -tzf "$asset" 2>/dev/null || die 1 "failed to read RTK release archive")

  if [ "$rtk_count" -eq 0 ]; then
    die 1 "downloaded RTK asset did not contain an rtk binary"
  fi
  if [ "$rtk_count" -gt 1 ]; then
    die 1 "RTK release archive contains multiple rtk binaries; refusing ambiguous extraction"
  fi
  printf '%s\n' "$rtk_member"
}

extract_rtk_binary() {
  local asset="$1" temp_dir="$2" rtk_member found
  mkdir -p "$temp_dir"
  rtk_member="$(validate_rtk_archive_members "$asset")"
  tar -xzf "$asset" -C "$temp_dir" -- "$rtk_member"
  found="$temp_dir/$rtk_member"
  [ -f "$found" ] || die 1 "downloaded RTK asset did not contain an rtk binary"
  chmod +x "$found" 2>/dev/null || true
  printf '%s\n' "$found"
}

install_or_update() {
  local operation="$1" dry_run=false yes=false allow_missing=false install_dir metadata installed_path installed_version previous_version method receipt_method
  local temp_dir asset_name asset_url checksums_url asset_file checksums_file checksum extracted target_path receipt_binary latest_version

  while [ "$#" -gt 0 ]; do
    case "$1" in
      install|update) shift ;;
      --dry-run) dry_run=true; shift ;;
      --yes) yes=true; shift ;;
      --allow-missing-checksum) allow_missing=true; shift ;;
      --install-dir) install_dir="${2:-}"; [ -n "$install_dir" ] || die 2 "--install-dir requires a value"; shift 2 ;;
      *) die 2 "unknown ${operation} option: $1" ;;
    esac
  done

  install_dir="${install_dir:-$RTK_INSTALL_DIR_DEFAULT}"
  installed_path="$(rtk_path_detect)"
  installed_version="$(rtk_version_detect "$installed_path")"
  method="$(preferred_install_method_detect)"

  if [ "$operation" = "update" ]; then
    receipt_binary="$(rtk_path_from_receipt)"
    if receipt_managed; then
      receipt_method="$(receipt_field method)"
      [ -n "$receipt_method" ] || receipt_method="github-release"
      if [ -z "$receipt_binary" ] || [ ! -x "$receipt_binary" ]; then
        echo "RTK update preflight"
        echo "Installed: ${installed_version:-unknown}"
        echo "Method: VBW receipt exists but its binary is missing"
        echo "Will run: no update"
        echo "Next step: run /vbw:rtk install or repair the receipt-owned binary path."
        exit 1
      fi
      installed_path="$receipt_binary"
      installed_version="$(rtk_version_detect "$installed_path")"
      install_dir="$(dirname "$receipt_binary")"
      method="$receipt_method"
    elif [ -n "$installed_path" ]; then
      echo "RTK update preflight"
      echo "Installed: ${installed_version:-present}"
      echo "Method: external install detected"
      echo "Will run: no VBW-managed overwrite and no ownership takeover"
      echo "Next step: update RTK with the package manager or install method that owns ${installed_path}."
      exit 0
    else
      echo "RTK update preflight"
      echo "Installed: absent"
      echo "Method: no RTK binary detected"
      echo "Will run: no update"
      echo "Next step: run /vbw:rtk install."
      exit 0
    fi
  fi

  metadata="{}"
  if [ "$method" = "github-release" ]; then
    metadata="$(latest_metadata_or_die false)"
  fi
  print_install_preflight "$operation" "$method" "$metadata" "$install_dir" "$installed_version"
  if [ "$method" = "github-release" ]; then
    latest_version="$(printf '%s' "$metadata" | jq -r '.version // empty')"
    if [ "$operation" = "update" ] && [ -n "$latest_version" ] && [ -n "$installed_version" ] && ! version_gt "$latest_version" "$installed_version"; then
      echo "Update: installed RTK ${installed_version} is current for latest ${latest_version}; no replacement needed."
      exit 0
    fi
  fi
  ensure_confirmation "$yes" "$dry_run" "$operation"
  [ "$dry_run" = "true" ] && exit 0

  if [ "$method" = "homebrew" ]; then
    local outdated
    command -v brew >/dev/null 2>&1 || die 1 "Homebrew selected but brew is not available"
    previous_version="$installed_version"
    if [ "$operation" = "update" ]; then
      outdated="$(brew outdated --quiet rtk 2>/dev/null || true)"
      if [ -n "$outdated" ]; then
        brew upgrade rtk
      else
        echo "Update: Homebrew reports rtk is current; no replacement needed."
      fi
    else
      brew install rtk
    fi
    installed_path="$(rtk_path_detect)"
    [ -n "$installed_path" ] || die 1 "Homebrew completed but rtk is not on PATH"
    installed_version="$(rtk_version_detect "$installed_path")"
    write_receipt "$operation" "homebrew" "$installed_path" "$previous_version" "$installed_version" "$metadata" ""
    if [ "$operation" = "install" ]; then
      echo "RTK binary installed via Homebrew: $installed_path (${installed_version:-version unknown})"
      complete_setup "$installed_path"
      echo "✓ RTK install setup complete: $installed_path (${installed_version:-version unknown})"
    else
      verify_rtk_binary "$installed_path"
      echo "✓ RTK update complete via Homebrew: $installed_path (${installed_version:-version unknown})"
    fi
    exit 0
  fi

  asset_name="$(printf '%s' "$metadata" | jq -r '.asset_name')"
  asset_url="$(printf '%s' "$metadata" | jq -r '.asset_url')"
  checksums_url="$(printf '%s' "$metadata" | jq -r '.checksums_url // empty')"
  temp_dir="$(mktemp -d)"
  RTK_TEMP_DIR="$temp_dir"
  trap cleanup_temp_dir EXIT
  asset_file="$temp_dir/$asset_name"
  checksums_file="$temp_dir/checksums.txt"
  curl_bounded -o "$asset_file" "$asset_url"
  if [ -n "$checksums_url" ]; then
    curl_bounded -o "$checksums_file" "$checksums_url"
  else
    : > "$checksums_file"
  fi
  checksum="$(verify_download_checksum "$asset_file" "$asset_name" "$checksums_file" "$allow_missing")"
  extracted="$(extract_rtk_binary "$asset_file" "$temp_dir/extract")"
  mkdir -p "$install_dir"
  target_path="$install_dir/rtk"
  backup_if_present "$target_path"
  previous_version="$installed_version"
  cp "$extracted" "$target_path"
  chmod +x "$target_path"
  installed_version="$("$target_path" --version 2>/dev/null | awk 'match($0, /[0-9]+([.][0-9]+)+/) {print substr($0, RSTART, RLENGTH); exit}' || true)"
  write_receipt "$operation" "github-release" "$target_path" "$previous_version" "$installed_version" "$metadata" "$checksum"
  cache_latest_release "$metadata"
  if [ "$operation" = "install" ]; then
    echo "RTK binary installed: $target_path (${installed_version:-version unknown})"
    if ! path_contains_dir "$install_dir"; then
      echo "ℹ $install_dir is not on PATH. Setup will use the selected binary path; optional for manual shell use: export PATH=\"${install_dir}:\$PATH\""
    fi
    complete_setup "$target_path"
    echo "✓ RTK install setup complete: $target_path (${installed_version:-version unknown})"
  else
    verify_rtk_binary "$target_path"
    echo "✓ RTK update complete: $target_path (${installed_version:-version unknown})"
  fi
  cleanup_temp_dir
  RTK_TEMP_DIR=""
  trap - EXIT
}

init_hook() {
  local dry_run=false yes=false hook_only=false rtk_path receipt_path display_cmd
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      --yes) yes=true; shift ;;
      --auto-patch) shift ;; # Backward-compatible no-op; auto-patch is always used.
      --hook-only) hook_only=true; shift ;;
      *) die 2 "unknown init option: $1" ;;
    esac
  done
  rtk_path="$(command_path rtk)"
  if [ -z "$rtk_path" ]; then
    receipt_path="$(rtk_path_from_receipt)"
    if [ -n "$receipt_path" ] && [ -x "$receipt_path" ]; then
      die 1 "RTK binary exists at $receipt_path but is not on PATH; add $(dirname "$receipt_path") to PATH before hook activation"
    fi
    die 1 "RTK binary not found on PATH; run /vbw:rtk install first or install RTK manually"
  fi
  display_cmd="$rtk_path init -g --auto-patch"
  if [ "$hook_only" = "true" ]; then display_cmd="$display_cmd --hook-only"; fi
  echo "RTK hook preflight"
  echo "Will run: $display_cmd"
  echo "Writes: config $(rtk_config_path) when missing; ${RTK_SETTINGS_JSON}, ${RTK_GLOBAL_MD}, and @RTK.md references inside ${RTK_CLAUDE_MD} when RTK/VBW patches Claude Code"
  echo "Fallback: validate settings hook after RTK auto-patch; use a jq settings patch only when settings JSON is valid and the hook is still missing"
  echo "Next step: restart Claude Code after hook activation, then run /vbw:rtk verify"
  echo "Risk: Claude Code issue #15897 reports updatedInput can fail when multiple PreToolUse hooks match; compatibility remains unverified until a runtime smoke proof exists. VBW bash-guard.sh is not disabled, reordered, or weakened."
  ensure_confirmation "$yes" "$dry_run" "init"
  [ "$dry_run" = "true" ] && exit 0
  complete_setup "$rtk_path" "$hook_only"
}

verify_rtk() {
  local as_json=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) as_json=true; shift ;;
      *) die 2 "unknown verify option: $1" ;;
    esac
  done
  if [ "$as_json" = "true" ]; then
    status_json false false
    return 0
  fi
  status_json false false | jq -r '
    "RTK verify\n" +
    "Static: " + .summary + "\n" +
    "Config: " + (.config_state // "unknown") + " at " + (.config_path // "unknown") + "\n" +
    "Runtime: " + (if .compatibility == "verified" then "verified by runtime smoke proof " + .proof_source else "manual Claude Code smoke required before PASS" end) +
    (if (.compatibility == "verified" and (.updated_input_risk == true)) then "\nCaveat: " + (.diagnostic_caveat // "anthropics/claude-code#15897 remains an upstream diagnostic caveat") else "" end) +
    (if .compatibility == "verified" then "" else "\nManual smoke: restart Claude Code, run the scoped /vbw:rtk verify Bash-tool sequence, confirm RTK rewrites and VBW bash-guard behavior, then record proof." end)
  '
}

uninstall_rtk() {
  local dry_run=false yes=false deactivate_hook=false binary_path managed rtk_path active_hook settings_unknown will_run receipt_method
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      --yes) yes=true; shift ;;
      --deactivate-hook) deactivate_hook=true; shift ;;
      *) die 2 "unknown uninstall option: $1" ;;
    esac
  done
  managed=false
  if receipt_managed; then managed=true; fi
  receipt_method="$(receipt_field method)"
  [ -n "$receipt_method" ] || receipt_method="github-release"
  binary_path="$(rtk_path_from_receipt)"
  active_hook=""
  settings_unknown=false
  if settings_valid; then
    active_hook="$(settings_hook_command)"
  else
    settings_unknown=true
  fi
  echo "RTK uninstall preflight"
  if [ "$managed" = "true" ] && [ "$receipt_method" = "homebrew" ]; then
    echo "Will remove: Homebrew-managed rtk formula after hook-safety guards pass"
  elif [ "$managed" = "true" ] && [ -n "$binary_path" ]; then
    echo "Will remove: $binary_path (VBW receipt-owned)"
  else
    echo "Will remove: no binary; external installs are not deleted by VBW"
  fi
  if [ "$managed" = "true" ] && { [ -n "$active_hook" ] || [ "$settings_unknown" = "true" ]; } && [ "$deactivate_hook" != "true" ]; then
    will_run="hook deactivation or settings repair required before binary removal; rerun with --deactivate-hook after confirming settings intent"
  elif [ "$deactivate_hook" = "true" ]; then
    if [ "$receipt_method" = "homebrew" ]; then
      will_run="rtk init -g --uninstall before brew uninstall rtk"
    else
      will_run="rtk init -g --uninstall before binary removal"
    fi
  elif [ "$managed" = "true" ] && [ "$receipt_method" = "homebrew" ]; then
    will_run="brew uninstall rtk after hook-safety guards pass"
  elif [ "$managed" = "true" ] && [ -n "$binary_path" ]; then
    will_run="remove VBW receipt-owned binary only; no hook deactivation requested"
  else
    will_run="external/no-receipt guidance only; no binary deletion"
  fi
  echo "Will run: $will_run"
  echo "Writes: receipt/backups under ${VBW_RTK_DIR}; RTK may edit Claude settings only when --deactivate-hook is used"
  ensure_confirmation "$yes" "$dry_run" "uninstall"
  [ "$dry_run" = "true" ] && exit 0
  if [ "$managed" = "true" ] && { [ -n "$active_hook" ] || [ "$settings_unknown" = "true" ]; } && [ "$deactivate_hook" != "true" ]; then
    echo "RTK: active or unreadable RTK settings hook state detected; pass --deactivate-hook before removing the VBW-managed binary" >&2
    exit 1
  fi
  if [ "$deactivate_hook" = "true" ]; then
    rtk_path="$(rtk_path_detect)"
    if [ -z "$rtk_path" ] && [ -n "$binary_path" ] && [ -x "$binary_path" ]; then
      rtk_path="$binary_path"
    fi
    if [ -z "$rtk_path" ]; then
      echo "RTK: cannot deactivate hook because no runnable RTK binary was found; preserved existing files" >&2
      exit 1
    fi
    backup_rtk_global_config_files
    if ! "$rtk_path" init -g --uninstall; then
      echo "RTK: hook deactivation failed; preserved RTK binary and receipt for retry" >&2
      exit 1
    fi
  fi
  if [ "$managed" = "true" ] && [ "$receipt_method" = "homebrew" ]; then
    command -v brew >/dev/null 2>&1 || die 1 "Homebrew-managed RTK receipt found but brew is not available; preserved receipt for manual repair"
    brew uninstall rtk
  elif [ "$managed" = "true" ] && [ -n "$binary_path" ] && [ -e "$binary_path" ]; then
    rm -f "$binary_path"
  fi
  if [ "$managed" = "true" ]; then
    retire_install_receipt
  fi
  echo "✓ RTK uninstall complete"
}

status_command() {
  local json=false check_updates=false include_stats=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --json) json=true; shift ;;
      --check-updates) check_updates=true; shift ;;
      --stats) include_stats=true; shift ;;
      *) die 2 "unknown status option: $1" ;;
    esac
  done
  if [ "$json" = "true" ]; then
    status_json "$check_updates" "$include_stats"
  else
    status_json "$check_updates" "$include_stats" | jq -r '.summary'
  fi
}

main() {
  local cmd="${1:-status}"
  [ "$#" -gt 0 ] && shift || true
  case "$cmd" in
    status) status_command "$@" ;;
    doctor-json) doctor_json "$@" ;;
    install) install_or_update install "$@" ;;
    update) install_or_update update "$@" ;;
    init) init_hook "$@" ;;
    verify) verify_rtk "$@" ;;
    smoke-start) smoke_start "$@" ;;
    smoke-finish) smoke_finish "$@" ;;
    uninstall) uninstall_rtk "$@" ;;
    help|-h|--help) usage ;;
    *) usage >&2; die 2 "unknown command: $cmd" ;;
  esac
}

main "$@"
