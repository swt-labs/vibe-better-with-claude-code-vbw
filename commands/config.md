---
name: vbw:config
category: supporting
disable-model-invocation: true
description: View and modify VBW configuration including effort profile, verification tier, and skill-hook wiring.
argument-hint: [setting value]
allowed-tools: Read, Write, Edit, Bash, Glob
---

# VBW Config $ARGUMENTS

## Context

Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | sed -n 's/.*--plugin-dir  *\([^ ]*\).*/\1/p' | head -1); [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; rm -f "$LINK"; ln -s "$R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; echo "$LINK"`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found -- run /vbw:init first"`
```

## Guard

If no .vbw-planning/ dir: STOP "Run /vbw:init first." (check `.vbw-planning/config.json`)

## Behavior

### Step 0 (always): migrate brownfield config first

Before any read/write behavior below, run:

```bash
MIGRATED_COUNT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/migrate-config.sh --print-added .vbw-planning/config.json 2>/dev/null)
if [ $? -ne 0 ] || [ -z "${MIGRATED_COUNT:-}" ]; then
  echo "⚠ Config migration failed (invalid JSON). Fix .vbw-planning/config.json, then retry /vbw:config"
  exit 0
fi

if [ "$MIGRATED_COUNT" -gt 0 ]; then
  echo "✓ Added $MIGRATED_COUNT new settings from defaults (run /vbw:config to see them)"
fi
```

This backfills all missing keys from `config/defaults.json` (without overwriting existing values), and migrates legacy `agent_teams` to `prefer_teams` (then removes stale `agent_teams`).

### No arguments: Interactive configuration

**Step 1:** Display current settings in single-line box table (setting, value, description) + skill-hook mappings.

After the settings table, display Model Profile section:
```bash
PROFILE=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json)
echo ""
echo "Model Profile: $PROFILE"
echo "Agent Models:"
# Resolve each agent model
LEAD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh lead .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
DEV=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh dev .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
QA=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh qa .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
SCOUT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh scout .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
DEBUGGER=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
ARCHITECT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh architect .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
# Check for overrides and mark with asterisk
LEAD_DISPLAY=$LEAD
DEV_DISPLAY=$DEV
QA_DISPLAY=$QA
SCOUT_DISPLAY=$SCOUT
DEBUGGER_DISPLAY=$DEBUGGER
ARCHITECT_DISPLAY=$ARCHITECT
if [ "$(jq -r '.model_overrides.lead // ""' .vbw-planning/config.json)" != "" ]; then LEAD_DISPLAY="${LEAD}*"; fi
if [ "$(jq -r '.model_overrides.dev // ""' .vbw-planning/config.json)" != "" ]; then DEV_DISPLAY="${DEV}*"; fi
if [ "$(jq -r '.model_overrides.qa // ""' .vbw-planning/config.json)" != "" ]; then QA_DISPLAY="${QA}*"; fi
if [ "$(jq -r '.model_overrides.scout // ""' .vbw-planning/config.json)" != "" ]; then SCOUT_DISPLAY="${SCOUT}*"; fi
if [ "$(jq -r '.model_overrides.debugger // ""' .vbw-planning/config.json)" != "" ]; then DEBUGGER_DISPLAY="${DEBUGGER}*"; fi
if [ "$(jq -r '.model_overrides.architect // ""' .vbw-planning/config.json)" != "" ]; then ARCHITECT_DISPLAY="${ARCHITECT}*"; fi
echo "  Lead: $LEAD_DISPLAY | Dev: $DEV_DISPLAY | QA: $QA_DISPLAY | Scout: $SCOUT_DISPLAY | Debugger: $DEBUGGER_DISPLAY | Architect: $ARCHITECT_DISPLAY"
```

Note: Core infrastructure flags (v2_hard_contracts, v2_hard_gates, v2_typed_protocol, v2_role_isolation, v3_event_log, v3_delta_context, v3_context_cache, v3_plan_research_persist, v3_schema_validation, v3_contract_lite, v3_lock_lite) have graduated to always-on behavior. The remaining flags are configurable under unprefixed names (see Settings Reference below). Brownfield configs with old `v2_`/`v3_` prefixed keys are auto-migrated by `migrate-config.sh`.

**Step 2:** AskUserQuestion with up to 5 commonly changed settings (mark current values):
- Effort: thorough | balanced | fast | turbo
- Autonomy: cautious | standard | confident | pure-vibe
- Planning tracking: manual | ignore | commit
- Auto push: never | after_phase | always
- Model Profile

**Step 2.5:** If "Model Profile" was selected, AskUserQuestion with 2 options:
- Use preset profile (quality/balanced/budget)
- Configure each agent individually (6 questions)

Store selection in variable `PROFILE_METHOD`.

**Branching:**
- If `PROFILE_METHOD = "Use preset profile"`: AskUserQuestion with 3 options (quality | balanced | budget). Apply selected profile using model profile switching logic (lines 88-130).
- If `PROFILE_METHOD = "Configure each agent individually"`: Proceed to individual agent configuration flow (Round 1 below).

**Individual Configuration - Round 1 (4 agents):**

Calculate OLD_COST before making changes (cost weights: opus=100, sonnet=20, haiku=2):
```bash
CURRENT_PROFILE=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json)
PROFILES_PATH="`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json"

# Get current models (before changes)
LEAD_OLD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh lead .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
DEV_OLD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh dev .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
QA_OLD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh qa .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
SCOUT_OLD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh scout .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
DEBUGGER_OLD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
ARCHITECT_OLD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh architect .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)

