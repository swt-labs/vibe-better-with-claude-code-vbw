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
RTK_BACKUP_DIR="${RTK_BACKUP_DIR:-$VBW_RTK_DIR/backups}"
RTK_SETTINGS_JSON="${RTK_SETTINGS_JSON:-$CLAUDE_DIR/settings.json}"
RTK_GLOBAL_MD="${RTK_GLOBAL_MD:-$CLAUDE_DIR/RTK.md}"
RTK_CLAUDE_MD="${RTK_CLAUDE_MD:-$CLAUDE_DIR/CLAUDE.md}"
RTK_INSTALL_DIR_DEFAULT="${RTK_INSTALL_DIR:-$HOME/.local/bin}"
RTK_LEGACY_CLAUDE_DIR="${RTK_LEGACY_CLAUDE_DIR:-${HOME}/.claude}"
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
  init [--dry-run] [--yes] [--auto-patch] [--hook-only]
  verify [--json]
  uninstall [--dry-run] [--yes] [--deactivate-hook]

Mutating commands require --yes. Use --dry-run to inspect planned effects.
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

command_path() {
  command -v "$1" 2>/dev/null || true
}

rtk_path_from_receipt() {
  if [ -f "$RTK_RECEIPT_FILE" ] && jq empty "$RTK_RECEIPT_FILE" >/dev/null 2>&1; then
    jq -r '.binary_path // empty' "$RTK_RECEIPT_FILE" 2>/dev/null || true
  fi
}

rtk_path_detect() {
  local path receipt_path
  path="$(command_path rtk)"
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
    return 0
  fi

  receipt_path="$(rtk_path_from_receipt)"
  if [ -n "$receipt_path" ] && [ -x "$receipt_path" ]; then
    printf '%s\n' "$receipt_path"
  fi
}

