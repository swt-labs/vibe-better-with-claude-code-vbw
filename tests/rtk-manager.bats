#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude"
  export VBW_RTK_DIR="$CLAUDE_CONFIG_DIR/vbw"
  mkdir -p "$CLAUDE_CONFIG_DIR" "$TEST_TEMP_DIR/bin"
  if command -v jq >/dev/null 2>&1; then
    ln -sf "$(command -v jq)" "$TEST_TEMP_DIR/bin/jq"
  fi
  local clean_path="" path_dir
  local -a _rtk_path_parts=()
  IFS=: read -r -a _rtk_path_parts <<< "${PATH:-}"
  for path_dir in "${_rtk_path_parts[@]}"; do
    [ -n "$path_dir" ] || continue
    [ -x "$path_dir/rtk" ] && continue
    [ -x "$path_dir/brew" ] && continue
    if [ -z "$clean_path" ]; then
      clean_path="$path_dir"
    else
      clean_path="$clean_path:$path_dir"
    fi
  done
  export PATH="$TEST_TEMP_DIR/bin${clean_path:+:$clean_path}"
}

teardown() {
  teardown_temp_dir
}

rtk_manager() {
  bash "$SCRIPTS_DIR/rtk-manager.sh" "$@"
}

expected_rtk_config_path() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) printf '%s\n' "$HOME/Library/Application Support/rtk/config.toml" ;;
    *) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/rtk/config.toml" ;;
  esac
}

write_fake_uname() {
  local os="${1:-Darwin}" arch="${2:-arm64}"
  cat > "$TEST_TEMP_DIR/bin/uname" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  -s) echo "$os" ;;
  -m) echo "$arch" ;;
  *) echo "$os" ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/bin/uname"
}

@test "rtk-manager: test harness PATH has no empty segments" {
  [[ "$PATH" == "$TEST_TEMP_DIR/bin" || "$PATH" == "$TEST_TEMP_DIR/bin:"* ]]
  [[ "$PATH" != *: ]]
  [[ ":$PATH:" != *::* ]]
}

write_fake_rtk() {
  local version="${1:-0.1.0}"
  local config_path
  config_path="$(expected_rtk_config_path)"
  cat > "$TEST_TEMP_DIR/bin/rtk" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/rtk-calls.log"
case "\${1:-}" in
  --version)
    echo "rtk $version"
    ;;
  gain)
    if [ "\${2:-}" = "--json" ]; then
      echo '{"average_savings_pct":47,"commands":3}'
    else
      echo 'average savings: 47%'
    fi
    ;;
  config)
    if [ "\${2:-}" = "--create" ]; then
      if [ "\${FAKE_RTK_CONFIG_CREATE_FAIL:-false}" = "true" ]; then exit 55; fi
      mkdir -p "$(dirname "$config_path")"
      cat > "$config_path" <<'TOML'
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
TOML
      exit 0
    fi
    if [ "\${FAKE_RTK_CONFIG_VALIDATE_FAIL:-false}" = "true" ]; then exit 57; fi
    [ -s "$config_path" ] || exit 56
    cat "$config_path"
    ;;
  init)
    if [ "\${2:-}" = "-g" ] && [ "\${3:-}" = "--uninstall" ]; then
      if [ -e "\$0" ]; then echo "uninstall_binary_exists=yes" >> "$TEST_TEMP_DIR/rtk-calls.log"; fi
      if [ "\${FAKE_RTK_UNINSTALL_FAIL:-false}" = "true" ]; then exit 44; fi
      if [ "\${FAKE_RTK_MUTATE_CONFIG_ON_UNINSTALL:-false}" = "true" ]; then
        echo mutated > "$CLAUDE_CONFIG_DIR/settings.json"
        echo mutated > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
        echo mutated > "$CLAUDE_CONFIG_DIR/RTK.md"
      fi
      rm -f "$CLAUDE_CONFIG_DIR/settings.json"
      exit 0
    fi
    if [ "\${FAKE_RTK_INIT_FAIL_WITH_MANUAL:-false}" = "true" ]; then
      echo 'Manual settings snippet: {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}'
      exit 42
    fi
    mkdir -p "$CLAUDE_CONFIG_DIR"
    cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
    ;;
  *)
    echo "fake rtk: unsupported \$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/bin/rtk"
}

write_failing_curl() {
  cat > "$TEST_TEMP_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TEST_TEMP_DIR/curl-called.log"
exit 99
EOF
  chmod +x "$TEST_TEMP_DIR/bin/curl"
}

write_fake_brew() {
  local version="${1:-9.9.9}" config_path
  config_path="$(expected_rtk_config_path)"
  cat > "$TEST_TEMP_DIR/bin/brew" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/brew-calls.log"
write_rtk() {
  cat > "$TEST_TEMP_DIR/bin/rtk" <<'RTK'
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/rtk-calls.log"
case "\${1:-}" in
  --version) echo "rtk $version" ;;
  gain)
    if [ "\${2:-}" = "--json" ]; then
      echo '{"average_savings_pct":47,"commands":3}'
    else
      echo 'average savings: 47%'
    fi
    ;;
  config)
    if [ "\${2:-}" = "--create" ]; then
      if [ "\${FAKE_RTK_CONFIG_CREATE_FAIL:-false}" = "true" ]; then exit 55; fi
      mkdir -p "$(dirname "$config_path")"
      cat > "$config_path" <<'TOML'
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
TOML
      exit 0
    fi
    [ -s "$config_path" ] || exit 56
    cat "$config_path"
    ;;
  init)
    if [ "\${FAKE_RTK_INIT_FAIL_WITH_MANUAL:-false}" = "true" ]; then
      echo 'Manual settings snippet: {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}'
      exit 42
    fi
    mkdir -p "$CLAUDE_CONFIG_DIR"
    cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
    ;;
  *) exit 0 ;;
esac
RTK
  chmod +x "$TEST_TEMP_DIR/bin/rtk"
}
case "\${1:-}" in
  install) write_rtk ;;
  upgrade) write_rtk ;;
  outdated)
    if [ "\${FAKE_BREW_OUTDATED:-false}" = "true" ]; then echo rtk; fi
    ;;
  uninstall) rm -f "$TEST_TEMP_DIR/bin/rtk" ;;
  list) [ -x "$TEST_TEMP_DIR/bin/rtk" ] ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/bin/brew"
}

release_target_asset() {
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64|Darwin:aarch64) echo "rtk-aarch64-apple-darwin.tar.gz" ;;
    Darwin:x86_64) echo "rtk-x86_64-apple-darwin.tar.gz" ;;
    Linux:arm64|Linux:aarch64) echo "rtk-aarch64-unknown-linux-gnu.tar.gz" ;;
    *) echo "rtk-x86_64-unknown-linux-musl.tar.gz" ;;
  esac
}

sha256_value() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

