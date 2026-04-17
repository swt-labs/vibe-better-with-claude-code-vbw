#!/usr/bin/env bash
set -euo pipefail

# verify-issue-157-migration-contract.sh — targeted contract coverage for
# command markdown migrated off embedded inline/path `!` spans.

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
  local file="$1"
  local pattern="$2"
  grep -Fq "$pattern" "$file"
}

contains_re() {
  local file="$1"
  local pattern="$2"
  grep -Eq "$pattern" "$file"
}

HELP_FILE="$ROOT/commands/help.md"
DISCUSS_FILE="$ROOT/commands/discuss.md"
UPDATE_FILE="$ROOT/commands/update.md"
WHATS_NEW_FILE="$ROOT/commands/whats-new.md"
DOCTOR_FILE="$ROOT/commands/doctor.md"
TEACH_FILE="$ROOT/commands/teach.md"
UNINSTALL_FILE="$ROOT/commands/uninstall.md"
RESEARCH_FILE="$ROOT/commands/research.md"
RELEASE_FILE="$ROOT/internal/release.md"

if contains "$HELP_FILE" 'Read `{plugin-root}/commands/{name}.md`'; then
  pass "help: reads command details via {plugin-root}"
else
  fail "help: missing {plugin-root} command-detail lookup"
fi

if contains "$DISCUSS_FILE" 'Read `{plugin-root}/references/discussion-engine.md`'; then
  pass "discuss: reads discussion engine via {plugin-root}"
else
  fail "discuss: missing {plugin-root} discussion-engine lookup"
fi

if contains "$UPDATE_FILE" 'Store as `old_version`. If empty, fall back to `{plugin-root}/VERSION`.' \
  && contains "$UPDATE_FILE" 'bash "{plugin-root}/scripts/cache-nuke.sh"'; then
  pass "update: uses safe {plugin-root} VERSION and cache-nuke references"
else
  fail "update: missing safe {plugin-root} VERSION/cache-nuke references"
fi

if contains "$WHATS_NEW_FILE" 'Read `{plugin-root}/VERSION` for current_version.' \
  && contains "$WHATS_NEW_FILE" 'Read `{plugin-root}/CHANGELOG.md`, split by `## [` headings.'; then
  pass "whats-new: uses safe {plugin-root} VERSION and CHANGELOG lookups"
else
  fail "whats-new: missing safe {plugin-root} VERSION/CHANGELOG lookups"
fi

if contains_re "$DOCTOR_FILE" '^Version:$'; then
  pass "doctor: version probe moved out of inline executable span"
else
  fail "doctor: version probe still appears inline"
fi

if contains_re "$TEACH_FILE" '^Codebase map:$' && contains_re "$TEACH_FILE" '^```text$'; then
  pass "teach: codebase map probe uses fenced block instead of inline span"
else
  fail "teach: codebase map probe missing fenced-block form"
fi

if contains_re "$UNINSTALL_FILE" '^Planning dir:$' \
  && contains_re "$UNINSTALL_FILE" '^CLAUDE\.md:$'; then
  pass "uninstall: status probes use fenced blocks instead of inline spans"
else
  fail "uninstall: status probes still appear inline"
fi

if contains "$RESEARCH_FILE" 'bash "{plugin-root}/scripts/todo-details.sh" get <hash>' \
  && contains "$RESEARCH_FILE" 'bash "{plugin-root}/scripts/resolve-agent-model.sh" scout .vbw-planning/config.json "{plugin-root}/config/model-profiles.json"' \
  && contains "$RESEARCH_FILE" 'bash "{plugin-root}/scripts/research-session-state.sh" start .vbw-planning "$RESEARCH_SLUG"'; then
  pass "research: uses safe {plugin-root} script callsites"
else
  fail "research: missing migrated {plugin-root} script callsites"
fi

if contains_re "$RELEASE_FILE" '^Version:$' \
  && contains_re "$RELEASE_FILE" '^Current branch:$'; then
  pass "release: inline executable context probes moved to fenced blocks"
else
  fail "release: inline executable context probes still present"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1
