#!/usr/bin/env bats
# Engineering standards as tests. Each rule traces to a v1 defect or a design
# rule (vbw2_build_plan.md §2 M0). A rule that is not enforced here is not a rule.

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

@test "no eval or data-as-code (ledger D108, D139)" {
  run code_grep '(^|[^[:alnum:]_])eval[[:space:]]|bash -c "\$|sh -c "\$'
  [ -z "$output" ]
}

@test "no bash-4-only features: macOS /bin/bash 3.2 is the floor (K2, ledger D294)" {
  run code_grep '(^|[^[:alnum:]_])(mapfile|readarray)[[:space:]]|(declare|local)[[:space:]]+-[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)\}|"\$\{@\}"'
  [ -z "$output" ]
}

@test "never terminates processes (ledger D54, D285–D288)" {
  run code_grep '(^|[^[:alnum:]_])(pkill|killall)[[:space:]]|(^|[^[:alnum:]_])kill[[:space:]]+(-([^0]|0[^[:space:]])|[^-])|tmux[[:space:]]+kill-'
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
  local hooks="$PLUGIN_ROOT/hooks/hooks.json" cmd rest
  # Before jq a command may hold only shell builtins: NAME=value assignments and
  # [ ... ] tests, joined by && || ; . No program starts, no $(...), no pipe.
  local exp='\$\{[^}`(]*\}|\$[A-Za-z_][A-Za-z0-9_]*'
  local val='([A-Za-z0-9_./:-]|'"$exp"'|"([^"$`]|'"$exp"')*")+'
  local assign='^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*='"$val"'[[:space:]]*(;|&&|\|\|)?'
  local test_='^[[:space:]]*\[ ([^]$`;&|()<>]|'"$exp"')* \][[:space:]]*(;|&&|\|\|)'
  # The one program-free limit allowed first: the shell's own CPU-time limit (R165).
  local limit='^[[:space:]]*ulimit -t [0-9]+( 2>/dev/null)?[[:space:]]*;'
  # The only loops allowed, exactly these texts: the walk up to the project (the nearest
  # folder holding .git, then from a submodule with no record the nearest folder above
  # holding .git and a record, as hooks/project.sh and the kernel find it; a submodule
  # is a .git file whose gitdir is under modules/, never a linked worktree's), [ ] tests,
  # case, read from the .git file and parameter expansion only.
  local walk=' while [ "$p" != / ] && [ -n "$p" ] && [ ! -e "$p/.git" ]; do case "$p" in */*) p="${p%/*}"; p="${p:-/}" ;; *) p=/ ;; esac; done;'
  local up=' while [ "$u" != / ] && [ -f "$u/.git" ] && [ ! -f "$u/.vbw/record.json" ]; do l=; read -r l < "$u/.git" || :; case "$l" in */modules/*) ;; *) break ;; esac; case "${l##*/worktrees/}" in "$l" | */*) ;; *) break ;; esac; case "$u" in */*) u="${u%/*}"; u="${u:-/}" ;; *) u=/ ;; esac; while [ "$u" != / ] && [ ! -e "$u/.git" ]; do case "$u" in */*) u="${u%/*}"; u="${u:-/}" ;; *) u=/ ;; esac; done; done;'
  [ -f "$hooks" ] || return 0
  while IFS= read -r cmd; do
    rest=$cmd
    while [[ "$rest" =~ $assign || "$rest" =~ $test_ || "$rest" =~ $limit || "$rest" == "$walk"* || "$rest" == "$up"* ]]; do
      if [[ "$rest" == "$walk"* ]]; then rest=${rest#"$walk"}
      elif [[ "$rest" == "$up"* ]]; then rest=${rest#"$up"}
      else rest=${rest#"${BASH_REMATCH[0]}"}; fi
    done
    rest=${rest#"${rest%%[![:space:]]*}"}
    [[ "$rest" == "jq "* ]] || { echo "PreToolUse hook must be jq itself (only shell variable assignments and [ ] tests may come before it; no interpreter startup): $cmd"; false; }
    # It ends in || true, or in the fail-closed handler (R165): a failing guard
    # blocks with exit 2 only while a run is open, and otherwise ends in true.
    [[ "$cmd" == *" || true" || "$cmd" == *" || { "*"exit 2"*" true; }" ]] || { echo "PreToolUse hook must end in || true, or in the fail-closed handler (exit 2 only while a run is open): $cmd"; false; }
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

@test "no brace-literal parameter defaults (a default of {} written inside the expansion): bash 3.2 keeps the backslash (tests and tools too)" {
  run grep -rnE '\$\{[A-Za-z0-9_]+:-\\?\{' --include='*.sh' --include='*.bash' --include='*.bats' "$REPO_ROOT/tests" "$REPO_ROOT/tools" "$PLUGIN_ROOT"
  # A comment that names the pattern is allowed.
  [ -z "$(printf '%s\n' "$output" | grep -vE ':[0-9]+:[[:space:]]*#')" ]
}

@test "the vision rule is VBW's first development rule, and every contributor file states it (owner mandate, 2026-10-06)" {
  run bash "$REPO_ROOT/tools/check-vision-rule.sh" "$REPO_ROOT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "every answer a hook gives Claude Code has a test pinning its meaning, and no hook answers allow (R128)" {
  run bash "$REPO_ROOT/tools/check-hook-answers.sh" "$PLUGIN_ROOT/hooks" "$REPO_ROOT/tests/hook-answers.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "no tracked file, .vbw/ included, names a private project of the owner (owner rule, 2026-10-21; needs the maintainer-local list, skipped without it)" {
  # The self-tests run these rules against a stand-in plugin and expect only its defect to fail.
  [ "$PLUGIN_ROOT" = "$REPO_ROOT/plugin" ] || skip "not the shipped plugin"
  run bash "$REPO_ROOT/tools/check-private-words.sh" tracked
  [ "$status" -ne 3 ] || skip "$output"
  [ "$status" -eq 0 ] || { echo "files that name a private project:"; echo "$output"; false; }
}

@test "no shell code pipes into a quiet grep: grep -q stops early, and under pipefail the producer's SIGPIPE fails the pipeline (tools/check-pipefail-grep.sh)" {
  run bash "$REPO_ROOT/tools/check-pipefail-grep.sh" "$PLUGIN_ROOT" "$REPO_ROOT/tools"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "self-test: the pipefail rule refuses each quiet grep after a pipe, whatever the producer, naming its line, and passes every form that reads to the end" {
  local d line n=0
  d=$(mktemp -d "${BATS_TEST_TMPDIR:?}/plant.XXXXXX")
  # Each line is refused, whatever the quiet option looks like.
  for line in \
    "printf '%s' \"\$s\" | grep -q 'x'" \
    "if printf '%s\n' \"\$s\" | grep -Eq 'a|b'; then :; fi" \
    "echo \"\$s\" | grep -qi x" \
    "printf '%s' \"\$s\" | grep -E -q x" \
    "printf '%s' \"\$s\" | grep --quiet x" \
    "ok && ! printf '%s' \"\$s\" | grep -qxF -- \"\$f\"" \
    "printf '%s' \"\$s\" | command grep -q x" \
    "jq . f | grep -q x" \
    "if screen | grep -q 'Ready'; then :; fi" \
    "screen | cut -c1-120 | grep -qE 'a b' || return 1" \
    "./test.sh | grep -qx 'TESTS PASS'"; do
    n=$((n + 1))
    printf '#!/usr/bin/env bash\n# planted\n\n%s\n' "$line" > "$d/p$n.sh"
    run bash "$REPO_ROOT/tools/check-pipefail-grep.sh" "$d"
    [ "$status" -eq 1 ] || { echo "not refused: $line"; false; }
    [[ "$output" == *"p$n.sh:4:"* ]] || { echo "no line named for: $line: $output"; false; }
    rm "$d/p$n.sh"
  done
  # Each of these passes: grep reads to the end, reads no pipe, or no code at all.
  for line in \
    "printf '%s' \"\$s\" | grep 'x' > /dev/null" \
    "printf '%s' \"\$s\" | grep -c x" \
    "grep -q x <<< \"\$s\"" \
    "grep -q x file" \
    "# printf '%s' \"\$s\" | grep -q x" \
    "printf '%s' \"\$s\" | grep -e q"; do
    printf '#!/usr/bin/env bash\n# planted\n\n%s\n' "$line" > "$d/ok.sh"
    run bash "$REPO_ROOT/tools/check-pipefail-grep.sh" "$d"
    [ "$status" -eq 0 ] || { echo "refused: $line: $output"; false; }
  done
  rm "$d/ok.sh"
  # bin/vbw has no .sh name and is read too.
  mkdir -p "$d/bin"
  printf 'printf "%%s" "$s" | grep -q x\n' > "$d/bin/vbw"
  run bash "$REPO_ROOT/tools/check-pipefail-grep.sh" "$d"
  [ "$status" -eq 1 ] || { echo "bin/vbw was not read: $output"; false; }
  run bash "$REPO_ROOT/tools/check-pipefail-grep.sh" "$d/nothing"
  [ "$status" -eq 2 ]
  run bash "$REPO_ROOT/tools/check-pipefail-grep.sh"
  [ "$status" -eq 2 ]
}