prepare_release_fixture() {
  local version="${1:-9.9.9}" mismatch="${2:-false}" checksum_mode="${3:-present}"
  local asset checksum config_path
  asset="$(release_target_asset)"
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$TEST_TEMP_DIR/release/payload"
  cat > "$TEST_TEMP_DIR/release/payload/rtk" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/installed-rtk-calls.log"
case "\${1:-}" in
  --version) echo "rtk $version" ;;
  gain)
    if [ "\${FAKE_INSTALLED_RTK_GAIN_FAIL:-false}" = "true" ]; then exit 58; fi
    echo 'average savings: 47%'
    ;;
  config)
    if [ "\${2:-}" = "--create" ]; then
      mkdir -p "$(dirname "$config_path")"
      cat > "$config_path" <<'TOML'
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
TOML
      exit 0
    fi
    [ -s "$config_path" ] || exit 56
    cat "$config_path"
    ;;
  init)
    mkdir -p "$CLAUDE_CONFIG_DIR"
    cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
    ;;
  *) echo "installed fake rtk $version" ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/release/payload/rtk"
  (cd "$TEST_TEMP_DIR/release/payload" && tar -czf "$TEST_TEMP_DIR/release/$asset" rtk)
  checksum="$(sha256_value "$TEST_TEMP_DIR/release/$asset")"
  if [ "$mismatch" = "true" ]; then
    checksum="0000000000000000000000000000000000000000000000000000000000000000"
  fi
  case "$checksum_mode" in
    present) printf '%s  %s\n' "$checksum" "$asset" > "$TEST_TEMP_DIR/release/checksums.txt" ;;
    missing-asset) printf '%s  %s\n' "$checksum" "other-asset.tar.gz" > "$TEST_TEMP_DIR/release/checksums.txt" ;;
    empty) : > "$TEST_TEMP_DIR/release/checksums.txt" ;;
    no-asset) : > "$TEST_TEMP_DIR/release/checksums.txt" ;;
  esac
  cat > "$TEST_TEMP_DIR/release/release.json" <<EOF
{
  "tag_name": "v$version",
  "assets": [
    {"name": "$asset", "browser_download_url": "https://example.invalid/$asset"}
    $(if [ "$checksum_mode" != "no-asset" ]; then printf ',\n    {"name": "checksums.txt", "browser_download_url": "https://example.invalid/checksums.txt"}'; fi)
  ]
}
EOF
}

tar_supports_rewrite() {
  local probe_dir
  if tar --version 2>/dev/null | grep -qi 'gnu tar'; then
    echo "gnu"
  else
    probe_dir="$(mktemp -d)"
    echo x > "$probe_dir/x"
    if tar -czf "$probe_dir/out.tar.gz" -C "$probe_dir" -s '|^x$|y|' x >/dev/null 2>&1; then
      rm -rf "$probe_dir"
      echo "bsd"
      return 0
    fi
    rm -rf "$probe_dir"
    echo ""
  fi
}