# Calculate cost based on model
get_model_cost() {
  case "$1" in
    opus) echo 100 ;;
    sonnet) echo 20 ;;
    haiku) echo 2 ;;
    *) echo 0 ;;
  esac
}

OLD_COST=$(( $(get_model_cost "$LEAD_OLD") + $(get_model_cost "$DEV_OLD") + $(get_model_cost "$QA_OLD") + $(get_model_cost "$SCOUT_OLD") + $(get_model_cost "$DEBUGGER_OLD") + $(get_model_cost "$ARCHITECT_OLD") ))
```

Get current models for Lead, Dev, QA, Scout:
```bash
CURRENT_LEAD=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh lead .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
CURRENT_DEV=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh dev .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
CURRENT_QA=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh qa .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
CURRENT_SCOUT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh scout .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
```

AskUserQuestion with 4 questions:
- Lead model (current: $CURRENT_LEAD): opus | sonnet | haiku
- Dev model (current: $CURRENT_DEV): opus | sonnet | haiku
- QA model (current: $CURRENT_QA): opus | sonnet | haiku
- Scout model (current: $CURRENT_SCOUT): opus | sonnet | haiku

Store selections in variables `LEAD_MODEL`, `DEV_MODEL`, `QA_MODEL`, `SCOUT_MODEL`.

**Individual Configuration - Round 2 (2 agents):**

Get current models for Debugger and Architect:
```bash
CURRENT_DEBUGGER=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh debugger .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
CURRENT_ARCHITECT=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh architect .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)
```

AskUserQuestion with 2 questions:
- Debugger model (current: $CURRENT_DEBUGGER): opus | sonnet | haiku
- Architect model (current: $CURRENT_ARCHITECT): opus | sonnet | haiku

Store selections in variables `DEBUGGER_MODEL`, `ARCHITECT_MODEL`.

**Apply Individual Overrides:**

Ensure model_overrides object exists:
```bash
if ! jq -e '.model_overrides' .vbw-planning/config.json >/dev/null 2>&1; then
  jq '.model_overrides = {}' .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
fi
```

Apply each agent override:
```bash
jq ".model_overrides.lead = \"$LEAD_MODEL\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
echo "✓ Model override: lead ➜ $LEAD_MODEL"

jq ".model_overrides.dev = \"$DEV_MODEL\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
echo "✓ Model override: dev ➜ $DEV_MODEL"

jq ".model_overrides.qa = \"$QA_MODEL\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
echo "✓ Model override: qa ➜ $QA_MODEL"

jq ".model_overrides.scout = \"$SCOUT_MODEL\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
echo "✓ Model override: scout ➜ $SCOUT_MODEL"

jq ".model_overrides.debugger = \"$DEBUGGER_MODEL\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
echo "✓ Model override: debugger ➜ $DEBUGGER_MODEL"

