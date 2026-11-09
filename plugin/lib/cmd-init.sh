#!/usr/bin/env bash
# vbw init: create .vbw/ in the current git repository. Idempotent; never
# overwrites existing state; writes nothing outside the project.

cmd_init() {
  vbw_project
  if [ -f "$VBW_RECORD" ]; then
    if record_gitignore; then init_said; fi
    printf 'VBW is already initialized in %s\n' "$VBW_ROOT"
    init_hidden
    return 0
  fi
  mkdir -p "$VBW_RUNTIME"
  local name commands big kind
  name=$(basename "$VBW_ROOT")
  # Large git-ignored folders (R253): candidates for the Clean copy section.
  # shellcheck source=proofcopy.sh
  . "$VBW_LIB/proofcopy.sh"
  big=$(proofcopy_big_ignored 2> /dev/null) || big=''
  kind=$(proofcopy_disk_kind)
  commands=$(init_detect_commands "$VBW_ROOT")
  # The detected commands are a suggestion in spec.md, which the user owns; a
  # spec that already lists its own commands wins.
  if [ -f "$VBW_DIR/spec.md" ]; then
    commands=$(jq -Rs -f "$VBW_LIB/spec.jq" < "$VBW_DIR/spec.md" 2> /dev/null \
      | jq -c --argjson d "$commands" '.commands // $d' 2> /dev/null || printf '%s' "$commands")
  else
    init_spec "$name" "$commands" "$big" "$kind" > "$VBW_DIR/spec.md"
  fi
  jq -n --arg name "$name" --argjson commands "$commands" '{
    schema: 4,
    lease: null,
    protected: [],
    checks: [],
    project: {name: $name},
    milestone: {id: "M1", title: "First milestone", status: "active"},
    shipped: [],
    requirements: [], phases: [], plans: [],
    fixes: [], todos: [], decisions: [],
    commands: $commands,
    settings: {profile: "balanced", autonomy_cap: 25},
    evidence: null
  }' > "$VBW_RUNTIME/record.init"
  record_back "$VBW_RUNTIME/record.init"
  mv "$VBW_RUNTIME/record.init" "$VBW_RECORD"
  # A new project starts with its writer file (the write step of every record write, R272)
  # and a current glance, written under the lock.
  ( vbw_guard_reset; record_lock; record_writer_write; record_glance_write; record_unlock ) || true
  record_gitignore || true
  printf 'Initialized VBW in %s\n' "$VBW_ROOT"
  printf '  .vbw/spec.md      what you are building (you own this file)\n'
  printf '  .vbw/record.json  the plan of record (written only by vbw)\n'
  local init_branch
  if init_branch=$(git -C "$VBW_ROOT" symbolic-ref --short -q HEAD 2> /dev/null) && [ -n "$init_branch" ]; then
    printf 'VBW commits its plan of record and the checks it plans to the branch checked out: %s\n' "$init_branch"
  else
    printf 'VBW commits its plan of record and the checks it plans to the commit checked out: no branch (detached HEAD at %s)\n' "$(git -C "$VBW_ROOT" rev-parse HEAD 2> /dev/null | cut -c1-12)"
  fi
  if [ "$commands" != "{}" ]; then
    printf '\nDetected project commands, not approved yet (vbw prove runs them only after\nyou approve them in the approval menu). Edit or delete them in .vbw/spec.md under Commands:\n'
    printf '%s\n' "$commands" | jq -r 'to_entries[] | "  \(.key): \(.value | join(" "))"'
  fi
  if [ -n "$big" ] && [ "$kind" = clone ]; then
    printf '\nLarge git-ignored folders (this disk clones them into every proof copy at little cost;\nkeeping them can save rebuilds):\n'
    printf '%s\n' "$big" | sed 's/^/  /'
  elif [ -n "$big" ]; then
    printf '\nLarge git-ignored folders (each is copied into every proof copy). They are written as\ncommented suggestions in .vbw/spec.md under Clean copy; uncomment a line to leave it out:\n'
    printf '%s\n' "$big" | sed 's/^/  /'
  fi
  init_said
  init_hidden
}