create_rewritten_tar() {
  local archive="$1" payload_dir="$2" source_name="$3" target_name="$4" mode="$5"
  case "$mode" in
    gnu)
      if [[ "$target_name" = /* ]]; then
        tar -P -czf "$archive" -C "$payload_dir" --transform "s|^${source_name}$|${target_name}|" rtk "$source_name"
      else
        tar -czf "$archive" -C "$payload_dir" --transform "s|^${source_name}$|${target_name}|" rtk "$source_name"
      fi
      ;;
    bsd)
      if [[ "$target_name" = /* ]]; then
        tar -P -czf "$archive" -C "$payload_dir" -s "|^${source_name}$|${target_name}|" rtk "$source_name"
      else
        tar -czf "$archive" -C "$payload_dir" -s "|^${source_name}$|${target_name}|" rtk "$source_name"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

prepare_malicious_release_fixture() {
  local unsafe_member="$1" version="${2:-9.9.9}" mode asset checksum
  mode="$(tar_supports_rewrite)"
  [ -n "$mode" ] || return 1
  asset="$(release_target_asset)"
  mkdir -p "$TEST_TEMP_DIR/release/payload"
  cat > "$TEST_TEMP_DIR/release/payload/rtk" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version) echo "rtk $version" ;;
  *) echo "installed fake rtk $version" ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/release/payload/rtk"
  echo "evil" > "$TEST_TEMP_DIR/release/payload/evil"
  create_rewritten_tar "$TEST_TEMP_DIR/release/$asset" "$TEST_TEMP_DIR/release/payload" evil "$unsafe_member" "$mode" || return 1
  checksum="$(sha256_value "$TEST_TEMP_DIR/release/$asset")"
  printf '%s  %s\n' "$checksum" "$asset" > "$TEST_TEMP_DIR/release/checksums.txt"
  cat > "$TEST_TEMP_DIR/release/release.json" <<EOF
{
  "tag_name": "v$version",
  "assets": [
    {"name": "$asset", "browser_download_url": "https://example.invalid/$asset"},
    {"name": "checksums.txt", "browser_download_url": "https://example.invalid/checksums.txt"}
  ]
}
EOF
}

prepare_ambiguous_rtk_release_fixture() {
  local version="${1:-9.9.9}" asset checksum
  asset="$(release_target_asset)"
  mkdir -p "$TEST_TEMP_DIR/release/payload/nested"
  cat > "$TEST_TEMP_DIR/release/payload/rtk" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version) echo "rtk $version" ;;
  *) echo "installed fake rtk $version" ;;
esac
EOF
  cp "$TEST_TEMP_DIR/release/payload/rtk" "$TEST_TEMP_DIR/release/payload/nested/rtk"
  chmod +x "$TEST_TEMP_DIR/release/payload/rtk" "$TEST_TEMP_DIR/release/payload/nested/rtk"
  (cd "$TEST_TEMP_DIR/release/payload" && tar -czf "$TEST_TEMP_DIR/release/$asset" rtk nested/rtk)
  checksum="$(sha256_value "$TEST_TEMP_DIR/release/$asset")"
  printf '%s  %s\n' "$checksum" "$asset" > "$TEST_TEMP_DIR/release/checksums.txt"
  cat > "$TEST_TEMP_DIR/release/release.json" <<EOF
{
  "tag_name": "v$version",
  "assets": [
    {"name": "$asset", "browser_download_url": "https://example.invalid/$asset"},
    {"name": "checksums.txt", "browser_download_url": "https://example.invalid/checksums.txt"}
  ]
}
EOF
}

create_managed_rtk() {
  local version="${1:-0.1.0}" dir="${2:-$TEST_TEMP_DIR/managed-bin}" binary config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$dir" "$VBW_RTK_DIR"
  binary="$dir/rtk"
  cat > "$binary" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/rtk-calls.log"
case "\${1:-}" in
  --version) echo "rtk $version" ;;
  gain) echo 'average savings: 47%' ;;
  config)
    if [ "\${2:-}" = "--create" ]; then
      mkdir -p "$(dirname "$config_path")"
      cat > "$config_path" <<'TOML'
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
TOML
      exit 0
    fi
    [ -s "$config_path" ] || exit 56
    cat "$config_path"
    ;;
  init)
    if [ "\${2:-}" = "-g" ] && [ "\${3:-}" = "--uninstall" ]; then
      if [ -e "\$0" ]; then echo "uninstall_binary_exists=yes" >> "$TEST_TEMP_DIR/rtk-calls.log"; fi
      if [ "\${FAKE_RTK_UNINSTALL_FAIL:-false}" = "true" ]; then exit 44; fi
      if [ "\${FAKE_RTK_MUTATE_CONFIG_ON_UNINSTALL:-false}" = "true" ]; then
        echo mutated > "$CLAUDE_CONFIG_DIR/settings.json"
        echo mutated > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
        echo mutated > "$CLAUDE_CONFIG_DIR/RTK.md"
      fi
      exit 0
    fi
    mkdir -p "$CLAUDE_CONFIG_DIR"
    cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
    ;;
esac
EOF
  chmod +x "$binary"
  jq -n --arg binary "$binary" --arg version "$version" \
    '{manager:"vbw", binary_path:$binary, installed_version:$version, method:"github-release"}' > "$VBW_RTK_DIR/rtk-install.json"
  printf '%s\n' "$binary"
}

write_valid_smoke_proof() {
  mkdir -p "$VBW_RTK_DIR"
  local config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  printf '%s\n' '[tracking]' 'enabled = true' 'history_days = 90' > "$config_path"
  cat > "$VBW_RTK_DIR/rtk-compatibility-proof.json" <<'JSON'
{
  "proof_type": "runtime_smoke",
  "status": "pass",
  "timestamp": "2026-04-27T00:00:00Z",
  "rtk_version": "0.1.0",
  "hook_command": "rtk hook claude",
  "updated_input_verified": true,
  "rtk_rewrite_observed": true,
  "vbw_bash_guard_verified": true,
  "commands": ["git status", "echo ok"]
}
JSON
}

write_release_curl() {
  cat > "$TEST_TEMP_DIR/bin/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_TEMP_DIR/curl-calls.log"
out=""
url=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o)
      out="\${2:-}"
      shift 2
      ;;
    --max-time|--retry|--retry-delay)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="\$1"
      shift
      ;;
  esac
done
case "\$url" in
  *releases/latest)
    cat "$TEST_TEMP_DIR/release/release.json"
    ;;
  *checksums.txt)
    if [ -n "\$out" ]; then cp "$TEST_TEMP_DIR/release/checksums.txt" "\$out"; else cat "$TEST_TEMP_DIR/release/checksums.txt"; fi
    ;;
  *tar.gz)
    if [ -n "\$out" ]; then cp "$TEST_TEMP_DIR/release/$(release_target_asset)" "\$out"; else cat "$TEST_TEMP_DIR/release/$(release_target_asset)"; fi
    ;;
  *)
    echo "unexpected URL: \$url" >&2
    exit 9
    ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/bin/curl"
}

@test "rtk-manager: default status is offline and absent when RTK missing" {
  write_failing_curl
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == false'
  echo "$output" | jq -e '.compatibility == "absent"'
  echo "$output" | jq -e '.version_source == "none"'
  echo "$output" | jq -e '.config_present == false'
  echo "$output" | jq -e '.config_state == "missing"'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: binary-only status does not call gain by default" {
  write_fake_rtk "0.1.0"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == true'
  echo "$output" | jq -e '.rtk_version == "0.1.0"'
  echo "$output" | jq -e '.compatibility == "binary_only"'
  echo "$output" | jq -e '.config_state == "missing"'
  echo "$output" | jq -e '.next_action == "init"'
  echo "$output" | jq -e '.config_next_action == "init"'
  ! grep -Fq 'gain --json' "$TEST_TEMP_DIR/rtk-calls.log"
}

@test "rtk-manager: status detects RTK version when PATH contains spaces" {
  local spaced_bin="$TEST_TEMP_DIR/bin with space"
  mkdir -p "$spaced_bin"
  cat > "$spaced_bin/rtk" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "rtk 1.2.3" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$spaced_bin/rtk"
  export PATH="$spaced_bin:$PATH"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == true'
  echo "$output" | jq -e --arg path "$spaced_bin/rtk" '.rtk_path == $path'
  echo "$output" | jq -e '.rtk_version == "1.2.3"'
}

@test "rtk-manager: stats work when PATH contains spaces" {
  local spaced_bin="$TEST_TEMP_DIR/bin with space"
  mkdir -p "$spaced_bin"
  cat > "$spaced_bin/rtk" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "rtk 1.2.3" ;;
  gain)
    if [ "${2:-}" = "--json" ]; then
      echo '{"average_savings_pct":88}'
    fi
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$spaced_bin/rtk"
  export PATH="$spaced_bin:$PATH"
  run rtk_manager status --json --stats
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg path "$spaced_bin/rtk" '.rtk_path == $path'
  echo "$output" | jq -e '.stats.average_savings_pct == 88'
}

@test "rtk-manager: detects current RTK settings hook and updatedInput risk with VBW hook" {
  write_fake_rtk "0.1.0"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e '.global_hook_command == "rtk hook claude"'
  echo "$output" | jq -e '.multiple_bash_pretooluse_hooks_detected == true'
  echo "$output" | jq -e --arg typo_key "multiple_bash_pre""tookuse_hooks_detected" 'has($typo_key) | not'
  echo "$output" | jq -e '.updated_input_risk == true'
  echo "$output" | jq -e '.compatibility == "risk"'
  echo "$output" | jq -e '.next_action == "verify"'
  echo "$output" | jq -e '.config_next_action == "init"'
}

@test "rtk-manager: malformed settings JSON is reported without breaking status" {
  write_fake_rtk "0.1.0"
  printf '{not-json' > "$CLAUDE_CONFIG_DIR/settings.json"
  local config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  printf '%s\n' '[tracking]' 'enabled = true' > "$config_path"
  export FAKE_RTK_CONFIG_VALIDATE_FAIL=true
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.settings_json_valid == false'
  echo "$output" | jq -e '.settings_hook_state == "unknown"'
  echo "$output" | jq -e '.global_hook_present == false'
  echo "$output" | jq -e '.compatibility == "settings_unreadable"'
  echo "$output" | jq -e '.config_state == "config_error"'
  echo "$output" | jq -e '.next_action == "repair_settings"'
  echo "$output" | jq -e '.config_next_action == "init"'
  echo "$output" | jq -e '.next_action != "repair_config" and .config_next_action != "repair_config"'
}

@test "rtk-manager: config validation failure is reported in status and doctor" {
  write_fake_rtk "0.1.0"
  local config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  printf '%s\n' '[tracking]' 'enabled = true' > "$config_path"
  export FAKE_RTK_CONFIG_VALIDATE_FAIL=true
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.config_present == true'
  echo "$output" | jq -e '.config_state == "config_error"'
  echo "$output" | jq -e '.next_action == "init"'
  echo "$output" | jq -e '.config_next_action == "init"'
  echo "$output" | jq -e '.next_action != "repair_config" and .config_next_action != "repair_config"'
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.doctor_status == "WARN"'
  echo "$output" | jq -e '.doctor_detail | test("config unreadable|config")'
}

@test "rtk-manager: config error with hook risk preserves verify route" {
  write_fake_rtk "0.1.0"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  local config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  printf '%s\n' '[tracking]' 'enabled = true' > "$config_path"
  export FAKE_RTK_CONFIG_VALIDATE_FAIL=true
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.compatibility == "risk"'
  echo "$output" | jq -e '.config_state == "config_error"'
  echo "$output" | jq -e '.next_action == "verify"'
  echo "$output" | jq -e '.config_next_action == "init"'
  echo "$output" | jq -e '.next_action != "repair_config" and .config_next_action != "repair_config"'
}

@test "rtk-manager: config error without PATH RTK maps config action to install" {
  write_failing_curl
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  local config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  : > "$config_path"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == false'
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e '.config_state == "config_error"'
  echo "$output" | jq -e '.config_next_action == "install"'
  echo "$output" | jq -e '.next_action != "repair_config" and .config_next_action != "repair_config"'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: check-updates queries latest release only on explicit flag" {
  write_fake_rtk "0.1.0"
  prepare_release_fixture "9.9.9"
  write_release_curl
  export RTK_CURL_MAX_TIME=7
  run rtk_manager status --json --check-updates
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.latest_version == "9.9.9"'
  echo "$output" | jq -e '.update_available == true'
  [ -f "$VBW_RTK_DIR/rtk-latest-release.json" ]
  grep -Fq -- '--max-time 7' "$TEST_TEMP_DIR/curl-calls.log"
}

@test "rtk-manager: install dry-run shows preflight and does not mutate" {
  prepare_release_fixture "9.9.9"
  write_release_curl
  run rtk_manager install --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"RTK install preflight"* ]]
  [[ "$output" == *"Method:"* ]]
  [[ "$output" == *"Will run:"* ]]
  [[ "$output" == *"Fallback:"* ]]
  [[ "$output" == *"rtk init -g --auto-patch"* ]]
  [[ "$output" == *"no curl-pipe-shell"* ]]
  [ ! -e "$HOME/.local/bin/rtk" ]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
  [ ! -f "$VBW_RTK_DIR/rtk-latest-release.json" ]
}

@test "rtk-manager: install without confirmation aborts after preflight" {
  prepare_release_fixture "9.9.9"
  write_release_curl
  run rtk_manager install
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires explicit confirmation"* ]]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
  [ ! -f "$VBW_RTK_DIR/rtk-latest-release.json" ]
}

@test "rtk-manager: off-PATH managed install verifies checksum, writes receipt, and completes setup" {
  prepare_release_fixture "9.9.9"
  write_release_curl
  export RTK_CURL_MAX_TIME=7
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install-bin"
  run rtk_manager install --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Binary: verified"* ]]
  [[ "$output" == *"Config: created_after_missing"* ]]
  [[ "$output" == *"Hook: active via VBW settings fallback patch"* ]]
  [[ "$output" == *"RTK install setup complete"* ]]
  [ -x "$TEST_TEMP_DIR/install-bin/rtk" ]
  [ -f "$VBW_RTK_DIR/rtk-install.json" ]
  jq -e '.manager == "vbw"' "$VBW_RTK_DIR/rtk-install.json"
  jq -e '.installed_version == "9.9.9"' "$VBW_RTK_DIR/rtk-install.json"
  jq -e '.verified_checksum != ""' "$VBW_RTK_DIR/rtk-install.json"
  [ -s "$(expected_rtk_config_path)" ]
  grep -Fq -- '--version' "$TEST_TEMP_DIR/installed-rtk-calls.log"
  grep -Fxq 'gain' "$TEST_TEMP_DIR/installed-rtk-calls.log"
  grep -Fq -- 'config --create' "$TEST_TEMP_DIR/installed-rtk-calls.log"
  grep -Fq -- 'init -g --auto-patch' "$TEST_TEMP_DIR/installed-rtk-calls.log"
  local expected_command
  expected_command="'$TEST_TEMP_DIR/install-bin/rtk' hook claude"
  jq -e --arg command "$expected_command" '.hooks.PreToolUse[0].hooks[0].command == $command' "$CLAUDE_CONFIG_DIR/settings.json"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.managed_by_vbw == true'
  echo "$output" | jq -e '.binary_install_state == "installed_not_on_path"'
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e --arg path "$TEST_TEMP_DIR/install-bin/rtk" '.active_hook_rtk_path == $path'
  [ "$(grep -c -- '--max-time 7' "$TEST_TEMP_DIR/curl-calls.log")" -ge 3 ]
}

@test "rtk-manager: off-PATH managed install with spaces writes parseable absolute hook" {
  prepare_release_fixture "9.9.9"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install bin with space"
  run rtk_manager install --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hook: active via VBW settings fallback patch"* ]]
  [ -x "$RTK_INSTALL_DIR/rtk" ]
  jq -e '.installed_version == "9.9.9"' "$VBW_RTK_DIR/rtk-install.json"
  local expected_command
  expected_command="'$RTK_INSTALL_DIR/rtk' hook claude"
  jq -e --arg command "$expected_command" '.hooks.PreToolUse[0].hooks[0].command == $command' "$CLAUDE_CONFIG_DIR/settings.json"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg path "$RTK_INSTALL_DIR/rtk" '.active_hook_rtk_path == $path'
}

@test "rtk-manager: off-PATH managed install with apostrophe writes parseable absolute hook" {
  prepare_release_fixture "9.9.9"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/rtk QA's bin"
  run rtk_manager install --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hook: active via VBW settings fallback patch"* ]]
  [ -x "$RTK_INSTALL_DIR/rtk" ]
  local expected_command
  expected_command="'${RTK_INSTALL_DIR%\'*}'\\''${RTK_INSTALL_DIR#*\'}/rtk' hook claude"
  jq -e --arg command "$expected_command" '.hooks.PreToolUse[0].hooks[0].command == $command' "$CLAUDE_CONFIG_DIR/settings.json"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.binary_install_state == "installed_not_on_path"'
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e --arg path "$RTK_INSTALL_DIR/rtk" '.active_hook_rtk_path == $path'
}

@test "rtk-manager: install fails honestly when required setup probe fails" {
  prepare_release_fixture "9.9.9"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install-bin"
  export FAKE_INSTALLED_RTK_GAIN_FAIL=true
  run rtk_manager install --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"RTK binary probe failed"* ]]
  [[ "$output" != *"RTK install setup complete"* ]]
  [ -x "$TEST_TEMP_DIR/install-bin/rtk" ]
  [ -f "$VBW_RTK_DIR/rtk-install.json" ]
  [ ! -f "$CLAUDE_CONFIG_DIR/settings.json" ]
}

@test "rtk-manager: install runs full setup when GitHub binary is on PATH" {
  prepare_release_fixture "9.9.9"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/bin"
  run rtk_manager install --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Binary: verified"* ]]
  [[ "$output" == *"Config: created_after_missing"* ]]
  [[ "$output" == *"Hook: active"* ]]
  [ -s "$(expected_rtk_config_path)" ]
  jq -e '.hooks.PreToolUse[0].hooks[0].command | test("rtk hook claude")' "$CLAUDE_CONFIG_DIR/settings.json"
  grep -Fq -- '--version' "$TEST_TEMP_DIR/installed-rtk-calls.log"
  grep -Fxq 'gain' "$TEST_TEMP_DIR/installed-rtk-calls.log"
  grep -Fq -- 'config --create' "$TEST_TEMP_DIR/installed-rtk-calls.log"
  grep -Fq -- 'init -g --auto-patch' "$TEST_TEMP_DIR/installed-rtk-calls.log"
}

@test "rtk-manager: install prefers Homebrew on macOS with fake brew" {
  write_fake_uname Darwin arm64
  write_fake_brew "9.9.9"
  run rtk_manager install --yes
  [ "$status" -eq 0 ]
  grep -Fxq 'install rtk' "$TEST_TEMP_DIR/brew-calls.log"
  jq -e '.method == "homebrew"' "$VBW_RTK_DIR/rtk-install.json"
  jq -e '.binary_path | endswith("/rtk")' "$VBW_RTK_DIR/rtk-install.json"
  [ -s "$HOME/Library/Application Support/rtk/config.toml" ]
  jq -e '.global_hook_present == true' < <(rtk_manager status --json)
}

@test "rtk-manager: managed install aborts on checksum mismatch" {
  prepare_release_fixture "9.9.9" "true"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install-bin"
  run rtk_manager install --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -e "$TEST_TEMP_DIR/install-bin/rtk" ]
}

@test "rtk-manager: managed install rejects archive traversal member" {
  prepare_malicious_release_fixture "../outside-marker" || skip "tar rewrite support unavailable"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install-bin"
  run rtk_manager install --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe RTK archive member path"* ]]
  [ ! -e "$TEST_TEMP_DIR/install-bin/rtk" ]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
  [ ! -e "$TEST_TEMP_DIR/outside-marker" ]
}

@test "rtk-manager: managed install rejects archive absolute member" {
  prepare_malicious_release_fixture "$TEST_TEMP_DIR/outside-marker" || skip "tar rewrite support unavailable"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install-bin"
  run rtk_manager install --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe RTK archive member path"* ]]
  [ ! -e "$TEST_TEMP_DIR/install-bin/rtk" ]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
  [ ! -e "$TEST_TEMP_DIR/outside-marker" ]
}

@test "rtk-manager: managed install rejects ambiguous rtk members" {
  prepare_ambiguous_rtk_release_fixture "9.9.9"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install-bin"
  run rtk_manager install --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"multiple rtk binaries"* ]]
  [ ! -e "$TEST_TEMP_DIR/install-bin/rtk" ]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
}

@test "rtk-manager: init dry-run warns about hook mutation and compatibility" {
  write_fake_rtk "0.1.0"
  run rtk_manager init --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"RTK hook preflight"* ]]
  [[ "$output" == *"rtk init -g"* ]]
  [[ "$output" == *"--auto-patch"* ]]
  [[ "$output" != *"--hook-only"* ]]
  [[ "$output" == *"Fallback:"* ]]
  [[ "$output" == *"updatedInput"* ]]
  [ ! -f "$CLAUDE_CONFIG_DIR/settings.json" ]
}

@test "rtk-manager: init accepts legacy auto-patch flag without advertising it as a toggle" {
  write_fake_rtk "0.1.0"
  run rtk_manager init --dry-run --auto-patch --hook-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"--auto-patch"* ]]
  [[ "$output" == *"--hook-only"* ]]
  run rtk_manager help
  [ "$status" -eq 0 ]
  [[ "$output" == *"init [--dry-run] [--yes] [--hook-only]"* ]]
  [[ "$output" != *"init [--dry-run] [--yes] [--auto-patch] [--hook-only]"* ]]
}

@test "rtk-manager: init creates missing RTK config and activates hook" {
  write_fake_rtk "0.1.0"
  run rtk_manager init --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Binary: verified"* ]]
  [[ "$output" == *"Config: created_after_missing"* ]]
  [[ "$output" == *"Hook: active"* ]]
  [ -s "$(expected_rtk_config_path)" ]
  jq -e '.config_present == true' < <(rtk_manager status --json)
  grep -Fq -- 'init -g --auto-patch' "$TEST_TEMP_DIR/rtk-calls.log"
}

@test "rtk-manager: init preserves existing RTK config" {
  write_fake_rtk "0.1.0"
  local config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  printf '%s\n' '[tracking]' 'enabled = false' > "$config_path"
  run rtk_manager init --yes
  [ "$status" -eq 0 ]
  grep -Fq 'enabled = false' "$config_path"
}

@test "rtk-manager: init fallback creates non-telemetry config when rtk config create fails" {
  write_fake_rtk "0.1.0"
  export FAKE_RTK_CONFIG_CREATE_FAIL=true
  run rtk_manager init --yes
  [ "$status" -eq 0 ]
  local config_path
  config_path="$(expected_rtk_config_path)"
  [ -s "$config_path" ]
  grep -Fq '[tracking]' "$config_path"
  grep -Fq 'exclude_commands = []' "$config_path"
  ! grep -Fq '[telemetry]' "$config_path"
}

@test "rtk-manager: init handles macOS Application Support config path with spaces" {
  write_fake_uname Darwin arm64
  write_fake_rtk "0.1.0"
  run rtk_manager init --yes
  [ "$status" -eq 0 ]
  [ -s "$HOME/Library/Application Support/rtk/config.toml" ]
}

@test "rtk-manager: fallback settings patch activates hook after RTK auto-patch failure" {
  write_fake_rtk "0.1.0"
  export FAKE_RTK_INIT_FAIL_WITH_MANUAL=true
  run rtk_manager init --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hook: active via VBW settings fallback patch"* ]]
  jq -e '.hooks.PreToolUse[0].matcher == "Bash"' "$CLAUDE_CONFIG_DIR/settings.json"
  jq -e '.hooks.PreToolUse[0].hooks[0].command | test("rtk.*hook claude")' "$CLAUDE_CONFIG_DIR/settings.json"
}

@test "rtk-manager: fallback settings patch preserves malformed settings" {
  write_fake_rtk "0.1.0"
  printf '{not-json' > "$CLAUDE_CONFIG_DIR/settings.json"
  export FAKE_RTK_INIT_FAIL_WITH_MANUAL=true
  run rtk_manager init --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"settings preserved"* ]]
  [ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = "{not-json" ]
}

@test "rtk-manager: doctor-json skips absent RTK" {
  write_failing_curl
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.doctor_status == "SKIP"'
  echo "$output" | jq -e '.doctor_detail | test("not installed")'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: doctor-json with RTK present does not collect RTK gain stats" {
  write_fake_rtk "0.1.0"
  write_failing_curl
  : > "$TEST_TEMP_DIR/rtk-calls.log"
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == true'
  echo "$output" | jq -e '.stats == null'
  echo "$output" | jq -e '.config_state == "missing"'
  echo "$output" | jq -e '.doctor_status == "WARN"'
  grep -Fxq -- '--version' "$TEST_TEMP_DIR/rtk-calls.log"
  ! grep -Fxq 'gain' "$TEST_TEMP_DIR/rtk-calls.log"
  ! grep -Fq 'gain --json' "$TEST_TEMP_DIR/rtk-calls.log"
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: stats are explicit and labeled separately in JSON" {
  write_fake_rtk "0.1.0"
  run rtk_manager status --json --stats
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stats.average_savings_pct == 47'
}

@test "rtk-manager: verify does not collect RTK gain stats" {
  write_fake_rtk "0.1.0"
  : > "$TEST_TEMP_DIR/rtk-calls.log"
  run rtk_manager verify
  [ "$status" -eq 0 ]
  ! grep -Fq 'gain --json' "$TEST_TEMP_DIR/rtk-calls.log"
  run rtk_manager verify --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stats == null'
  ! grep -Fq 'gain --json' "$TEST_TEMP_DIR/rtk-calls.log"
}

@test "rtk-manager: doctor-json warns on malformed settings without network" {
  write_failing_curl
  printf '{not-json' > "$CLAUDE_CONFIG_DIR/settings.json"
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.settings_json_valid == false'
  echo "$output" | jq -e '.doctor_status == "WARN"'
  echo "$output" | jq -e '.doctor_detail | test("settings unreadable|Settings unreadable|Claude settings unreadable")'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: doctor-json warns on legacy hook artifact without network" {
  write_failing_curl
  mkdir -p "$CLAUDE_CONFIG_DIR/hooks"
  touch "$CLAUDE_CONFIG_DIR/hooks/rtk-rewrite.sh"
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.legacy_hook_file_present == true'
  echo "$output" | jq -e '.global_hook_present == false'
  echo "$output" | jq -e '.doctor_status == "WARN"'
  echo "$output" | jq -e '.doctor_detail | test("legacy hook file")'
  ! echo "$output" | jq -e '.doctor_detail | test("not installed; optional")'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: doctor-json warns on global RTK docs artifacts without network" {
  write_failing_curl
  echo "RTK docs" > "$CLAUDE_CONFIG_DIR/RTK.md"
  echo "@RTK.md" > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.global_rtk_md_present == true'
  echo "$output" | jq -e '.global_claude_ref_present == true'
  echo "$output" | jq -e '.doctor_status == "WARN"'
  echo "$output" | jq -e '.doctor_detail | test("global RTK.md")'
  echo "$output" | jq -e '.doctor_detail | test("CLAUDE.md @RTK.md reference")'
  ! echo "$output" | jq -e '.doctor_detail | test("not installed; optional")'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: doctor-json warns on project RTK artifact without network" {
  write_failing_curl
  mkdir -p "$TEST_TEMP_DIR/project/.rtk"
  touch "$TEST_TEMP_DIR/project/.rtk/filters.toml"
  cd "$TEST_TEMP_DIR/project"
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.project_local_present == true'
  echo "$output" | jq -e '.doctor_status == "WARN"'
  echo "$output" | jq -e '.doctor_detail | test("project .rtk files")'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: arbitrary valid proof JSON does not verify compatibility" {
  write_fake_rtk "0.1.0"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  mkdir -p "$VBW_RTK_DIR"
  echo '{"anything":"valid json"}' > "$VBW_RTK_DIR/rtk-compatibility-proof.json"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proof_source == ""'
  echo "$output" | jq -e '.compatibility == "risk"'
}

@test "rtk-manager: stale proof without runnable RTK does not verify doctor" {
  write_failing_curl
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  mkdir -p "$VBW_RTK_DIR"
  cat > "$VBW_RTK_DIR/rtk-compatibility-proof.json" <<'JSON'
{
  "proof_type": "runtime_smoke",
  "status": "pass",
  "timestamp": "2026-04-27T00:00:00Z",
  "rtk_version": "0.1.0",
  "hook_command": "rtk hook claude",
  "updated_input_verified": true,
  "rtk_rewrite_observed": true,
  "vbw_bash_guard_verified": true,
  "commands": ["git status"]
}
JSON
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == false'
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e '.proof_source == ""'
  echo "$output" | jq -e '.compatibility != "verified"'
  echo "$output" | jq -e '.restart_required == true'
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.doctor_status == "WARN"'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: stale proof does not verify missing quoted hook binary using unrelated PATH RTK" {
  write_failing_curl
  write_fake_rtk "0.1.0"
  local missing_binary="$TEST_TEMP_DIR/missing bin/rtk"
  local quoted_command="\"$missing_binary\" hook claude"
  jq -n --arg command "$quoted_command" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  mkdir -p "$VBW_RTK_DIR"
  jq -n --arg command "$quoted_command" '{proof_type:"runtime_smoke",status:"pass",timestamp:"2026-04-27T00:00:00Z",rtk_version:"0.1.0",hook_command:$command,updated_input_verified:true,rtk_rewrite_observed:true,vbw_bash_guard_verified:true,commands:["git status"]}' > "$VBW_RTK_DIR/rtk-compatibility-proof.json"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == true'
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e --arg command "$quoted_command" '.global_hook_command == $command'
  echo "$output" | jq -e '.active_hook_rtk_path == ""'
  echo "$output" | jq -e '.proof_source == ""'
  echo "$output" | jq -e '.compatibility != "verified"'
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.doctor_status == "WARN"'
  [ ! -f "$TEST_TEMP_DIR/curl-called.log" ]
}

@test "rtk-manager: proof version must match current RTK version" {
  write_fake_rtk "0.1.0"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  mkdir -p "$VBW_RTK_DIR"
  cat > "$VBW_RTK_DIR/rtk-compatibility-proof.json" <<'JSON'
{
  "proof_type": "runtime_smoke",
  "status": "pass",
  "timestamp": "2026-04-27T00:00:00Z",
  "rtk_version": "9.9.9",
  "hook_command": "rtk hook claude",
  "updated_input_verified": true,
  "rtk_rewrite_observed": true,
  "vbw_bash_guard_verified": true,
  "commands": ["git status"]
}
JSON
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == true'
  echo "$output" | jq -e '.proof_source == ""'
  echo "$output" | jq -e '.compatibility != "verified"'
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.doctor_status == "WARN"'
}

@test "rtk-manager: validated runtime smoke proof can produce doctor PASS" {
  write_fake_rtk "0.1.0"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  write_valid_smoke_proof
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == true'
  echo "$output" | jq -e '.compatibility == "verified"'
  echo "$output" | jq -e '.doctor_status == "PASS"'
}

@test "rtk-manager: validated quoted absolute hook proof can produce doctor PASS" {
  local binary
  binary="$(create_managed_rtk "0.1.0" "$TEST_TEMP_DIR/managed bin with space")"
  local config_path
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  printf '%s\n' '[tracking]' 'enabled = true' 'history_days = 90' > "$config_path"
  local quoted_command="\"$binary\" hook claude"
  jq -n --arg command "$quoted_command" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  mkdir -p "$VBW_RTK_DIR"
  jq -n --arg command "$quoted_command" '{proof_type:"runtime_smoke",status:"pass",timestamp:"2026-04-27T00:00:00Z",rtk_version:"0.1.0",hook_command:$command,updated_input_verified:true,rtk_rewrite_observed:true,vbw_bash_guard_verified:true,commands:["git status"]}' > "$VBW_RTK_DIR/rtk-compatibility-proof.json"
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg path "$binary" '.active_hook_rtk_path == $path'
  echo "$output" | jq -e '.active_hook_rtk_version == "0.1.0"'
  echo "$output" | jq -e '.compatibility == "verified"'
  echo "$output" | jq -e '.doctor_status == "PASS"'
}

@test "rtk-manager: shell-quoted absolute hook with apostrophe parses and verifies proof" {
  local binary_dir binary config_path quoted_command
  binary_dir="$TEST_TEMP_DIR/managed QA's bin"
  binary="$(create_managed_rtk "0.1.0" "$binary_dir")"
  config_path="$(expected_rtk_config_path)"
  mkdir -p "$(dirname "$config_path")"
  printf '%s\n' '[tracking]' 'enabled = true' 'history_days = 90' > "$config_path"
  quoted_command="'${binary%\'*}'\\''${binary#*\'}' hook claude"
  jq -n --arg command "$quoted_command" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  mkdir -p "$VBW_RTK_DIR"
  jq -n --arg command "$quoted_command" '{proof_type:"runtime_smoke",status:"pass",timestamp:"2026-04-27T00:00:00Z",rtk_version:"0.1.0",hook_command:$command,updated_input_verified:true,rtk_rewrite_observed:true,vbw_bash_guard_verified:true,commands:["git status"]}' > "$VBW_RTK_DIR/rtk-compatibility-proof.json"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e --arg path "$binary" '.active_hook_rtk_path == $path'
  echo "$output" | jq -e '.active_hook_rtk_version == "0.1.0"'
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.compatibility == "verified"'
  echo "$output" | jq -e '.doctor_status == "PASS"'
}

@test "rtk-manager: malformed quoted hook command is not executed or accepted" {
  write_fake_rtk "0.1.0"
  local malformed_command
  malformed_command="'$TEST_TEMP_DIR/malformed/rtk hook claude"
  jq -n --arg command "$malformed_command" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$command}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e '.active_hook_rtk_path == ""'
  echo "$output" | jq -e '.proof_source == ""'
}

@test "rtk-manager: cached newer release makes verified doctor status WARN" {
  write_fake_rtk "0.1.0"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  write_valid_smoke_proof
  mkdir -p "$VBW_RTK_DIR"
  echo '{"version":"9.9.9","checked_at":"2026-04-27T00:00:00Z"}' > "$VBW_RTK_DIR/rtk-latest-release.json"
  run rtk_manager doctor-json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.update_available == true'
  echo "$output" | jq -e '.doctor_status == "WARN"'
  echo "$output" | jq -e '.doctor_detail | test("outdated")'
}

@test "rtk-manager: legacy hook file alone is diagnostic not active hook" {
  mkdir -p "$CLAUDE_CONFIG_DIR/hooks"
  touch "$CLAUDE_CONFIG_DIR/hooks/rtk-rewrite.sh"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.legacy_hook_file_present == true'
  echo "$output" | jq -e '.global_hook_present == false'
  echo "$output" | jq -e '.compatibility == "absent"'
}

@test "rtk-manager: legacy command in settings JSON is active hook" {
  write_fake_rtk "0.1.0"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/rtk-rewrite.sh"}]}]}}
JSON
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e '.global_hook_command | test("rtk-rewrite")'
}

@test "rtk-manager: quoted absolute hook command in settings JSON is active" {
  local binary
  binary="$(create_managed_rtk "0.1.0" "$TEST_TEMP_DIR/managed bin with space")"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<JSON
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$binary\" hook claude"}]}]}}
JSON
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.settings_json_valid == true'
  echo "$output" | jq -e '.global_hook_present == true'
  echo "$output" | jq -e '.settings_hook_state == "active"'
  echo "$output" | jq -e --arg command "\"$binary\" hook claude" '.global_hook_command == $command'
  echo "$output" | jq -e '.global_hook_matcher == "Bash"'
  echo "$output" | jq -e '.compatibility != "binary_only"'
}

@test "rtk-manager: quoted absolute hook blocks managed uninstall without deactivate" {
  local binary
  binary="$(create_managed_rtk "0.1.0" "$TEST_TEMP_DIR/managed bin with space")"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<JSON
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$binary\" hook claude"}]}]}}
JSON
  run rtk_manager uninstall --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"pass --deactivate-hook"* ]]
  [ -e "$binary" ]
  [ -f "$VBW_RTK_DIR/rtk-install.json" ]
}

@test "rtk-manager: managed update dry-run does not cache latest release" {
  create_managed_rtk "0.1.0" >/dev/null
  prepare_release_fixture "9.9.9"
  write_release_curl
  run rtk_manager update --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"RTK update preflight"* ]]
  [ ! -f "$VBW_RTK_DIR/rtk-latest-release.json" ]
}

@test "rtk-manager: off-PATH managed receipt is not hook-activation-ready" {
  local binary
  binary="$(create_managed_rtk "0.1.0")"
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.rtk_present == false'
  echo "$output" | jq -e '.managed_by_vbw == true'
  echo "$output" | jq -e '.binary_install_state == "installed_not_on_path"'
  echo "$output" | jq -e '.compatibility == "absent"'
  echo "$output" | jq -e '.next_action == "path"'
  run rtk_manager init --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"not on PATH"* ]]
  [[ "$output" == *"$(dirname "$binary")"* ]]
}

@test "rtk-manager: external no-receipt update does not take ownership" {
  write_fake_rtk "0.1.0"
  prepare_release_fixture "9.9.9"
  write_release_curl
  run rtk_manager update --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"external install detected"* ]]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
  [ ! -f "$VBW_RTK_DIR/rtk-latest-release.json" ]
}

@test "rtk-manager: managed update replaces receipt-owned binary and records versions" {
  local binary
  binary="$(create_managed_rtk "0.1.0")"
  prepare_release_fixture "9.9.9"
  write_release_curl
  export RTK_CURL_MAX_TIME=7
  run rtk_manager update --yes
  [ "$status" -eq 0 ]
  [ -x "$binary" ]
  "$binary" --version | grep -Fq "9.9.9"
  jq -e '.previous_version == "0.1.0"' "$VBW_RTK_DIR/rtk-install.json"
  jq -e '.installed_version == "9.9.9"' "$VBW_RTK_DIR/rtk-install.json"
  [ "$(grep -c -- '--max-time 7' "$TEST_TEMP_DIR/curl-calls.log")" -ge 3 ]
}

@test "rtk-manager: Homebrew-managed update uses brew upgrade when outdated" {
  write_fake_uname Darwin arm64
  write_fake_brew "9.9.9"
  "$TEST_TEMP_DIR/bin/brew" install rtk
  mkdir -p "$VBW_RTK_DIR"
  jq -n --arg binary "$TEST_TEMP_DIR/bin/rtk" '{manager:"vbw", method:"homebrew", binary_path:$binary, installed_version:"0.1.0"}' > "$VBW_RTK_DIR/rtk-install.json"
  export FAKE_BREW_OUTDATED=true
  run rtk_manager update --yes
  [ "$status" -eq 0 ]
  grep -Fxq 'upgrade rtk' "$TEST_TEMP_DIR/brew-calls.log"
  jq -e '.method == "homebrew"' "$VBW_RTK_DIR/rtk-install.json"
}

@test "rtk-manager: Homebrew-managed uninstall calls brew uninstall after safety guards" {
  write_fake_uname Darwin arm64
  write_fake_brew "9.9.9"
  "$TEST_TEMP_DIR/bin/brew" install rtk
  mkdir -p "$VBW_RTK_DIR"
  jq -n --arg binary "$TEST_TEMP_DIR/bin/rtk" '{manager:"vbw", method:"homebrew", binary_path:$binary, installed_version:"9.9.9"}' > "$VBW_RTK_DIR/rtk-install.json"
  run rtk_manager uninstall --yes
  [ "$status" -eq 0 ]
  grep -Fxq 'uninstall rtk' "$TEST_TEMP_DIR/brew-calls.log"
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
}

@test "rtk-manager: missing checksum aborts unless explicitly allowed" {
  prepare_release_fixture "9.9.9" "false" "no-asset"
  write_release_curl
  export RTK_INSTALL_DIR="$TEST_TEMP_DIR/install-bin"
  run rtk_manager install --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksums.txt unavailable"* ]]
  run rtk_manager install --yes --allow-missing-checksum
  [ "$status" -eq 0 ]
  jq -e '.verified_checksum == ""' "$VBW_RTK_DIR/rtk-install.json"
}

@test "rtk-manager: uninstall deactivates hook before removing managed binary" {
  local binary
  binary="$(create_managed_rtk "0.1.0")"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  run rtk_manager uninstall --yes --deactivate-hook
  [ "$status" -eq 0 ]
  grep -Fq 'init -g --uninstall' "$TEST_TEMP_DIR/rtk-calls.log"
  grep -Fq 'uninstall_binary_exists=yes' "$TEST_TEMP_DIR/rtk-calls.log"
  [ ! -e "$binary" ]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
}

@test "rtk-manager: uninstall deactivation backs up Claude config before mutation" {
  create_managed_rtk "0.1.0" >/dev/null
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'EOF'
original settings
EOF
  cat > "$CLAUDE_CONFIG_DIR/CLAUDE.md" <<'EOF'
original claude
EOF
  cat > "$CLAUDE_CONFIG_DIR/RTK.md" <<'EOF'
original rtk
EOF
  export FAKE_RTK_MUTATE_CONFIG_ON_UNINSTALL=true
  run rtk_manager uninstall --yes --deactivate-hook
  [ "$status" -eq 0 ]
  grep -R "original settings" "$VBW_RTK_DIR/backups"
  grep -R "original claude" "$VBW_RTK_DIR/backups"
  grep -R "original rtk" "$VBW_RTK_DIR/backups"
}

@test "rtk-manager: failed hook deactivation preserves managed binary" {
  local binary
  binary="$(create_managed_rtk "0.1.0")"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  export FAKE_RTK_UNINSTALL_FAIL=true
  run rtk_manager uninstall --yes --deactivate-hook
  [ "$status" -eq 1 ]
  [ -e "$binary" ]
  [ -f "$VBW_RTK_DIR/rtk-install.json" ]
}

@test "rtk-manager: hook-active managed uninstall requires deactivate flag" {
  local binary
  binary="$(create_managed_rtk "0.1.0")"
  cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}
JSON
  run rtk_manager uninstall --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"hook deactivation or settings repair required before binary removal"* ]]
  run rtk_manager uninstall --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"pass --deactivate-hook"* ]]
  [ -e "$binary" ]
  [ -f "$VBW_RTK_DIR/rtk-install.json" ]
}

@test "rtk-manager: malformed settings blocks managed uninstall without deactivate flag" {
  local binary
  binary="$(create_managed_rtk "0.1.0")"
  printf '{not-json' > "$CLAUDE_CONFIG_DIR/settings.json"
  run rtk_manager uninstall --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings repair required"* ]]
  run rtk_manager uninstall --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"unreadable RTK settings hook state"* ]]
  [ -e "$binary" ]
  [ -f "$VBW_RTK_DIR/rtk-install.json" ]
}

@test "rtk-manager: uninstall preflight text has no boolean suffix" {
  create_managed_rtk "0.1.0" >/dev/null
  run rtk_manager uninstall --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"no hook deactivation requested"* ]]
  [[ "$output" != *"before binary removalfalse"* ]]
  run rtk_manager uninstall --dry-run --deactivate-hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"rtk init -g --uninstall before binary removal"* ]]
  [[ "$output" != *"false"* ]]
}

@test "rtk-manager: managed uninstall retires receipt and clears managed status" {
  local binary
  binary="$(create_managed_rtk "0.1.0")"
  run rtk_manager uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -e "$binary" ]
  [ ! -f "$VBW_RTK_DIR/rtk-install.json" ]
  run rtk_manager status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.managed_by_vbw == false'
  echo "$output" | jq -e '.install_receipt == ""'
}
