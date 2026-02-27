---
name: vbw:status
category: monitoring
description: Display project progress dashboard with phase status, velocity metrics, and next action.
argument-hint: [--verbose] [--metrics]
allowed-tools: Read, Glob, Grep, Bash
---

# VBW Status $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; rm -f "$LINK"; ln -s "$REAL_R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; STAMP="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; : > "$STAMP"; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
```

Current state:
```
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Roadmap:
```
!`head -50 .vbw-planning/ROADMAP.md 2>/dev/null || echo "No roadmap found"`
```

Config: Pre-injected by SessionStart hook. Read .vbw-planning/config.json only if --verbose.

Phase directories:
```
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; S="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; PD=""; [ -f "$P" ] && PD=$(cat "$P"); if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; S_M=0; P_M=0; [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0); [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0); if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""; fi; fi; if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then printf '%s' "$PD"; else echo "phase_detect_error=true"; fi`
```

Shipped milestones:
```
!`ls -d .vbw-planning/milestones/*/SHIPPED.md 2>/dev/null || echo "No shipped milestones"`
```

## Guard

- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- **Brownfield normalization:** If Phase state (from Context above) contains `misnamed_plans=true`, normalize all phase directories before proceeding:
  ```bash
  NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
  if [ -f "$NORM_SCRIPT" ]; then
    for pdir in .vbw-planning/phases/*/; do
      [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
    done
  fi
  ```
  Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
  Then re-run phase-detect.sh to refresh state (filenames changed):
  ```bash
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${CLAUDE_SESSION_ID:-default}.txt"
  ```
  Use the refreshed phase-detect output for all subsequent steps.
- No ROADMAP.md or has template placeholders: STOP "No roadmap found. Run /vbw:vibe to set up your project."

## Steps

1. **Parse args:** --verbose shows per-plan detail within each phase
2. **Resolve paths:** Use `.vbw-planning/phases/` for phase directories. Gather milestone list from `.vbw-planning/milestones/` (dirs with SHIPPED.md).
3. **Read data:** (STATE.md and ROADMAP.md use compact format -- flat fields, no verbose prose)
   - STATE.md: project name, current phase (flat `Phase:`, `Plans:`, `Progress:` lines), velocity
   - ROADMAP.md: phases, status markers, plan counts (compact per-phase fields, Progress table)
   - SessionStart injection: effort, autonomy. If --verbose, read config.json
   - Phase dirs: glob `*-PLAN.md` and `*-SUMMARY.md` per phase for completion data
   - If Agent Teams build active: read shared task list for teammate status
   - Cost ledger: if `.vbw-planning/.cost-ledger.json` exists, read with jq. Extract per-agent costs. Compute total. Only display economy if total > 0.
4. **Compute progress:** Per phase: count PLANs (total) vs SUMMARYs (done). Pct = done/total * 100. Status: ✓ (100%), ◆ (1-99%), ○ (0%).
5. **Compute velocity:** Total plans done, avg duration, total time. If --verbose: per-phase breakdown.
6. **Next action:** Find first incomplete phase. Has plans but not all summaries: `/vbw:vibe` (auto-executes). Complete + next unplanned: `/vbw:vibe` (auto-plans). All complete: `/vbw:vibe --archive`. No plans anywhere: `/vbw:vibe`.

## Display

Per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:

**Header:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {project-name}
  {progress-bar} {percent}%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Multi-milestone** (if multiple):
```
  Milestones:
    ◆ {active-slug}    {bar} {%}  ({done}/{total} phases)
    ○ {other-slug}     {bar} {%}  ({done}/{total} phases)
```

**Phases:** `✓/◆/○ Phase N: {name}  {██░░} {%}  ({done}/{total} plans)`. If --verbose, indent per-plan detail with duration.

**Agent Teams** (if active): `◆/✓/○ {Agent}: Plan {NN} ({status})`

**Velocity:**
```
  Velocity:
    Plans completed:  {N}
    Average duration: {time}
    Total time:       {time}
```

**Economy** (only if .cost-ledger.json exists AND total > $0.00): Read ledger with jq. Sort agents by cost desc. Show dollar + pct per agent. Include cache hit rate if available.
```
  Economy:
    Total cost:   ${total}
    Per agent:
      Dev          $0.82   70%
      Lead         $0.15   13%
    Cache hit rate: {percent}%
```

**Next Up:** Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh status` and display.
