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

@test "no committed result file names a home folder: the L3 results and the probes write the checkout as <checkout> and the home folder as ~ (T213)" {
  cd "$REPO_ROOT"
  local hits
  hits=$(git ls-files -z -- tools/l3-results tools/probes | xargs -0 grep -l -E '/(Users|home)/[^/"]+/' 2> /dev/null || true)
  [ -z "$hits" ] || { echo "result files that name a home folder:"; echo "$hits"; false; }
  local s
  for s in tools/l3-suite.sh tools/probe-mcp-tools.sh; do
    grep -q "tools/mask-paths.jq" "$s" || { echo "$s writes its result without tools/mask-paths.jq"; false; }
  done
  run jq -c --arg root "/Users/jane/My work/vbw" --arg home "/Users/jane" -f tools/mask-paths.jq <<< '{"a":"/Users/jane/My work/vbw/plugin","b":["/Users/jane/.claude/x",1],"c":"plain"}'
  [ "$output" = '{"a":"<checkout>/plugin","b":["~/.claude/x",1],"c":"plain"}' ] || { echo "masked: $output"; false; }
}

# R248 (T221; docs/record.md Versioning): a new key or allowed value of the record
# comes with a schema bump. tools/check-record-shape.sh digests the record's accepted
# shape (every literal key list and enum in record.jq, the schema table's rows in
# record-schema.jq, the interview values in interview.json) and compares it with the
# digest pinned here beside the pinned VBW_SCHEMA_MAX; it also checks the table's top,
# VBW_SCHEMA_MAX and the pin agree. Moving the pin is the deliberate act a shape change
# needs: add the table row (plugin/lib/record-schema.jq), set VBW_SCHEMA_MAX
# (plugin/lib/record.sh), describe it in docs/record.md, then copy the digest the check
# prints into R248_DIGEST. A layout-only change (comments, whitespace, line breaks, the
# order of names inside a list) never moves it.
R248_SCHEMA=9
R248_DIGEST=c28be9ea997039007511f92e00f14a09885798a662896b28c76040a6bdfb70ab

