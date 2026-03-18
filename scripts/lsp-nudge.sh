#!/bin/bash
set -u
# PreToolUse hook: Nudge agents to use LSP instead of Grep for semantic queries
# Exit 0 = allow (always — this is advisory only, never blocks)
# Fail-OPEN: exit 0 on any parse error (never block legitimate Grep usage)

# --- Config override (fast path) ---
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
if command -v jq >/dev/null 2>&1 && [ -f "$PLANNING_DIR/config.json" ]; then
  NUDGE=$(jq -r '.lsp_nudge // true' "$PLANNING_DIR/config.json" 2>/dev/null)
  [ "$NUDGE" = "false" ] && exit 0
fi

# --- Parse input ---
if ! command -v jq >/dev/null 2>&1; then
  exit 0  # fail-open: no jq = can't inspect, allow silently
fi

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // ""' 2>/dev/null) || exit 0
[ -z "$PATTERN" ] && exit 0

# --- LSP availability guard ---
# Only nudge in projects that have a language with LSP support.
# Check for common project markers. If none found, skip — the project
# likely has no LSP server configured.
LSP_PROJECT=false
# Covers all 34 languages in config/lsp-mappings.json:
# Tier 1 (11): Swift, TypeScript/JS, Python, Go, Rust, Java, Kotlin, C/C++, C#, Lua, PHP
# Tier 2 (23): Scala, Ruby, HTML/CSS, Elixir, Dart, OCaml, PowerShell, LaTeX, Julia,
#   Ada, BSL, Solidity, Bash, Haskell, Clojure, Elm, Erlang, F#, R, Zig, Nix, Terraform
for marker in *.xcodeproj Package.swift \
              tsconfig.json jsconfig.json package.json \
              pyproject.toml setup.py setup.cfg requirements.txt \
              go.mod go.sum \
              Cargo.toml \
              *.sln *.csproj *.fsproj \
              build.gradle build.gradle.kts pom.xml \
              *.kt *.kts \
              build.sbt *.scala \
              Makefile CMakeLists.txt *.c *.cpp *.h \
              Gemfile *.gemspec \
              composer.json \
              mix.exs \
              pubspec.yaml \
              *.ps1 *.psm1 \
              *.tex *.bib \
              Project.toml *.jl \
              *.vue \
              *.ml *.mli dune-project \
              *.sol foundry.toml hardhat.config.* \
              *.adb *.ads *.gpr \
              *.bsl *.os \
              *.lua *.sh \
              *.hs stack.yaml cabal.project \
              deps.edn project.clj \
              elm.json \
              rebar.config *.erl \
              *.r *.R DESCRIPTION \
              *.zig build.zig \
              flake.nix default.nix \
              *.tf *.tfvars; do
  # shellcheck disable=SC2086
  if ls $marker 1>/dev/null 2>&1; then
    LSP_PROJECT=true
    break
  fi
done
[ "$LSP_PROJECT" = "false" ] && exit 0

# --- Semantic pattern detection ---
# Match Grep patterns that look like symbol definition searches.
# These are cases where LSP (documentSymbol, goToDefinition, findReferences)
# would be faster and more precise than text search.
#
# Matches: "class Foo", "struct Bar", "func doThing", "def process", etc.
# Does NOT match: bare identifiers, literal strings, config values, REQ-IDs
if echo "$PATTERN" | grep -qE '^(class|struct|enum|protocol|extension|func|function|def|type|interface|trait|impl|module|namespace|package)\s'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": "LSP hint: Use LSP tool (documentSymbol, goToDefinition, findReferences) instead of Grep for symbol lookups. Grep is for literal strings, config values, and non-code assets."
    }
  }'
fi

exit 0