# The one line about .vbw/.gitignore (record_gitignore wrote something).
init_said() {
  printf 'VBW keeps its plan files visible to git through .vbw/.gitignore (runtime/ ignored; record.json, spec.md, map.md un-hidden)\n'
}

# An own file a rule hides that no line inside .vbw can undo (the whole folder): named on
# stderr with the rule's source and the fix; init itself still succeeds.
init_hidden() {
  ( cd "$VBW_ROOT" && record_hidden ) | sed 's/^/vbw: /' >&2 || true
}

# init_spec NAME COMMANDS_JSON: the starting spec.md.
init_spec() {
  cat <<EOF
# $1

## Goals

## Non-goals

## Constraints

## Requirements

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->

## Commands

<!-- The project's own commands, which every proof runs once you approve them.
     One per line: a name, then the command as words, or as a JSON array when
     an argument contains spaces. Edit or delete lines, then vbw spec sync.
- test: npm test
- build: ["make", "release build"]
-->
EOF
  # An argv whose words contain no whitespace reads as plain words.
  printf '%s' "$2" | jq -r 'to_entries[] | "- \(.key): " + (.value
    | if any(.[]; test("\\s") or startswith("[")) then tojson else join(" ") end)'
  cat <<'EOF'

## Clean copy

<!-- Git-ignored paths the proof's clean copy leaves out, such as a huge data
     folder or caches. One per line, relative to the project root; the rest of
     the ignored environment is still copied in. Edit lines, then vbw spec sync.
- data/
-->
EOF
  local c
  if [ -n "${3:-}" ] && [ "${4:-plain}" != clone ]; then
    printf '\n<!-- Large git-ignored folders found here; to leave one out, remove the comment marks around its line: -->\n'
    while IFS= read -r c; do
      [ -z "$c" ] || printf '<!-- - %s -->\n' "${c%% (*}"
    done <<< "$3"
  fi
}

# Detect the project's own test/lint/build commands as argv arrays (JSON object
# name -> argv). The first recognised ecosystem wins. Nothing is run.
init_detect_commands() {
  local root="$1" pm
  if [ -f "$root/package.json" ]; then
    pm=npm
    [ -f "$root/pnpm-lock.yaml" ] && pm=pnpm
    [ -f "$root/yarn.lock" ] && pm=yarn
    { [ -f "$root/bun.lockb" ] || [ -f "$root/bun.lock" ]; } && pm=bun
    jq -c --arg pm "$pm" '(.scripts // {}) as $s
      | [ (if $s.test then {key: "test", value: [$pm, "test"]} else empty end),
          ("lint", "typecheck", "build" | select($s[.]) | {key: ., value: [$pm, "run", .]}) ]
      | from_entries' "$root/package.json" 2>/dev/null || printf '{}\n'
  elif [ -f "$root/Cargo.toml" ]; then
    printf '{"test":["cargo","test"],"build":["cargo","build"]}\n'
  elif [ -f "$root/go.mod" ]; then
    printf '{"test":["go","test","./..."],"lint":["go","vet","./..."],"build":["go","build","./..."]}\n'
  elif [ -f "$root/pytest.ini" ] || { [ -f "$root/pyproject.toml" ] && grep -q '^\[tool\.pytest' "$root/pyproject.toml"; }; then
    printf '{"test":["python","-m","pytest"]}\n'
  elif [ -f "$root/Makefile" ]; then
    local t out='{}'
    for t in test lint build; do
      grep -q "^$t:" "$root/Makefile" && out=$(printf '%s' "$out" | jq -c --arg t "$t" '. + {($t): ["make", $t]}')
    done
    printf '%s\n' "$out"
  else
    # A project's own runner script, when no ecosystem is recognised.
    local s
    for s in test.sh tests.sh run_tests.sh; do
      if [ -f "$root/$s" ] && [ -x "$root/$s" ]; then
        jq -nc --arg s "./$s" '{test: [$s]}'
        return 0
      fi
    done
    printf '{}\n'
  fi
}
