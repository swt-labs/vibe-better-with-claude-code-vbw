#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

contains() {
  local file="$1" needle="$2"
  grep -Fq -- "$needle" "$file"
}

contains_re() {
  local file="$1" regex="$2"
  grep -Eq -- "$regex" "$file"
}

not_contains_re() {
  local file="$1" regex="$2"
  ! grep -Eq -- "$regex" "$file"
}

tracked_files() {
  local pattern
  for pattern in "$@"; do
    git -C "$ROOT" ls-files -- "$pattern"
  done | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

echo "=== RTK Integration Contract Verification ==="

RTK_CMD="$ROOT/commands/rtk.md"
RTK_MANAGER="$ROOT/scripts/rtk-manager.sh"
DOCTOR_CMD="$ROOT/commands/doctor.md"
STATUS_CMD="$ROOT/commands/status.md"
SESSION_START="$ROOT/scripts/session-start.sh"
README="$ROOT/README.md"

[ -f "$RTK_CMD" ] && pass "commands/rtk.md exists" || fail "commands/rtk.md missing"
[ -x "$RTK_MANAGER" ] && pass "scripts/rtk-manager.sh exists and is executable" || fail "scripts/rtk-manager.sh missing or not executable"

if contains "$RTK_CMD" 'name: vbw:rtk' \
  && contains "$RTK_CMD" 'argument-hint: [status|install|init|verify|update|uninstall]' \
  && contains "$RTK_CMD" 'allowed-tools: Read, Bash, AskUserQuestion'; then
  pass "rtk command frontmatter exposes explicit management subcommands"
else
  fail "rtk command frontmatter missing explicit management contract"
fi

for subcommand in 'status --json' 'install --dry-run' 'install --yes' 'init --dry-run' 'init --yes' 'verify' 'uninstall --dry-run' 'uninstall --yes'; do
  if contains "$RTK_CMD" "$subcommand"; then
    pass "rtk command references helper flow: $subcommand"
  else
    fail "rtk command missing helper flow: $subcommand"
  fi
done

if contains "$RTK_CMD" '/vbw:rtk install` and no-args install/repair selections are explicit consent for complete setup' \
  && contains "$RTK_CMD" 'do not ask a second install question' \
  && contains "$RTK_CMD" 'Managed setup must not use `sudo`, edit shell profiles, or pipe downloaded scripts into `sh`'; then
  pass "rtk command documents complete setup consent and no curl-to-shell piping"
else
  fail "rtk command missing consent/no-curl-to-shell wording"
fi

if contains "$RTK_CMD" 'Install or repair RTK setup` first when `status_unavailable=true' \
  && contains "$RTK_CMD" 'Install RTK and enable Claude hook` first when `rtk_present=false' \
  && contains "$RTK_CMD" 'Verify RTK/VBW coexistence` second when `status_unavailable=true` or `rtk_present=false' \
  && contains "$RTK_CMD" 'status_unavailable":true'; then
  pass "rtk command preserves unavailable state and setup-first no-args menu ordering"
else
  fail "rtk command missing unavailable-state/setup-first menu contract"
fi

if contains "$RTK_CMD" '/vbw:rtk init` is explicit consent for setup/repair of Claude Code RTK integration' \
  && contains "$RTK_CMD" 'does not install or update the binary' \
  && ! contains "$RTK_CMD" 'hook-only setup/repair for an RTK binary that is already on PATH'; then
  pass "rtk command init wording matches validation/config-bootstrap behavior"
else
  fail "rtk command init wording still implies hook-only behavior"
fi

if ! contains "$RTK_CMD" 'Binary install/update and Claude Code hook activation are separate operations' \
  && ! contains "$RTK_CMD" 'does not edit Claude settings' \
  && ! contains "$RTK_CMD" 'does not run `rtk init -g`'; then
  pass "rtk command rejects old binary-only install wording"
else
  fail "rtk command still contains old binary-only install wording"
fi

if contains "$RTK_MANAGER" 'status --json [--check-updates] [--stats]' \
  && contains "$RTK_MANAGER" 'doctor-json' \
  && contains "$RTK_MANAGER" 'install [--dry-run] [--yes] [--allow-missing-checksum]' \
  && contains "$RTK_MANAGER" 'init [--dry-run] [--yes] [--hook-only]' \
  && contains "$RTK_MANAGER" 'smoke-start' \
  && contains "$RTK_MANAGER" 'smoke-finish' \
  && contains "$RTK_MANAGER" 'uninstall [--dry-run] [--yes] [--deactivate-hook]'; then
  pass "rtk-manager exposes required subcommands and safety flags"
else
  fail "rtk-manager usage missing required subcommands or safety flags"
fi

if ! contains "$RTK_MANAGER" 'init [--dry-run] [--yes] [--auto-patch] [--hook-only]' \
  && contains "$RTK_MANAGER" '--auto-patch) shift ;; # Backward-compatible no-op; auto-patch is always used.' \
  && contains "$RTK_MANAGER" 'display_cmd="$rtk_path init -g --auto-patch"'; then
  pass "rtk-manager no longer advertises auto-patch as a user-controlled init option"
else
  fail "rtk-manager still advertises or misrepresents init --auto-patch"
fi

if contains "$RTK_MANAGER" 'RTK_REPO_API="${RTK_REPO_API:-https://api.github.com/repos/rtk-ai/rtk/releases/latest}"' \
  && contains "$RTK_MANAGER" 'checksums.txt' \
  && contains "$RTK_MANAGER" 'verify_download_checksum' \
  && contains "$RTK_MANAGER" 'checksum mismatch'; then
  pass "rtk-manager uses latest GitHub release metadata with checksum verification"
else
  fail "rtk-manager missing latest-release checksum contract"
fi

if contains "$RTK_MANAGER" 'preferred_install_method_detect()' \
  && contains "$RTK_MANAGER" 'command -v brew' \
  && contains "$RTK_MANAGER" 'brew install rtk' \
  && contains "$RTK_MANAGER" 'write_receipt "$operation" "homebrew"'; then
  pass "rtk-manager prefers Homebrew on macOS and records Homebrew receipts"
else
  fail "rtk-manager missing Homebrew-first install ownership contract"
fi

if contains "$RTK_MANAGER" 'verify_rtk_binary()' \
  && contains "$RTK_MANAGER" '"$rtk_path" --version' \
  && contains "$RTK_MANAGER" '"$rtk_path" gain' \
  && contains "$RTK_MANAGER" 'complete_setup()'; then
  pass "rtk-manager verifies RTK binary identity during explicit setup"
else
  fail "rtk-manager missing explicit setup binary identity probe"
fi

if contains "$RTK_MANAGER" 'rtk_config_path()' \
  && contains "$RTK_MANAGER" 'Library/Application Support/rtk/config.toml' \
  && contains "$RTK_MANAGER" '.config/rtk/config.toml' \
  && contains "$RTK_MANAGER" 'bootstrap_rtk_config()' \
  && contains "$RTK_MANAGER" 'config --create' \
  && contains "$RTK_MANAGER" '[tracking]' \
  && contains "$RTK_MANAGER" 'exclude_commands = []' \
  && ! contains "$RTK_MANAGER" '[telemetry]'; then
  pass "rtk-manager bootstraps documented non-telemetry RTK config"
else
  fail "rtk-manager missing config bootstrap/fallback contract"
fi

if contains "$RTK_MANAGER" 'config_present: $config_present' \
  && contains "$RTK_MANAGER" 'config_path: $config_path' \
  && contains "$RTK_MANAGER" 'config_state: $config_state' \
  && contains "$RTK_MANAGER" 'config_next_action: $config_next_action' \
  && contains "$RTK_MANAGER" 'RTK config missing at' \
  && contains "$RTK_MANAGER" 'RTK config unreadable or empty'; then
  pass "rtk-manager status/doctor surface compact config evidence"
else
  fail "rtk-manager missing config status JSON/reporting fields"
fi

if contains "$RTK_MANAGER" 'config_next_action="init"' \
  && contains "$RTK_MANAGER" 'config_next_action="install"' \
  && ! contains "$RTK_MANAGER" 'config_next_action="repair_config"' \
  && ! contains "$RTK_MANAGER" 'next_action="repair_config"' \
  && contains "$RTK_MANAGER" 'case "$next_action" in' \
  && contains "$ROOT/tests/rtk-manager.bats" '.config_next_action == "init"' \
  && contains "$ROOT/tests/rtk-manager.bats" '.config_next_action == "install"' \
  && contains "$ROOT/tests/rtk-manager.bats" '.next_action == "verify"' \
  && contains "$ROOT/tests/rtk-manager.bats" '.next_action == "repair_settings"' \
  && contains "$ROOT/tests/rtk-manager.bats" '.next_action != "repair_config" and .config_next_action != "repair_config"'; then
  pass "rtk-manager separates config remediation from primary next-action routing"
else
  fail "rtk-manager missing config_next_action routing guard"
fi

if contains "$RTK_MANAGER" 'activate_rtk_hook()' \
  && contains "$RTK_MANAGER" 'init -g --auto-patch' \
  && contains "$RTK_MANAGER" 'patch_settings_hook()' \
  && contains "$RTK_MANAGER" 'jq --arg command "$hook_command"' \
  && contains "$RTK_MANAGER" 'settings_valid || return 1' \
  && contains "$RTK_MANAGER" 'Hook: active via VBW settings fallback patch'; then
  pass "rtk-manager activates hook with auto-patch plus safe jq fallback"
else
  fail "rtk-manager missing auto-patch/fallback hook activation contract"
fi

if contains "$RTK_MANAGER" 'same_executable_path()' \
  && contains "$RTK_MANAGER" 'status_hook_matches_rtk_path()' \
  && contains "$RTK_MANAGER" 'status_hook_matches_rtk_path "$status_after" "$rtk_path"' \
  && contains "$RTK_MANAGER" 'complete_setup "$target_path"' \
  && contains "$RTK_MANAGER" "hook_command=\"\$(shell_single_quote \"\$rtk_path\") hook claude\"" \
  && contains "$ROOT/tests/rtk-manager.bats" 'off-PATH managed install verifies checksum, writes receipt, and completes setup'; then
  pass "rtk-manager completes GitHub setup from selected absolute binary and verifies hook usability"
else
  fail "rtk-manager missing off-PATH selected-binary setup/hook-usability invariant"
fi

if contains "$RTK_MANAGER" 'shell_first_word_unquote()' \
  && contains "$RTK_MANAGER" 'executable="$(shell_first_word_unquote "$command"' \
  && ! contains "$RTK_MANAGER" "executable=\"\${command#\\'}\"" \
  && contains "$ROOT/tests/rtk-manager.bats" 'off-PATH managed install with apostrophe writes parseable absolute hook' \
  && contains "$ROOT/tests/rtk-manager.bats" 'shell-quoted absolute hook with apostrophe parses and verifies proof'; then
  pass "rtk-manager parses apostrophe-safe shell-quoted hook executables without naïve truncation"
else
  fail "rtk-manager missing apostrophe-safe hook executable parsing contract"
fi

if ! contains "$RTK_CMD" 'do not offer hook activation until the user has made the binary visible' \
  && ! contains "$README" 'After the RTK binary is visible on `PATH`' \
  && contains "$RTK_CMD" 'Do not treat off-`PATH` as a setup blocker' \
  && contains "$README" 'VBW still completes setup through that absolute binary path'; then
  pass "rtk docs reject off-PATH binary-only setup guidance"
else
  fail "rtk docs still contain stale off-PATH setup blocker wording"
fi

curl_direct_count=$(grep -c 'curl -fsSL' "$RTK_MANAGER" 2>/dev/null || echo 0)
if contains "$RTK_MANAGER" 'RTK_CURL_MAX_TIME="${RTK_CURL_MAX_TIME:-15}"' \
  && contains "$RTK_MANAGER" 'curl_bounded()' \
  && contains "$RTK_MANAGER" 'curl -fsSL --max-time "$RTK_CURL_MAX_TIME" "$@"' \
  && contains "$RTK_MANAGER" 'curl_json()' \
  && contains "$RTK_MANAGER" 'curl_bounded "$url"' \
  && contains "$RTK_MANAGER" 'curl_bounded -o "$asset_file" "$asset_url"' \
  && contains "$RTK_MANAGER" 'curl_bounded -o "$checksums_file" "$checksums_url"' \
  && [ "${curl_direct_count:-0}" -eq 1 ]; then
  pass "rtk-manager bounds all managed curl calls with max-time"
else
  fail "rtk-manager has unbounded direct curl calls or missing timeout guard"
fi

unrestricted_tar_count=$(awk '/tar -xzf "\$asset" -C "\$temp_dir"$/ { count++ } END { print count + 0 }' "$RTK_MANAGER")
if contains "$RTK_MANAGER" 'rtk_archive_member_safe()' \
  && contains "$RTK_MANAGER" 'validate_rtk_archive_members()' \
  && contains "$RTK_MANAGER" 'tar -tzf "$asset"' \
  && contains "$RTK_MANAGER" 'unsafe RTK archive member path' \
  && contains "$RTK_MANAGER" 'multiple rtk binaries' \
  && contains "$RTK_MANAGER" 'tar -xzf "$asset" -C "$temp_dir" -- "$rtk_member"' \
  && [ "${unrestricted_tar_count:-0}" -eq 0 ]; then
  pass "rtk-manager validates tar members before single-member extraction"
else
  fail "rtk-manager missing safe tar member validation/extraction"
fi

if contains "$RTK_MANAGER" 'settings_hook_command()' \
  && contains "$RTK_MANAGER" 'as $match_command' \
  && contains "$RTK_MANAGER" 'rtkhookclaude' \
  && contains "$RTK_MANAGER" 'rtk-rewrite[.]sh' \
  && contains "$RTK_MANAGER" 'RTK_CLAUDE_MD' \
  && contains "$RTK_MANAGER" 'RTK_GLOBAL_MD'; then
  pass "rtk-manager detects current, quoted, and legacy RTK hook/artifact shapes"
else
  fail "rtk-manager missing current/legacy RTK hook detection"
fi

if contains "$RTK_MANAGER" 'RTK_RECEIPT_FILE' \
  && contains "$RTK_MANAGER" 'write_receipt()' \
  && contains "$RTK_MANAGER" 'manager:$manager' \
  && contains "$RTK_MANAGER" 'receipt_managed'; then
  pass "rtk-manager records VBW ownership receipts for update/uninstall"
else
  fail "rtk-manager missing ownership receipt contract"
fi

if contains "$RTK_MANAGER" '"$path" --version' \
  && contains "$RTK_MANAGER" '"$target_path" --version' \
  && ! contains "$RTK_MANAGER" '$path --version' \
  && ! contains "$RTK_MANAGER" '$target_path --version'; then
  pass "rtk-manager quotes executable paths for version probes"
else
  fail "rtk-manager has unquoted RTK executable version probes"
fi

pretooluse_typo_key="multiple_bash_pre""tookuse_hooks_detected"
if contains "$RTK_MANAGER" 'multiple_bash_pretooluse_hooks_detected' \
  && contains "$ROOT/tests/rtk-manager.bats" 'multiple_bash_pretooluse_hooks_detected' \
  && contains "$ROOT/tests/rtk-manager.bats" 'typo_key' \
  && ! contains "$RTK_MANAGER" "$pretooluse_typo_key"; then
  pass "rtk-manager status JSON spells PreToolUse correctly"
else
  fail "rtk-manager status JSON still contains misspelled PreToolUse key"
fi

if contains "$RTK_MANAGER" '"$rtk_path" gain --json' \
  && ! contains "$RTK_MANAGER" '$rtk_path gain --json'; then
  pass "rtk-manager quotes executable path for explicit stats"
else
  fail "rtk-manager has unquoted RTK executable stats invocation"
fi

backup_helper_refs=$(grep -c 'backup_rtk_global_config_files' "$RTK_MANAGER" 2>/dev/null || echo 0)
if contains "$RTK_MANAGER" 'backup_rtk_global_config_files()' \
  && contains "$RTK_MANAGER" 'backup_if_present "$RTK_SETTINGS_JSON"' \
  && contains "$RTK_MANAGER" 'backup_if_present "$RTK_CLAUDE_MD"' \
  && contains "$RTK_MANAGER" 'backup_if_present "$RTK_GLOBAL_MD"' \
  && [ "${backup_helper_refs:-0}" -ge 3 ]; then
  pass "rtk-manager backs up Claude config for activation and uninstall deactivation"
else
  fail "rtk-manager missing shared Claude config backup helper/calls"
fi

if contains "$RTK_MANAGER" 'ensure_confirmation' \
  && contains "$RTK_MANAGER" 'requires explicit confirmation' \
  && contains "$RTK_MANAGER" 'dry_run=true'; then
  pass "rtk-manager mutating operations require --yes or --dry-run"
else
  fail "rtk-manager missing explicit confirmation guard"
fi

if contains "$RTK_MANAGER" 'updatedInput' \
  && contains "$RTK_MANAGER" '#15897' \
  && contains "$RTK_MANAGER" 'compatibility="risk"' \
  && contains "$RTK_MANAGER" 'hook_active_unverified'; then
  pass "rtk-manager preserves PreToolUse updatedInput compatibility caveat"
else
  fail "rtk-manager missing updatedInput compatibility caveat"
fi

if contains "$RTK_MANAGER" 'valid_runtime_smoke_proof()' \
  && contains "$RTK_MANAGER" 'updated_input_verified' \
  && contains "$RTK_MANAGER" 'rtk_rewrite_observed' \
  && contains "$RTK_MANAGER" 'vbw_bash_guard_verified' \
  && contains "$RTK_MANAGER" '[ -n "$current_version" ] || return 1' \
  && contains "$RTK_MANAGER" '(.rtk_version // "") == $current_version' \
  && contains "$RTK_MANAGER" '(.hook_command // "") == $active_hook_command' \
  && ! grep -Fq 'jq empty "$RTK_PROOF_FILE"' "$RTK_MANAGER"; then
  pass "rtk-manager requires concrete runtime smoke proof before verified compatibility"
else
  fail "rtk-manager proof validation is too weak"
fi

if contains "$RTK_MANAGER" 'RTK_PENDING_SMOKE_FILE' \
  && contains "$RTK_MANAGER" 'smoke_start()' \
  && contains "$RTK_MANAGER" 'smoke_finish()' \
  && contains "$RTK_MANAGER" 'rtk_history_snapshot()' \
  && contains "$RTK_MANAGER" 'gain --history' \
  && contains "$RTK_MANAGER" 'expected_unprefixed_commands:["ls -la .","git status --short","git log -n 2 --oneline"]' \
  && contains "$RTK_MANAGER" 'verify_bash_guard_smoke()' \
  && contains "$RTK_MANAGER" 'scripts/bash-guard.sh to block synthetic destructive command with exit 2' \
  && contains "$RTK_MANAGER" 'history_count_evidence'; then
  pass "rtk-manager records explicit scoped runtime smoke proofs"
else
  fail "rtk-manager missing explicit scoped runtime smoke helper contract"
fi

if contains "$RTK_MANAGER" 'rtk git log -n 2 --oneline' \
  && contains "$RTK_MANAGER" '[[:space:]]+--oneline([^[:alnum:]_-]|$)' \
  && ! contains "$RTK_MANAGER" '([[:space:]]+--oneline)?' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish rejects git log smoke evidence without --oneline'; then
  pass "rtk-manager requires --oneline for git log smoke proof evidence"
else
  fail "rtk-manager can still accept git log smoke proof evidence without --oneline"
fi

if contains "$RTK_MANAGER" 'Install/update/init/uninstall require --yes' \
  && contains "$RTK_MANAGER" 'Smoke helpers are explicit runtime verification internals used by /vbw:rtk verify; they write only local VBW RTK pending/proof/failure JSON'; then
  pass "rtk-manager usage scopes confirmation requirements away from local smoke proof writes"
else
  fail "rtk-manager usage misrepresents smoke helper local proof writes as --yes-gated mutations"
fi

if contains "$RTK_MANAGER" 'rtk_history_after_pending_tail()' \
  && contains "$RTK_MANAGER" 'jq -Rs -r --arg before_tail "$before_tail"' \
  && ! contains "$RTK_MANAGER" '--arg after_history'; then
  pass "rtk-manager compares post-smoke history through stdin instead of argv"
else
  fail "rtk-manager can still pass full RTK history through argv during smoke verification"
fi

if contains "$RTK_MANAGER" 'rtk_history_evidence()' \
  && contains "$RTK_MANAGER" 'rtk_history_command_count()' \
  && contains "$RTK_MANAGER" 'history_tail_hash_unchanged' \
  && contains "$RTK_MANAGER" 'history_totals_available' \
  && contains "$RTK_MANAGER" 'history_total_delta' \
  && contains "$RTK_MANAGER" 'history_before_command_counts' \
  && contains "$RTK_MANAGER" 'history_command_counts="$(rtk_history_command_counts_json "$history_evidence")"' \
  && contains "$RTK_MANAGER" 'after_ls="$(rtk_history_command_count "$history_after_evidence" ls)"' \
  && contains "$RTK_MANAGER" 'rtk_history_require_fresh_command_counts' \
  && contains "$RTK_MANAGER" 'history_isolation_evidence' \
  && contains "$RTK_MANAGER" 'history_command_evidence' \
  && contains "$RTK_MANAGER" 'missing fresh RTK history evidence after smoke-start' \
  && contains "$RTK_MANAGER" 'history totals unavailable and evidence tail hash unchanged' \
  && contains "$RTK_MANAGER" 'fresh smoke evidence requires a new /vbw:rtk verify attempt' \
  && ! contains "$RTK_MANAGER" 'pending history tail was not found in the after-history snapshot' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish accepts parseable total tail mismatch with fresh command counts' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish rejects parseable total tail mismatch with stale command counts' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish rejects parseable total tail mismatch with stale commands outside stored tail' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish accepts parseable total unchanged tail with fresh prepended command counts' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish rejects parseable total unchanged tail with stale prepended unrelated commands' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish rejects count-unavailable tail mismatch with stale commands outside stored tail' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish rejects count-unavailable unchanged tail with scoped-looking prepended commands' \
  && contains "$ROOT/tests/rtk-manager.bats" 'smoke-finish asks for fresh verify when tail mismatch pending lacks command counts'; then
  pass "rtk-manager proves fresh smoke history with command counts when exact tail isolation is unavailable"
else
  fail "rtk-manager missing robust tail-mismatch smoke history proof contract"
fi

if contains "$RTK_MANAGER" 'compatibility_basis="runtime_smoke_passed"' \
  && contains "$RTK_MANAGER" 'proof_state="valid"' \
  && contains "$RTK_MANAGER" 'upstream_issue="anthropics/claude-code#15897"' \
  && contains "$RTK_MANAGER" 'RTK/VBW coexistence verified by runtime smoke proof' \
  && contains "$RTK_MANAGER" 'manual Claude Code smoke required before PASS' \
  && contains "$RTK_MANAGER" 'diagnostic_caveat'; then
  pass "rtk-manager separates verified normal output from diagnostic #15897 caveat"
else
  fail "rtk-manager missing verified-proof normal/diagnostic caveat split"
fi

if ! contains "$RTK_MANAGER" '$current_version == ""' \
  && ! contains "$RTK_MANAGER" '.rtk_version // $current_version' \
  && ! contains "$RTK_MANAGER" '.hook_command // $active_hook_command' \
  && contains "$RTK_MANAGER" 'rtk_path_from_hook_command()' \
  && contains "$RTK_MANAGER" 'active_hook_rtk_path' \
  && contains "$RTK_MANAGER" 'active_hook_rtk_version' \
  && contains "$RTK_MANAGER" 'valid_runtime_smoke_proof "$RTK_PROOF_FILE" "$active_hook_rtk_version" "$hook_command"'; then
  pass "rtk-manager rejects stale proof without current RTK runtime state"
else
  fail "rtk-manager can still accept stale proof without current RTK runtime state"
fi

if contains "$RTK_MANAGER" 'if [ -n "$hook_command" ]; then' \
  && contains "$RTK_MANAGER" 'global_hook_present=true' \
  && contains "$RTK_MANAGER" 'settings_hook_state="active"' \
  && ! contains "$RTK_MANAGER" 'if [ -n "$hook_command" ] || [ "$legacy_hook" = "true" ]; then global_hook_present=true; fi'; then
  pass "rtk-manager treats settings JSON hook command as active-hook source of truth"
else
  fail "rtk-manager lets legacy hook files masquerade as active hooks"
fi

if contains "$RTK_MANAGER" 'fetch_latest_release()' \
  && contains "$RTK_MANAGER" 'cache_latest_release()' \
  && contains "$RTK_MANAGER" 'metadata="$(latest_metadata_or_die false)"' \
  && contains "$RTK_MANAGER" 'cache_latest_release "$metadata"'; then
  pass "rtk-manager separates metadata fetch from cache writes for dry-run/preflight safety"
else
  fail "rtk-manager does not clearly separate latest-release fetch and cache mutation"
fi

if contains "$RTK_MANAGER" 'no ownership takeover' \
  && contains "$RTK_MANAGER" 'VBW receipt exists but its binary is missing'; then
  pass "rtk-manager update path is ownership-aware for external and inconsistent installs"
else
  fail "rtk-manager update path missing ownership-aware guards"
fi

if contains "$RTK_MANAGER" 'rtk init -g --uninstall before binary removal' \
  && contains "$RTK_MANAGER" 'hook deactivation failed; preserved RTK binary and receipt'; then
  pass "rtk-manager uninstall deactivates hooks before removing managed binaries"
else
  fail "rtk-manager uninstall order can remove binary before hook deactivation"
fi

if contains "$RTK_CMD" 'managed_by_vbw=true` and either `global_hook_present=true` or `settings_json_valid=false' \
  && contains "$RTK_CMD" 'uninstall --dry-run --deactivate-hook' \
  && contains "$RTK_CMD" 'uninstall --yes --deactivate-hook'; then
  pass "rtk command routes hook-active managed uninstall through deactivate-hook flow"
else
  fail "rtk command missing hook-active managed deactivate-hook uninstall flow"
fi

if contains "$RTK_MANAGER" 'active or unreadable RTK settings hook state detected; pass --deactivate-hook' \
  && contains "$RTK_MANAGER" 'retire_install_receipt()' \
  && contains "$RTK_MANAGER" 'retire_install_receipt'; then
  pass "rtk-manager refuses unsafe managed uninstall and retires receipts after success"
else
  fail "rtk-manager missing unsafe-uninstall guard or receipt retirement"
fi

if ! contains "$RTK_MANAGER" '${auto_patch:+' \
  && ! contains "$RTK_MANAGER" '${hook_only:+' \
  && ! contains "$RTK_MANAGER" '${deactivate_hook:+'; then
  pass "rtk-manager preflight output avoids non-empty-string boolean expansion bugs"
else
  fail "rtk-manager still uses buggy boolean parameter expansion in preflight output"
fi

if contains "$RTK_MANAGER" 'binary_install_state="installed_not_on_path"' \
  && contains "$RTK_MANAGER" 'RTK binary exists at $receipt_path but is not on PATH' \
  && contains "$RTK_CMD" 'Enable Claude Code hook` when `rtk_present=true` and `global_hook_present=false' \
  && contains "$RTK_CMD" 'Show PATH guidance` when `managed_by_vbw=true` and `binary_install_state="installed_not_on_path"'; then
  pass "rtk status and command menu keep hook activation gated on PATH-visible RTK"
else
  fail "rtk status/menu missing PATH-visible RTK hook activation invariant"
fi

if contains "$RTK_MANAGER" 'settings_hook_state="unknown"' \
  && contains "$RTK_MANAGER" 'compatibility="settings_unreadable"' \
  && contains "$RTK_MANAGER" 'if ($s.settings_json_valid == false) then "WARN"' \
  && contains "$RTK_MANAGER" 'active or unreadable RTK settings hook state detected' \
  && contains "$RTK_CMD" 'settings_json_valid=false'; then
  pass "rtk-manager treats malformed settings as unknown/WARN and blocks unsafe uninstall"
else
  fail "rtk-manager missing malformed-settings unknown-state safety"
fi

if contains "$RTK_MANAGER" '$rtk_artifacts' \
  && contains "$RTK_MANAGER" 'legacy hook file' \
  && contains "$RTK_MANAGER" 'global RTK.md' \
  && contains "$RTK_MANAGER" 'CLAUDE.md @RTK.md reference' \
  && contains "$RTK_MANAGER" 'project .rtk files' \
  && contains "$RTK_MANAGER" 'VBW install receipt' \
  && contains "$RTK_MANAGER" 'RTK artifacts present with no active settings hook' \
  && contains "$DOCTOR_CMD" 'artifact-only'; then
  pass "doctor-json surfaces artifact-only RTK states as WARN with concrete evidence"
else
  fail "doctor-json missing artifact-only RTK WARN/detail handling"
fi

if ! grep -Fq 'status_json false true' "$RTK_MANAGER" \
  && contains "$RTK_MANAGER" 'status_json false false'; then
  pass "rtk verify path does not implicitly collect RTK stats"
else
  fail "rtk verify path still enables implicit stats collection"
fi

if contains "$DOCTOR_CMD" '### 18. RTK integration' \
  && contains "$DOCTOR_CMD" 'bash "{plugin-root}/scripts/rtk-manager.sh" doctor-json' \
  && contains "$DOCTOR_CMD" 'Result: {N}/18 passed' \
  && contains "$DOCTOR_CMD" 'PASS when `compatibility` is `"verified"` with a concrete `proof_source`, even if `updated_input_risk=true`' \
  && contains "$DOCTOR_CMD" 'When invoked with `--verbose`, include `diagnostic_caveat`/`upstream_issue`' \
  && contains "$DOCTOR_CMD" 'Doctor must not query the network, run RTK history/stats, or run runtime smoke'; then
  pass "doctor command includes RTK check 18 via plugin-root offline helper JSON"
else
  fail "doctor command missing plugin-root RTK check 18 offline helper contract"
fi

if contains "$STATUS_CMD" 'RTK external metrics' \
  && contains "$STATUS_CMD" 'status --json --stats' \
  && contains "$STATUS_CMD" 'RTK external: verified by runtime smoke proof' \
  && contains "$STATUS_CMD" 'Use compatibility-unverified wording only for `risk` or `hook_active_unverified` states without proof' \
  && contains "$STATUS_CMD" 'Default `/vbw:status` avoids RTK history, stats, network, and smoke work'; then
  pass "status command limits RTK to explicit external metrics"
else
  fail "status command missing explicit-only RTK metrics boundary"
fi

if contains "$RTK_CMD" 'smoke-start' \
  && contains "$RTK_CMD" 'ls -la .' \
  && contains "$RTK_CMD" 'git status --short' \
  && contains "$RTK_CMD" 'git log -n 2 --oneline' \
  && contains "$RTK_CMD" 'smoke-finish' \
  && contains "$RTK_CMD" 'separate Claude Code Bash tool calls exercise the RTK PreToolUse `updatedInput` rewrite behavior' \
  && contains "$RTK_CMD" 'Example anti-pattern' \
  && contains "$RTK_CMD" 'Do not use repo-wide `rtk grep`, `find .`, broad scans'; then
  pass "rtk command verifies with separate scoped Bash-tool smoke calls"
else
  fail "rtk command missing separate scoped Bash-tool smoke verification contract"
fi

if contains "$README" '/vbw:rtk' \
  && contains "$README" '`/vbw:rtk install` is complete setup' \
  && contains "$README" 'prefers `brew install rtk`' \
  && contains "$README" 'checksums.txt' \
  && contains "$README" 'config.toml' \
  && contains "$README" 'rtk init -g --auto-patch' \
  && contains "$README" '/vbw:rtk verify` can run a scoped Claude Code Bash-tool smoke' \
  && contains "$README" 'normal status and doctor warnings quiet for this local setup' \
  && contains "$README" 'anthropics/claude-code#15897 caveat' \
  && contains "$README" 'RTK savings are shown as external RTK metrics'; then
  pass "README documents complete RTK setup and verification boundaries"
else
  fail "README missing RTK managed setup docs"
fi

if contains "$ROOT/testing/list-contract-tests.sh" 'rtk-integration-contract'; then
  pass "RTK contract test is registered"
else
  fail "RTK contract test not registered"
fi

if contains "$ROOT/testing/verify-plugin-root-resolution.sh" 'rtk.md'; then
  pass "rtk.md included in plugin-root preamble coverage"
else
  fail "rtk.md missing from plugin-root preamble coverage"
fi

if not_contains_re "$SESSION_START" '[Rr][Tt][Kk]'; then
  pass "session-start has no recurring RTK context"
else
  fail "session-start must not mention RTK"
fi

implicit_targets=(
  "$ROOT/commands/init.md"
  "$ROOT/commands/vibe.md"
  "$ROOT/commands/status.md"
  "$ROOT/commands/doctor.md"
  "$SESSION_START"
)
for target in "${implicit_targets[@]}"; do
  rel="${target#$ROOT/}"
  if not_contains_re "$target" 'rtk-manager[.]sh[[:space:]]+(install|update|init|uninstall)|rtk[[:space:]]+init[[:space:]]+-g|curl[[:space:]].*[|][[:space:]]*sh'; then
    pass "$rel does not invoke implicit RTK setup"
  else
    fail "$rel invokes implicit RTK setup"
  fi
done

curl_pipe_matches=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if contains_re "$file" 'curl[[:space:]].*[|][[:space:]]*(ba)?sh'; then
    curl_pipe_matches+="${file#$ROOT/}"$'\n'
  fi
done < <(tracked_files 'scripts/*.sh')
if [ -z "$curl_pipe_matches" ]; then
  pass "managed shell scripts do not use curl-pipe-shell"
else
  fail $'managed shell scripts contain curl-pipe-shell:\n'"$curl_pipe_matches"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "RTK integration contract checks passed."
exit 0