jq ".model_overrides.architect = \"$ARCHITECT_MODEL\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
echo "✓ Model override: architect ➜ $ARCHITECT_MODEL"
```

**Cost Estimate Display:**

Calculate NEW_COST using selected models:
```bash
NEW_COST=$(( $(get_model_cost "$LEAD_MODEL") + $(get_model_cost "$DEV_MODEL") + $(get_model_cost "$QA_MODEL") + $(get_model_cost "$SCOUT_MODEL") + $(get_model_cost "$DEBUGGER_MODEL") + $(get_model_cost "$ARCHITECT_MODEL") ))

# Calculate percentage difference
if [ $OLD_COST -gt 0 ]; then
  DIFF=$(( (NEW_COST - OLD_COST) * 100 / OLD_COST ))
else
  DIFF=0
fi

echo ""
echo "Cost estimate (per phase):"
echo "  Before: ${OLD_COST} units (~${CURRENT_PROFILE} profile)"
if [ $DIFF -lt 0 ]; then
  DIFF_ABS=$(( -DIFF ))
  echo "  After:  ${NEW_COST} units (${DIFF_ABS}% reduction)"
elif [ $DIFF -gt 0 ]; then
  echo "  After:  ${NEW_COST} units (+${DIFF}% increase)"
else
  echo "  After:  ${NEW_COST} units (no change)"
fi
```

**Step 3:** Apply changes to config.json. Display ✓ per changed setting with ➜. No changes: "✓ No changes made."

**Step 4: Profile drift detection** — if effort/autonomy/verification_tier changed:
- Compare against active profile's expected values
- If mismatch: AskUserQuestion "Settings no longer match '{profile}'. Save as new profile?" → "Save" (route to /vbw:profile save) or "No" (set active_profile to "custom")
- Skip if no profile-tracked settings changed or already "custom"

Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh config` and display.

### With arguments: `<setting> <value>`

Validate setting + value. Update config.json. Display ✓ with ➜.

If `setting=planning_tracking`, after writing config run:

```bash
  PG_SCRIPT="`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/planning-git.sh"
  if [ -f "$PG_SCRIPT" ]; then
    bash "$PG_SCRIPT" sync-ignore .vbw-planning/config.json
  else
    echo "VBW: planning-git.sh unavailable; skipping .gitignore sync" >&2
  fi
```

This keeps root `.gitignore` and `.vbw-planning/.gitignore` aligned with the selected tracking mode.

### Skill-hook wiring: `skill_hook <skill> <event> <matcher>`

- `config skill_hook lint-fix PostToolUse Write|Edit`
- `config skill_hook test-runner PostToolUse Bash`
- `config skill_hook remove <skill>`

Stored in config.json `skill_hooks`:
```json
{"skill_hooks": {"lint-fix": {"event": "PostToolUse", "matcher": "Write|Edit"}}}
```

### Model profile switching: `model_profile <profile>`

Validates profile name (quality/balanced/budget), shows before/after cost estimate, updates config.json model_profile field.

```bash
PROFILE="$1"
PROFILES_PATH="`!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json"

# Validate profile
if ! jq -e ".$PROFILE" "$PROFILES_PATH" >/dev/null 2>&1; then
  echo "⚠ Unknown profile '$PROFILE'. Valid: quality, balanced, budget"
  exit 0
fi

# Get current profile
OLD_PROFILE=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json)

# Calculate cost estimate
# Cost weights: opus=100, sonnet=20, haiku=2
calc_cost() {
  local profile=$1
  local opus=$(jq "[.$profile | to_entries[] | select(.value == \"opus\")] | length" "$PROFILES_PATH")
  local sonnet=$(jq "[.$profile | to_entries[] | select(.value == \"sonnet\")] | length" "$PROFILES_PATH")
  local haiku=$(jq "[.$profile | to_entries[] | select(.value == \"haiku\")] | length" "$PROFILES_PATH")
  echo $(( opus * 100 + sonnet * 20 + haiku * 2 ))
}

OLD_COST=$(calc_cost "$OLD_PROFILE")
NEW_COST=$(calc_cost "$PROFILE")
DIFF=$(( (NEW_COST - OLD_COST) * 100 / OLD_COST ))

if [ $DIFF -lt 0 ]; then
  DIFF_ABS=$(( -DIFF ))
  echo "Switching from $OLD_PROFILE to $PROFILE (~${DIFF_ABS}% cost reduction per phase)"
else
  echo "Switching from $OLD_PROFILE to $PROFILE (~${DIFF}% cost increase per phase)"
fi

