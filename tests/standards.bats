#!/usr/bin/env bats
# Engineering standards as tests. Each rule traces to a v1 defect or a design
# budget (vbw2_build_plan.md §2 M0). A rule that is not enforced here is not a rule.

load helper

# Every shell file that ships: the kernel CLI, its library, hook handlers.
kernel_files() {
  { [ -f "$PLUGIN_ROOT/bin/vbw" ] && printf '%s\n' "$PLUGIN_ROOT/bin/vbw"
    find "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts" -type f -name '*.sh' 2>/dev/null
  } | LC_ALL=C sort
}

# Grep shipped shell code for a pattern, ignoring comment-only lines.
code_grep() {
  local pattern="$1" file
  while IFS= read -r file; do
    grep -nE "$pattern" "$file" | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$file:|"
  done < <(kernel_files)
}

@test "kernel stays within 3,300 lines of code (design §10; owner raised it from 3,000 on 2026-10-04)" {
  # Shell and jq both count: the jq programs are kernel logic too.
  local total=0 file n
  while IFS= read -r file; do
    n=$(grep -cvE '^[[:space:]]*(#|$)' "$file" || true)
    total=$((total + n))
  done < <(kernel_files; find "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts" -type f -name '*.jq' 2>/dev/null)
  echo "kernel lines: $total"
  [ "$total" -le 3300 ]
}

@test "workflows stay within 1,500 lines (design §10)" {
  local total=0 file n
  while IFS= read -r file; do
    n=$(grep -cvE '^[[:space:]]*(//|$)' "$file" || true)
    total=$((total + n))
  done < <(find "$PLUGIN_ROOT/workflows" -type f -name '*.js' 2>/dev/null)
  echo "workflow lines: $total"
  [ "$total" -le 1500 ]
}

@test "shipped plugin is under 1 MB (design §10, ledger D295)" {
  local kb
  kb=$(du -sk "$PLUGIN_ROOT" | cut -f1)
  echo "plugin size: ${kb} KB"
  [ "$kb" -lt 1024 ]
}

@test "no eval or data-as-code (ledger D108, D139)" {
  run code_grep '(^|[^[:alnum:]_])eval[[:space:]]|bash -c "\$|sh -c "\$'
  [ -z "$output" ]
}

@test "no bash-4-only features: macOS /bin/bash 3.2 is the floor (K2, ledger D294)" {
  run code_grep '(^|[^[:alnum:]_])(mapfile|readarray)[[:space:]]|(declare|local)[[:space:]]+-[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)\}|"\$\{@\}"'
  [ -z "$output" ]
}

@test "never terminates processes (ledger D54, D285–D288)" {
  run code_grep '(^|[^[:alnum:]_])(kill|pkill|killall)[[:space:]]|tmux[[:space:]]+kill-'
  [ -z "$output" ]
}

@test "no predictable /tmp paths or writes outside the project (K3, ledger D296)" {
  run code_grep '/tmp/|/var/tmp/'
  [ -z "$output" ]
}

@test "git path listings are NUL-separated (ledger D293)" {
  run code_grep 'git[^|;]*(--name-only|--name-status|ls-files|status --porcelain|diff-tree)'
  local line bad=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in *" -z"*) ;; *) bad="$bad$line"$'\n' ;; esac
  done <<< "$output"
  [ -z "$bad" ] || { printf '%s' "$bad"; false; }
}

