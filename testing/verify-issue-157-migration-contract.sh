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
CONFIG_FILE="$ROOT/commands/config.md"
DEBUG_FILE="$ROOT/commands/debug.md"
FIX_FILE="$ROOT/commands/fix.md"
INIT_FILE="$ROOT/commands/init.md"
MAP_FILE="$ROOT/commands/map.md"
QA_FILE="$ROOT/commands/qa.md"
VERIFY_FILE="$ROOT/commands/verify.md"
UPDATE_FILE="$ROOT/commands/update.md"
WHATS_NEW_FILE="$ROOT/commands/whats-new.md"
DOCTOR_FILE="$ROOT/commands/doctor.md"
TEACH_FILE="$ROOT/commands/teach.md"
UNINSTALL_FILE="$ROOT/commands/uninstall.md"
RESEARCH_FILE="$ROOT/commands/research.md"
RELEASE_FILE="$ROOT/internal/release.md"

PLUGIN_ROOT_FILES=(
  "$CONFIG_FILE"
  "$DEBUG_FILE"
  "$DISCUSS_FILE"
  "$FIX_FILE"
  "$HELP_FILE"
  "$INIT_FILE"
  "$MAP_FILE"
  "$QA_FILE"
  "$RESEARCH_FILE"
  "$UPDATE_FILE"
  "$VERIFY_FILE"
  "$WHATS_NEW_FILE"
)

for file in "${PLUGIN_ROOT_FILES[@]}"; do
  base="$(basename "$file")"
  if contains "$file" 'Store the plugin root path output above as `{plugin-root}`'; then
    pass "$base: declares the {plugin-root} literal-substitution convention"
  else
    fail "$base: missing {plugin-root} literal-substitution instruction"
  fi
done

if contains "$CONFIG_FILE" 'bash "{plugin-root}/scripts/migrate-config.sh"' \
  && contains "$CONFIG_FILE" 'bash "{plugin-root}/scripts/resolve-agent-model.sh"' \
  && contains "$CONFIG_FILE" 'PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"'; then
  pass "config: uses safe {plugin-root} lookups plus deterministic planning-git path"
else
  fail "config: missing migrated {plugin-root} / planning-git callsites"
fi

if contains "$DEBUG_FILE" 'bash "{plugin-root}/scripts/debug-session-state.sh"' \
  && contains "$DEBUG_FILE" 'bash "{plugin-root}/scripts/write-debug-session.sh"' \
  && contains "$DEBUG_FILE" '{plugin-root}/references/handoff-schemas.md'; then
  pass "debug: uses safe {plugin-root} session and handoff references"
else
  fail "debug: missing migrated {plugin-root} session/handoff references"
fi

if contains "$FIX_FILE" 'bash "{plugin-root}/scripts/todo-details.sh" get <hash>' \
  && contains "$FIX_FILE" 'bash "{plugin-root}/scripts/resolve-agent-model.sh" dev .vbw-planning/config.json "{plugin-root}/config/model-profiles.json"' \
  && contains "$FIX_FILE" 'bash "{plugin-root}/scripts/suggest-next.sh" fix'; then
  pass "fix: uses safe {plugin-root} helper callsites"
else
  fail "fix: missing migrated {plugin-root} helper callsites"
fi

if contains "$INIT_FILE" 'bash "{plugin-root}/scripts/generate-gsd-index.sh"' \
  && contains "$INIT_FILE" 'bash "{plugin-root}/scripts/bootstrap/bootstrap-project.sh"' \
  && contains "$INIT_FILE" 'PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"'; then
  pass "init: uses safe {plugin-root} bootstrap helpers plus deterministic planning-git path"
else
  fail "init: missing migrated bootstrap/planning-git callsites"
fi

if contains "$MAP_FILE" 'bash "{plugin-root}/scripts/normalize-prefer-teams.sh"' \
  && contains "$MAP_FILE" 'bash "{plugin-root}/scripts/clean-stale-teams.sh"' \
  && contains "$MAP_FILE" '{plugin-root}/references/handoff-schemas.md'; then
  pass "map: uses safe {plugin-root} helper and handoff references"
else
  fail "map: missing migrated {plugin-root} helper/handoff references"
fi

if contains "$QA_FILE" 'bash "{plugin-root}/scripts/qa-result-gate.sh"' \
  && contains "$QA_FILE" 'bash "{plugin-root}/scripts/track-known-issues.sh" promote-todos' \
  && contains "$QA_FILE" 'bash "{plugin-root}/scripts/resolve-agent-model.sh" qa .vbw-planning/config.json "{plugin-root}/config/model-profiles.json"'; then
  pass "qa: uses safe {plugin-root} gate, known-issues, and model-resolution callsites"
else
  fail "qa: missing migrated {plugin-root} gate/known-issues/model callsites"
fi

if contains "$VERIFY_FILE" 'bash "{plugin-root}/scripts/compile-verify-context-for-uat.sh"' \
  && contains "$VERIFY_FILE" 'bash "{plugin-root}/scripts/finalize-uat-status.sh"' \
  && contains "$VERIFY_FILE" 'PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"'; then
  pass "verify: uses safe {plugin-root} UAT helpers plus deterministic planning-git path"
else
  fail "verify: missing migrated UAT/planning-git callsites"
fi

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