rtk_version_detect() {
  local path="$1" out
  [ -n "$path" ] || return 0
  out="$($path --version 2>/dev/null || true)"
  normalize_version "$out"
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
      | select((.command // "") | test("(^|[[:space:]/])rtk[[:space:]]+hook[[:space:]]+claude($|[[:space:];])|rtk-rewrite[.]sh"))
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
      | select((.command // "") | test("(^|[[:space:]/])rtk[[:space:]]+hook[[:space:]]+claude($|[[:space:];])|rtk-rewrite[.]sh"))
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

curl_json() {
  local url="$1"
  curl -fsSL "$url"
}

query_latest_release() {
  local release_json tag version target asset_name asset_url checksums_url checked tmp
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
  mkdir -p "$VBW_RTK_DIR"
  tmp="$(mktemp "$VBW_RTK_DIR/rtk-latest.XXXXXX")"
  jq -n \
    --arg tag "$tag" \
    --arg version "$version" \
    --arg checked_at "$checked" \
    --arg target "$target" \
    --arg asset_name "$asset_name" \
    --arg asset_url "$asset_url" \
    --arg checksums_url "$checksums_url" \
    '{tag:$tag, version:$version, checked_at:$checked_at, target:$target, asset_name:$asset_name, asset_url:$asset_url, checksums_url:$checksums_url}' > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$RTK_LATEST_CACHE"
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

status_json() {
  local check_updates="${1:-false}" include_stats="${2:-false}"
  local rtk_path rtk_present rtk_version latest_json latest_version latest_checked_at update_available version_source
  local managed_by_vbw install_receipt receipt_binary binary_install_state can_install preferred_install_method
  local settings_json_valid hook_command hook_matcher global_hook_present global_claude_ref global_rtk_md legacy_hook project_local vbw_hook bash_hook_count multiple_bash updated_input_risk
  local proof_source compatibility restart_required summary next_action stats_json

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
    binary_install_state="installed_path_missing"
  fi

  can_install=true
  command -v curl >/dev/null 2>&1 || can_install=false
  command -v jq >/dev/null 2>&1 || can_install=false
  [ -n "$(checksum_tool)" ] || can_install=false
  preferred_install_method="github-release"

  settings_json_valid=true
  if ! settings_valid; then settings_json_valid=false; fi
  hook_command=""
  hook_matcher=""
  if [ "$settings_json_valid" = "true" ]; then
    hook_command="$(settings_hook_command)"
    hook_matcher="$(settings_hook_matcher)"
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
  if [ -n "$hook_command" ] || [ "$legacy_hook" = "true" ]; then global_hook_present=true; fi
  bash_hook_count=0
  if [ "$settings_json_valid" = "true" ]; then bash_hook_count="$(settings_bash_hook_count)"; fi
  multiple_bash=false
  if [ "$global_hook_present" = "true" ] && { [ "$vbw_hook" = "true" ] || [ "${bash_hook_count:-0}" -gt 1 ]; }; then
    multiple_bash=true
  fi
  updated_input_risk=false
  [ "$multiple_bash" = "true" ] && updated_input_risk=true

  proof_source=""
  if [ -f "$RTK_PROOF_FILE" ] && jq empty "$RTK_PROOF_FILE" >/dev/null 2>&1; then
    proof_source="$RTK_PROOF_FILE"
  fi

  compatibility="absent"
  restart_required=false
  if [ -n "$proof_source" ] && [ "$global_hook_present" = "true" ]; then
    compatibility="verified"
  elif [ "$global_hook_present" = "true" ] && [ "$updated_input_risk" = "true" ]; then
    compatibility="risk"
  elif [ "$global_hook_present" = "true" ]; then
    compatibility="hook_active_unverified"
  elif [ "$rtk_present" = "true" ]; then
    compatibility="binary_only"
  fi
  if [ "$global_hook_present" = "true" ] && [ -z "$proof_source" ]; then
    restart_required=true
  fi

  case "$compatibility" in
    absent)
      summary="RTK not installed; optional: /vbw:rtk install"
      next_action="install"
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
      summary="RTK/VBW coexistence verified by smoke proof"
      next_action="status"
      ;;
    *)
      summary="RTK status unknown"
      next_action="status"
      ;;
  esac

  stats_json="null"
  if [ "$include_stats" = "true" ] && [ -n "$rtk_path" ]; then
    stats_json="$($rtk_path gain --json 2>/dev/null || echo null)"
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
    --argjson settings_json_valid "$(bool_to_json "$settings_json_valid")" \
    --argjson global_hook_present "$(bool_to_json "$global_hook_present")" \
    --arg global_hook_command "$hook_command" \
    --arg global_hook_matcher "$hook_matcher" \
    --argjson global_claude_ref_present "$(bool_to_json "$global_claude_ref")" \
    --argjson global_rtk_md_present "$(bool_to_json "$global_rtk_md")" \
    --argjson legacy_hook_file_present "$(bool_to_json "$legacy_hook")" \
    --argjson project_local_present "$(bool_to_json "$project_local")" \
    --argjson vbw_bash_hook_present "$(bool_to_json "$vbw_hook")" \
    --argjson multiple_bash_pretookuse_hooks_detected "$(bool_to_json "$multiple_bash")" \
    --argjson updated_input_risk "$(bool_to_json "$updated_input_risk")" \
    --arg compatibility "$compatibility" \
    --arg proof_source "$proof_source" \
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
      settings_json_valid: $settings_json_valid,
      global_hook_present: $global_hook_present,
      global_hook_command: $global_hook_command,
      global_hook_matcher: $global_hook_matcher,
      global_claude_ref_present: $global_claude_ref_present,
      global_rtk_md_present: $global_rtk_md_present,
      legacy_hook_file_present: $legacy_hook_file_present,
      project_local_present: $project_local_present,
      vbw_bash_hook_present: $vbw_bash_hook_present,
      multiple_bash_pretookuse_hooks_detected: $multiple_bash_pretookuse_hooks_detected,
      updated_input_risk: $updated_input_risk,
      compatibility: $compatibility,
      proof_source: $proof_source,
      restart_required: $restart_required,
      summary: $summary,
      next_action: $next_action,
      stats: $stats
    }'
}

doctor_json() {
  status_json false false | jq '
    . as $s
    | .doctor_status = (
        if ($s.compatibility == "verified") then "PASS"
        elif ($s.compatibility == "absent" and ($s.project_local_present | not)) then "SKIP"
        else "WARN" end
      )
    | .doctor_detail = (
        if .doctor_status == "PASS" then "verified by " + ($s.proof_source // "smoke proof")
        elif .compatibility == "absent" then "not installed; optional: /vbw:rtk install"
        elif .compatibility == "binary_only" then "binary installed; hook inactive"
        elif .compatibility == "risk" then "hook active; PreToolUse updatedInput compatibility unverified"
        elif .update_available == true then "outdated; run /vbw:rtk update"
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
  local metadata
  metadata="$(query_latest_release)"
  [ -n "$metadata" ] || die 1 "latest release metadata unavailable"
  printf '%s\n' "$metadata"
}

print_install_preflight() {
  local operation="$1" metadata="$2" install_dir="$3" installed_version="$4"
  local tag asset_name checksums_url path_state next_step risk
  tag="$(printf '%s' "$metadata" | jq -r '.tag // empty')"
  asset_name="$(printf '%s' "$metadata" | jq -r '.asset_name // empty')"
  checksums_url="$(printf '%s' "$metadata" | jq -r '.checksums_url // empty')"
  path_state="on PATH"
  if ! path_contains_dir "$install_dir"; then
    path_state="not on PATH"
  fi
  next_step="Run /vbw:rtk init after the binary is visible on PATH."
  risk="No Claude Code settings are edited by this ${operation}; checksum is required when checksums.txt exists."
  echo "RTK ${operation} preflight"
  echo "Installed: ${installed_version:-absent}"
  echo "Latest: ${tag:-unknown}"
  echo "Method: latest GitHub release asset from rtk-ai/rtk"
  echo "Will run: query latest release metadata, download ${asset_name:-matching asset}, download checksums.txt, verify SHA-256, install rtk"
  echo "Writes: ${install_dir}/rtk (${path_state}); receipt ${RTK_RECEIPT_FILE}; backups under ${RTK_BACKUP_DIR}"
  echo "Does not do: edit Claude settings, edit shell profiles, use sudo, pipe downloaded shell scripts into sh, or run rtk init -g"
  echo "Next step: ${next_step}"
  echo "Risk: ${risk}"
  if [ -z "$checksums_url" ]; then
    echo "Checksum: unavailable; operation will abort unless --allow-missing-checksum is explicitly provided"
  else
    echo "Checksum: ${checksums_url}"
  fi
  if ! path_contains_dir "$install_dir"; then
    echo "PATH note: add this yourself before hook activation: export PATH=\"${install_dir}:\$PATH\""
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

write_receipt() {
  local operation="$1" binary_path="$2" previous_version="$3" installed_version="$4" metadata="$5" checksum="$6" tmp
  mkdir -p "$VBW_RTK_DIR"
  tmp="$(mktemp "$VBW_RTK_DIR/rtk-install.XXXXXX")"
  jq -n \
    --arg manager "vbw" \
    --arg operation "$operation" \
    --arg method "github-release" \
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

extract_rtk_binary() {
  local asset="$1" temp_dir="$2" found
  mkdir -p "$temp_dir"
  tar -xzf "$asset" -C "$temp_dir"
  found="$(find "$temp_dir" -type f -name rtk -perm -u+x -print 2>/dev/null | head -1 || true)"
  if [ -z "$found" ]; then
    found="$(find "$temp_dir" -type f -name rtk -print 2>/dev/null | head -1 || true)"
  fi
  [ -n "$found" ] || die 1 "downloaded RTK asset did not contain an rtk binary"
  chmod +x "$found" 2>/dev/null || true
  printf '%s\n' "$found"
}

install_or_update() {
  local operation="$1" dry_run=false yes=false allow_missing=false install_dir metadata installed_path installed_version previous_version
  local temp_dir asset_name asset_url checksums_url asset_file checksums_file checksum extracted target_path

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

  if [ "$operation" = "update" ] && [ -f "$RTK_RECEIPT_FILE" ] && ! receipt_managed; then
    echo "RTK update preflight"
    echo "Installed: ${installed_version:-present}"
    echo "Method: external install detected"
    echo "Will run: no VBW-managed overwrite"
    echo "Next step: update RTK with the package manager or install method that owns ${installed_path:-the binary}."
    exit 0
  fi

  metadata="$(latest_metadata_or_die)"
  print_install_preflight "$operation" "$metadata" "$install_dir" "$installed_version"
  ensure_confirmation "$yes" "$dry_run" "$operation"
  [ "$dry_run" = "true" ] && exit 0

  asset_name="$(printf '%s' "$metadata" | jq -r '.asset_name')"
  asset_url="$(printf '%s' "$metadata" | jq -r '.asset_url')"
  checksums_url="$(printf '%s' "$metadata" | jq -r '.checksums_url // empty')"
  temp_dir="$(mktemp -d)"
  RTK_TEMP_DIR="$temp_dir"
  trap cleanup_temp_dir EXIT
  asset_file="$temp_dir/$asset_name"
  checksums_file="$temp_dir/checksums.txt"
  curl -fsSL -o "$asset_file" "$asset_url"
  if [ -n "$checksums_url" ]; then
    curl -fsSL -o "$checksums_file" "$checksums_url"
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
  installed_version="$($target_path --version 2>/dev/null | awk 'match($0, /[0-9]+([.][0-9]+)+/) {print substr($0, RSTART, RLENGTH); exit}' || true)"
  write_receipt "$operation" "$target_path" "$previous_version" "$installed_version" "$metadata" "$checksum"
  echo "✓ RTK ${operation} complete: $target_path (${installed_version:-version unknown})"
  if ! path_contains_dir "$install_dir"; then
    echo "⚠ $install_dir is not on PATH. Add: export PATH=\"${install_dir}:\$PATH\""
  fi
  cleanup_temp_dir
  RTK_TEMP_DIR=""
  trap - EXIT
}

init_hook() {
  local dry_run=false yes=false auto_patch=false hook_only=false rtk_path args
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      --yes) yes=true; shift ;;
      --auto-patch) auto_patch=true; shift ;;
      --hook-only) hook_only=true; shift ;;
      *) die 2 "unknown init option: $1" ;;
    esac
  done
  rtk_path="$(rtk_path_detect)"
  [ -n "$rtk_path" ] || die 1 "RTK binary not found; run /vbw:rtk install first or install RTK manually"
  echo "RTK hook preflight"
  echo "Will run: $rtk_path init -g${auto_patch:+ --auto-patch}${hook_only:+ --hook-only}"
  echo "Writes: ${RTK_SETTINGS_JSON}, ${RTK_GLOBAL_MD}, and @RTK.md references inside ${RTK_CLAUDE_MD} when RTK patches Claude Code"
  echo "Does not do: disable, reorder, or weaken VBW bash-guard.sh"
  echo "Next step: restart Claude Code after hook activation, then run /vbw:rtk verify"
  echo "Risk: Claude Code issue #15897 reports updatedInput can fail when multiple PreToolUse hooks match; compatibility remains unverified until a runtime smoke proof exists."
  ensure_confirmation "$yes" "$dry_run" "init"
  [ "$dry_run" = "true" ] && exit 0
  backup_if_present "$RTK_SETTINGS_JSON"
  backup_if_present "$RTK_CLAUDE_MD"
  backup_if_present "$RTK_GLOBAL_MD"
  args=(init -g)
  [ "$auto_patch" = "true" ] && args+=(--auto-patch)
  [ "$hook_only" = "true" ] && args+=(--hook-only)
  "$rtk_path" "${args[@]}"
  status_json false false | jq -r '.summary'
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
    status_json false true
    return 0
  fi
  status_json false true | jq -r '
    "RTK verify\n" +
    "Static: " + .summary + "\n" +
    "Runtime: " + (if .compatibility == "verified" then "verified by " + .proof_source else "manual Claude Code smoke required before PASS" end) + "\n" +
    "Manual smoke: restart Claude Code, run representative Bash commands, confirm RTK rewrites and VBW bash-guard behavior, then record proof."
  '
}

uninstall_rtk() {
  local dry_run=false yes=false deactivate_hook=false binary_path managed
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
  binary_path="$(rtk_path_from_receipt)"
  echo "RTK uninstall preflight"
  if [ "$managed" = "true" ] && [ -n "$binary_path" ]; then
    echo "Will remove: $binary_path (VBW receipt-owned)"
  else
    echo "Will remove: no binary; external installs are not deleted by VBW"
  fi
  echo "Will run: ${deactivate_hook:+rtk init -g --uninstall}${deactivate_hook:-no hook deactivation unless --deactivate-hook is passed}"
  echo "Writes: receipt/backups under ${VBW_RTK_DIR}; RTK may edit Claude settings only when --deactivate-hook is used"
  ensure_confirmation "$yes" "$dry_run" "uninstall"
  [ "$dry_run" = "true" ] && exit 0
  if [ "$managed" = "true" ] && [ -n "$binary_path" ] && [ -e "$binary_path" ]; then
    rm -f "$binary_path"
  fi
  if [ "$deactivate_hook" = "true" ]; then
    local rtk_path
    rtk_path="$(rtk_path_detect)"
    [ -n "$rtk_path" ] || rtk_path="rtk"
    "$rtk_path" init -g --uninstall
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
    uninstall) uninstall_rtk "$@" ;;
    help|-h|--help) usage ;;
    *) usage >&2; die 2 "unknown command: $cmd" ;;
  esac
}

main "$@"