@test "no plugin-root discovery: paths come from \${CLAUDE_PLUGIN_ROOT} substitution or \$0 (K4)" {
  # The one exception: the user's statusLine setting cannot use substitution, so
  # the command VBW writes there finds the newest install in the plugin cache.
  run code_grep 'plugins/cache|plugin-root-link|--plugin-dir|(^|[^[:alnum:]_])ps[[:space:]]+(a|-)'
  output=$(printf '%s\n' "$output" | grep -v '/lib/cmd-statusline.sh:[0-9]*:VBW_STATUSLINE_CMD=' || true)
  [ -z "$output" ]
  local dirs=() d
  for d in skills agents workflows; do [ -d "$PLUGIN_ROOT/$d" ] && dirs+=("$PLUGIN_ROOT/$d"); done
  [ ${#dirs[@]} -eq 0 ] && return 0
  run grep -rnE 'plugins/cache|plugin-root-link|find_plugin_root' "${dirs[@]}"
  [ -z "$output" ]
}

@test "shell files parse on the minimum bash and pass shellcheck" {
  local file
  while IFS= read -r file; do
    if /bin/bash -c '[ "${BASH_VERSINFO[0]}" -eq 3 ]' 2>/dev/null; then
      /bin/bash -n "$file"
    fi
    bash -n "$file"
  done < <(kernel_files)
  if command -v shellcheck >/dev/null 2>&1; then
    kernel_files | tr '\n' '\0' | xargs -0 -r shellcheck -S warning -x
  fi
}

@test "plugin manifests are valid" {
  jq -e '.name == "vbw" and (.version | type == "string")' "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  jq -e '.plugins[0].source == "./plugin"' "$REPO_ROOT/marketplace.json"
  # Relative: the plugin comes from the same repository and branch as the
  # marketplace (a branch can be tested before it is merged).
  jq -e '.plugins[0].source == "./plugin"' "$REPO_ROOT/.claude-plugin/marketplace.json"
  [ "$(jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json")" = "$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")" ]
  # VBW 1's /vbw:update confirms an update by reading VERSION inside the installed
  # plugin, so the plugin ships one (docs/convert.md).
  [ "$(tr -d '[:space:]' < "$PLUGIN_ROOT/VERSION")" = "$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")" ]
}

@test "hooks.json is valid and every file a hook names exists in hooks/" {
  local hooks="$PLUGIN_ROOT/hooks/hooks.json" cmd rest
  [ -f "$hooks" ] || return 0
  jq -e '.hooks | type == "object"' "$hooks"
  while IFS= read -r cmd; do
    [[ "$cmd" == *'${CLAUDE_PLUGIN_ROOT}/hooks/'* ]] || { echo "hook runs nothing from hooks/: $cmd"; false; }
    rest=$cmd
    while [[ "$rest" =~ \$\{CLAUDE_PLUGIN_ROOT\}/(hooks/[A-Za-z0-9._-]+) ]]; do
      [ -f "$PLUGIN_ROOT/${BASH_REMATCH[1]}" ] || { echo "missing: ${BASH_REMATCH[1]}"; false; }
      rest=${rest#*"${BASH_REMATCH[0]}"}
    done
  done < <(jq -r '.hooks[][].hooks[].command' "$hooks")
}

@test "per-tool-call hooks run jq directly and never exit non-zero (K20)" {
  local hooks="$PLUGIN_ROOT/hooks/hooks.json" cmd
  [ -f "$hooks" ] || return 0
  while IFS= read -r cmd; do
    [[ "$cmd" == "jq "* ]] || { echo "PreToolUse hook must be jq itself (no interpreter startup): $cmd"; false; }
    [[ "$cmd" == *" || true" ]] || { echo "PreToolUse hook must never exit non-zero (exit 2 blocks the call): $cmd"; false; }
  done < <(jq -r '.hooks.PreToolUse[]?.hooks[].command' "$hooks")
}

@test "Claude Code's own validator accepts the plugin and the marketplace" {
  command -v claude > /dev/null 2>&1 || skip "claude is not installed"
  [ -f "$REPO_ROOT/.claude-plugin/marketplace.json" ] && [ "$PLUGIN_ROOT" = "$REPO_ROOT/plugin" ] || skip "not the shipped plugin"
  run claude plugin validate "$PLUGIN_ROOT"
  [[ "$output" == *"Validation passed"* ]] || { echo "$output"; false; }
  [[ "$output" != *"with warnings"* ]] || { echo "$output"; false; }
  run claude plugin validate "$REPO_ROOT"
  [[ "$output" == *"Validation passed"* ]] || { echo "$output"; false; }
}
