#!/usr/bin/env bash
# vbw init: create .vbw/ in the current git repository. Idempotent; never
# overwrites existing state; writes nothing outside the project.

cmd_init() {
  vbw_project
  if [ -f "$VBW_RECORD" ]; then
    init_gitignore
    printf 'VBW is already initialized in %s\n' "$VBW_ROOT"
    return 0
  fi
  mkdir -p "$VBW_RUNTIME"
  local name commands
  name=$(basename "$VBW_ROOT")
  commands=$(init_detect_commands "$VBW_ROOT")
  # The detected commands are a suggestion in spec.md, which the user owns; a
  # spec that already lists its own commands wins.
  if [ -f "$VBW_DIR/spec.md" ]; then
    commands=$(jq -Rs -f "$VBW_LIB/spec.jq" < "$VBW_DIR/spec.md" 2> /dev/null \
      | jq -c --argjson d "$commands" '.commands // $d' 2> /dev/null || printf '%s' "$commands")
  else
    init_spec "$name" "$commands" > "$VBW_DIR/spec.md"
  fi
  jq -n --arg name "$name" --argjson commands "$commands" '{
    schema: 1,
    project: {name: $name},
    milestone: {id: "M1", title: "First milestone", status: "active"},
    shipped: [],
    requirements: [], checks: [], phases: [], plans: [],
    fixes: [], todos: [], decisions: [],
    commands: $commands,
    settings: {profile: "balanced", autonomy_cap: 25},
    evidence: null, lease: null
  }' > "$VBW_RUNTIME/record.init"
  mv "$VBW_RUNTIME/record.init" "$VBW_RECORD"
  init_gitignore
  printf 'Initialized VBW in %s\n' "$VBW_ROOT"
  printf '  .vbw/spec.md      what you are building (you own this file)\n'
  printf '  .vbw/record.json  the plan of record (written only by vbw)\n'
  if [ "$commands" != "{}" ]; then
    printf '\nDetected project commands, not approved yet (vbw prove runs them only after\n/vbw:approve). Edit or delete them in .vbw/spec.md under Commands:\n'
    printf '%s\n' "$commands" | jq -r 'to_entries[] | "  \(.key): \(.value | join(" "))"'
  fi
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
}

# .vbw/runtime/ (locks, caches, check output) is never committed. VBW ignores it
# in its own .vbw/.gitignore and never edits the user's .gitignore.
init_gitignore() {
  [ -f "$VBW_DIR/.gitignore" ] || printf 'runtime/\n' > "$VBW_DIR/.gitignore"
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
    printf '{}\n'
  fi
}