@test "R248: the record's accepted shape is pinned: record.jq's key lists and enums, the schema table's rows and the interview values digest to R248_DIGEST, and the table's top, VBW_SCHEMA_MAX and R248_SCHEMA agree (tools/check-record-shape.sh)" {
  [ "$PLUGIN_ROOT" = "$REPO_ROOT/plugin" ] || skip "not the shipped plugin"
  run bash "$REPO_ROOT/tools/check-record-shape.sh" "$PLUGIN_ROOT" "$R248_SCHEMA" "$R248_DIGEST"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R248 self-test: the shape check refuses a key or value added to or removed from record.jq, interview.json or the schema table, and VBW_SCHEMA_MAX moved alone, naming the three places and the pin; the unchanged copy and layout-only changes pass" {
  # The self-tests run this file against a stand-in plugin many times; the check reads the shipped one.
  [ "$PLUGIN_ROOT" = "$REPO_ROOT/plugin" ] || skip "not the shipped plugin"
  local check="$REPO_ROOT/tools/check-record-shape.sh" d schema digest hits
  [ -f "$check" ] || { echo "no tools/check-record-shape.sh"; false; }
  # bash 3.2 clean, no data as code (the standards grep covers the plugin, not tools/).
  hits=$(grep -nE '(^|[^[:alnum:]_])(mapfile|readarray|eval)[[:space:]]|(declare|local)[[:space:]]+-[a-zA-Z]*A[[:space:]]' "$check" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
  [ -z "$hits" ] || { echo "the check is not bash 3.2 clean:"; echo "$hits"; false; }
  # interview.json is read only through jq.
  hits=$(grep -nE 'interview\.json' "$check" | grep -vE 'jq|^[0-9]+:[[:space:]]*#|\[ -f' || true)
  [ -z "$hits" ] || { echo "interview.json is read without jq:"; echo "$hits"; false; }
  d=$(mktemp -d "${BATS_TEST_TMPDIR:?}/shape.XXXXXX")
  # fresh: a copy of the shipped plugin's lib, the files the check reads.
  fresh() { rm -rf "$d/lib"; mkdir -p "$d/lib"; cp "$REPO_ROOT/plugin/lib/record.jq" "$REPO_ROOT/plugin/lib/record-schema.jq" "$REPO_ROOT/plugin/lib/record.sh" "$REPO_ROOT/plugin/lib/interview.json" "$d/lib/"; }
  fresh
  schema=$(sed -n 's/^VBW_SCHEMA_MAX=//p' "$d/lib/record.sh")
  [ -n "$schema" ]
  # A wrong pin is refused and the check prints the digest it computed, to copy.
  run bash "$check" "$d" "$schema" 0000000000000000000000000000000000000000000000000000000000000000
  [ "$status" -eq 1 ] || { echo "exit $status: $output"; false; }
  digest=$(printf '%s\n' "$output" | sed -n 's/^computed digest: //p')
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo "no 'computed digest: <sha256>' line: $output"; false; }
  [ "$digest" = "$R248_DIGEST" ] || { echo "the shipped shape digests to $digest, the pin is $R248_DIGEST"; false; }
  # refused: the last run exited 1 and named the three places and the pin.
  refused() {
    [ "$status" -eq 1 ] || { echo "$1: exit $status: $output"; return 1; }
    local place
    for place in plugin/lib/record-schema.jq VBW_SCHEMA_MAX plugin/lib/record.sh docs/record.md tests/standards.bats; do
      [[ "$output" == *"$place"* ]] || { echo "$1: the refusal does not name $place: $output"; return 1; }
    done
  }
  # The unchanged copy passes.
  run bash "$check" "$d" "$schema" "$digest"
  [ "$status" -eq 0 ] || { echo "unchanged: $output"; false; }
  # A key added to record.jq's top-level key list.
  fresh; sed -i.bak 's/"schema","project","milestone"/"schema","project","probe","milestone"/' "$d/lib/record.jq"
  grep -q '"probe"' "$d/lib/record.jq"
  run bash "$check" "$d" "$schema" "$digest"
  refused "a key added to the top-level list"
  [[ "$output" != *"computed digest: $digest"* ]] || { echo "the digest did not move for an added key"; false; }
  # A key removed from the settings key list.
  fresh; sed -i.bak 's/"rigor","motion","command_timeout"/"rigor","command_timeout"/' "$d/lib/record.jq"
  ! grep -q '"rigor","motion"' "$d/lib/record.jq" || false
  run bash "$check" "$d" "$schema" "$digest"
  refused "a key removed from the settings list"
  # A value appended to interview.json's level array.
  fresh; jq '.level += ["wizard"]' "$REPO_ROOT/plugin/lib/interview.json" > "$d/lib/interview.json"
  run bash "$check" "$d" "$schema" "$digest"
  refused "a value added to interview.json"
  # A row added to the schema table with the pin unmoved: the digest moves and the numbers differ.
  fresh; sed -i.bak 's/^def schema_features: \[/def schema_features: [ {schema: 10, feature: "a probe", present: false},/' "$d/lib/record-schema.jq"
  grep -q '"a probe"' "$d/lib/record-schema.jq"
  run bash "$check" "$d" "$schema" "$digest"
  refused "a table row added"
  [[ "$output" == *"table 10"* && "$output" == *"VBW_SCHEMA_MAX $schema"* && "$output" == *"pinned $schema"* ]] || { echo "the numbers line does not name each value: $output"; false; }
  # VBW_SCHEMA_MAX raised with the table unmoved: the digest holds, the numbers differ.
  fresh; sed -i.bak "s/^VBW_SCHEMA_MAX=.*\$/VBW_SCHEMA_MAX=$((schema + 1))/" "$d/lib/record.sh"
  run bash "$check" "$d" "$schema" "$digest"
  refused "VBW_SCHEMA_MAX raised alone"
  [[ "$output" == *"table $schema"* && "$output" == *"VBW_SCHEMA_MAX $((schema + 1))"* && "$output" == *"pinned $schema"* ]] || { echo "the numbers line does not name each value: $output"; false; }
  [[ "$output" != *"computed digest:"* ]] || { echo "the digest moved although no list changed: $output"; false; }
  # Layout-only changes pass: a comment line, a blank line, names reordered inside one list.
  fresh; { printf '# a new comment line\n'; cat "$REPO_ROOT/plugin/lib/record.jq"; } > "$d/lib/record.jq"
  run bash "$check" "$d" "$schema" "$digest"
  [ "$status" -eq 0 ] || { echo "a comment line moved the digest: $output"; false; }
  fresh; { cat "$REPO_ROOT/plugin/lib/record.jq"; printf '\n\n'; } > "$d/lib/record.jq"
  run bash "$check" "$d" "$schema" "$digest"
  [ "$status" -eq 0 ] || { echo "blank lines moved the digest: $output"; false; }
  fresh; sed -i.bak 's/"schema","project","milestone"/"project","milestone","schema"/' "$d/lib/record.jq"
  grep -q '"project","milestone","schema"' "$d/lib/record.jq"
  run bash "$check" "$d" "$schema" "$digest"
  [ "$status" -eq 0 ] || { echo "reordering names in a list moved the digest: $output"; false; }
  # Usage.
  run bash "$check" "$d" "$schema"
  [ "$status" -eq 2 ]
}

@test "R248: docs/record.md says beside the schema table that a new key or allowed value of the record needs a schema bump, naming tools/check-record-shape.sh" {
  [ "$PLUGIN_ROOT" = "$REPO_ROOT/plugin" ] || skip "not the shipped plugin"
  local section
  section=$(awk '/^## Versioning/ { on = 1 } /^## Consent/ { on = 0 } on' "$REPO_ROOT/docs/record.md")
  printf '%s\n' "$section" | grep -q 'tools/check-record-shape.sh' || { echo "the Versioning section does not name tools/check-record-shape.sh"; false; }
  printf '%s\n' "$section" | grep -qiE 'new key[^.]*(bump|raise|new schema|schema number)|(bump|raise)[^.]*new key' || { echo "the Versioning section does not say a new key needs a schema bump"; false; }
}
