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
  mkdir -p "$VBW_DIR/checks" "$VBW_RUNTIME"
  local name
  name=$(basename "$VBW_ROOT")
  [ -f "$VBW_DIR/spec.md" ] || init_spec "$name" > "$VBW_DIR/spec.md"
  jq -n --arg name "$name" '{
    schema: 1,
    project: {name: $name},
    milestone: {id: "M1", title: "First milestone", status: "active"},
    requirements: [], checks: [], phases: [], plans: [],
    fixes: [], todos: [], decisions: [],
    contract: {hash: null, approved_at: null},
    evidence: null, lease: null
  }' > "$VBW_RUNTIME/record.init"
  mv "$VBW_RUNTIME/record.init" "$VBW_RECORD"
  init_gitignore
  printf 'Initialized VBW in %s\n' "$VBW_ROOT"
  printf '  .vbw/spec.md      what you are building (you own this file)\n'
  printf '  .vbw/record.json  the plan of record (written only by vbw)\n'
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
