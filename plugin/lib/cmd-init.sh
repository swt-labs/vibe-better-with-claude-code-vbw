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
  [ -f "$VBW_DIR/spec.md" ] || init_spec "$name" > "$VBW_DIR/spec.md"
  jq -n --arg name "$name" --argjson commands "$commands" '{
    schema: 1,
    project: {name: $name},
    milestone: {id: "M1", title: "First milestone", status: "active"},
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
    printf '\nDetected project commands (not approved; vbw prove runs them only after /vbw:approve):\n'
    printf '%s\n' "$commands" | jq -r 'to_entries[] | "  \(.key): \(.value | join(" "))"'
  fi
}

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
EOF
}

# Ensure .vbw/runtime/ is ignored by git (one exact line, added once).
init_gitignore() {
  local gi="$VBW_ROOT/.gitignore"
  if [ -f "$gi" ] && grep -qxF '.vbw/runtime/' "$gi"; then
    return 0
  fi
  if [ -s "$gi" ] && [ -n "$(tail -c 1 "$gi")" ]; then
    printf '\n' >> "$gi"
  fi
  printf '.vbw/runtime/\n' >> "$gi"
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