# Update config.json
jq ".model_profile = \"$PROFILE\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json

echo "✓ Model profile ➜ $PROFILE"
```

### Per-agent override: `model_override <agent> <model>`

Validates agent name (lead|dev|qa|scout|debugger|architect) and model (opus|sonnet|haiku). Updates config.json model_overrides object.

```bash
AGENT="$1"
MODEL="$2"

# Validate agent
case "$AGENT" in
  lead|dev|qa|scout|debugger|architect)
    # Valid
    ;;
  *)
    echo "⚠ Unknown agent '$AGENT'. Valid: lead, dev, qa, scout, debugger, architect"
    exit 0
    ;;
esac

# Validate model
case "$MODEL" in
  opus|sonnet|haiku)
    # Valid
    ;;
  *)
    echo "⚠ Unknown model '$MODEL'. Valid: opus, sonnet, haiku"
    exit 0
    ;;
esac

# Get current model for this agent
OLD_MODEL=$(bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/resolve-agent-model.sh "$AGENT" .vbw-planning/config.json `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/config/model-profiles.json)

echo "Set $AGENT model override: $MODEL (was: $OLD_MODEL)"

# Update config.json - ensure model_overrides object exists
if ! jq -e '.model_overrides' .vbw-planning/config.json >/dev/null 2>&1; then
  jq '.model_overrides = {}' .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
fi

jq ".model_overrides.$AGENT = \"$MODEL\"" .vbw-planning/config.json > .vbw-planning/config.json.tmp && mv .vbw-planning/config.json.tmp .vbw-planning/config.json

echo "✓ Model override: $AGENT ➜ $MODEL"
```

## Settings Reference

Note: `auto_commit` controls source-task commits during Execute mode. Planning artifact commit behavior is controlled by `planning_tracking`.

| Setting | Type | Values | Default |
|---------|------|--------|---------|
| effort | string | thorough/balanced/fast/turbo | balanced |
| autonomy | string | cautious/standard/confident/pure-vibe | standard |
| auto_commit | boolean | true/false | true |
| planning_tracking | string | manual/ignore/commit | manual |
| auto_push | string | never/after_phase/always | never |
| verification_tier | string | quick/standard/deep | standard |
| skill_suggestions | boolean | true/false | true |
| auto_install_skills | boolean | true/false | false |
| discovery_questions | boolean | true/false | true |
| visual_format | string | unicode/ascii | unicode |
| max_tasks_per_plan | number | 1-7 | 5 |
| prefer_teams | string | always/when_parallel/auto | always |
| branch_per_milestone | boolean | true/false | false |
| plain_summary | boolean | true/false | true |
| active_profile | string | profile name or "custom" | default |
| custom_profiles | object | user-defined profiles | {} |
| model_profile | string | quality/balanced/budget | quality |
| model_overrides | object | agent-to-model map | {} |
| agent_max_turns | object | per-agent turns (number), 0/false = unlimited | scout=15, qa=25, architect=30, debugger=80, lead=50, dev=75 |
| context_compiler | boolean | true/false | true |
| token_budgets | boolean | true/false | true |
| two_phase_completion | boolean | true/false | true |
| metrics | boolean | true/false | true |
| smart_routing | boolean | true/false | true |
| validation_gates | boolean | true/false | true |
| snapshot_resume | boolean | true/false | true |
| lease_locks | boolean | true/false | false |
| event_recovery | boolean | true/false | false |
| monorepo_routing | boolean | true/false | true |
| require_phase_discussion | boolean | true/false | false |
| auto_uat | boolean | true/false | false |
| rolling_summary | boolean | true/false | false |

### agent_max_turns

Controls how many turns each agent gets before the Task tool stops. Values are scaled by the current effort level (thorough = 1.5×, balanced = 1×, fast = 0.8×, turbo = 0.6×).

Set a per-agent value to `false` or `0` to give that agent unlimited turns (no `maxTurns` parameter is passed to the Task tool):

```json
{
  "agent_max_turns": {
    "dev": false,
    "debugger": 0
  }
}
```

You can also provide per-effort overrides using an object instead of a number:

```json
{
  "agent_max_turns": {
    "dev": { "thorough": 120, "balanced": 75, "fast": 50, "turbo": false }
  }
}
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — single-line box, ✓ success, ⚠ invalid, ➜ transitions, no ANSI.
