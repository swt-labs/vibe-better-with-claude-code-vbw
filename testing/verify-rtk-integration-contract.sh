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

if contains "$RTK_CMD" 'Binary install/update and Claude Code hook activation are separate operations' \
  && contains "$RTK_CMD" 'Never combine them into one confirmation' \
  && contains "$RTK_CMD" 'does not pipe downloaded shell scripts into sh'; then
  pass "rtk command documents separate consent boundaries and no curl-to-shell piping"
else
  fail "rtk command missing consent/no-curl-to-shell wording"
fi

if contains "$RTK_MANAGER" 'status --json [--check-updates] [--stats]' \
  && contains "$RTK_MANAGER" 'doctor-json' \
  && contains "$RTK_MANAGER" 'install [--dry-run] [--yes] [--allow-missing-checksum]' \
  && contains "$RTK_MANAGER" 'init [--dry-run] [--yes] [--auto-patch] [--hook-only]' \
  && contains "$RTK_MANAGER" 'uninstall [--dry-run] [--yes] [--deactivate-hook]'; then
  pass "rtk-manager exposes required subcommands and safety flags"
else
  fail "rtk-manager usage missing required subcommands or safety flags"
fi

if contains "$RTK_MANAGER" 'RTK_REPO_API="${RTK_REPO_API:-https://api.github.com/repos/rtk-ai/rtk/releases/latest}"' \
  && contains "$RTK_MANAGER" 'checksums.txt' \
  && contains "$RTK_MANAGER" 'verify_download_checksum' \
  && contains "$RTK_MANAGER" 'checksum mismatch'; then
  pass "rtk-manager uses latest GitHub release metadata with checksum verification"
else
  fail "rtk-manager missing latest-release checksum contract"
fi

if contains "$RTK_MANAGER" 'settings_hook_command()' \
  && contains "$RTK_MANAGER" 'rtk[[:space:]]+hook[[:space:]]+claude' \
  && contains "$RTK_MANAGER" 'rtk-rewrite[.]sh' \
  && contains "$RTK_MANAGER" 'RTK_CLAUDE_MD' \
  && contains "$RTK_MANAGER" 'RTK_GLOBAL_MD'; then
  pass "rtk-manager detects current and legacy RTK hook/artifact shapes"
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
  && ! grep -Fq 'jq empty "$RTK_PROOF_FILE"' "$RTK_MANAGER"; then
  pass "rtk-manager requires concrete runtime smoke proof before verified compatibility"
else
  fail "rtk-manager proof validation is too weak"
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
  && contains "$DOCTOR_CMD" 'Doctor must not query the network'; then
  pass "doctor command includes RTK check 18 via plugin-root offline helper JSON"
else
  fail "doctor command missing plugin-root RTK check 18 offline helper contract"
fi

if contains "$STATUS_CMD" 'RTK external metrics' \
  && contains "$STATUS_CMD" 'status --json --stats' \
  && contains "$STATUS_CMD" 'Default `/vbw:status` must not advertise RTK when absent'; then
  pass "status command limits RTK to explicit external metrics"
else
  fail "status command missing explicit-only RTK metrics boundary"
fi

if contains "$README" '/vbw:rtk' \
  && contains "$README" 'Binary install/update and Claude Code hook activation are separate' \
  && contains "$README" 'checksums.txt' \
  && contains "$README" 'RTK savings are shown as external RTK metrics'; then
  pass "README documents optional RTK managed setup boundaries"
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
    curl_pipe_matches="${curl_pipe_matches}${file#$ROOT/}\n"
  fi
done < <(tracked_files 'scripts/*.sh')
if [ -z "$curl_pipe_matches" ]; then
  pass "managed shell scripts do not use curl-pipe-shell"
else
  fail "managed shell scripts contain curl-pipe-shell:\n$curl_pipe_matches"
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
