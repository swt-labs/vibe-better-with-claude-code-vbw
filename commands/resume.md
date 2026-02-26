---
name: vbw:resume
category: supporting
disable-model-invocation: true
description: Restore project context from .vbw-planning/ state.
argument-hint:
allowed-tools: Read, Bash, Glob
---

# VBW Resume

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || REAL_R="$R"; rm -f "$LINK"; ln -s "$REAL_R" "$LINK" 2>/dev/null || { echo "VBW: plugin root link failed" >&2; exit 1; }; STAMP="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; : > "$STAMP"; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
```

Pre-computed state (via phase-detect.sh):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; S="/tmp/.vbw-phase-detect-stamp-${SESSION_KEY}.txt"; PD=""; [ -f "$P" ] && PD=$(cat "$P"); if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; S_M=0; P_M=0; [ -f "$S" ] && S_M=$(stat -c %Y "$S" 2>/dev/null || stat -f %m "$S" 2>/dev/null || echo 0); [ -f "$P" ] && P_M=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo 0); if [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ] && { [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ "$P_M" -lt "$S_M" ]; }; then PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""; fi; fi; if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then printf '%s' "$PD"; else echo "phase_detect_error=true"; fi`
```

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **Brownfield normalization:** If Pre-computed state (from Context above) contains `misnamed_plans=true`, normalize all phase directories before proceeding:
   ```bash
   NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
   if [ -f "$NORM_SCRIPT" ]; then
     for pdir in .vbw-planning/phases/*/; do
       [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
     done
   fi
   ```
   Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
   Then re-run phase-detect.sh to refresh state:
   ```bash
   bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${CLAUDE_SESSION_ID:-default}.txt"
   ```
   Use the refreshed phase-detect output for all subsequent steps.
3. **No roadmap:** `.vbw-planning/ROADMAP.md` missing → STOP: "No roadmap found. Run /vbw:vibe."
4. **Phase-detect error:** If output contains `phase_detect_error=true`, display: "⚠ Phase detection failed. Run phase-detect.sh manually to debug." and STOP.

## Steps

1. **Read ground truth (top-level only):** Read these files from `.vbw-planning/` (NOT from `milestones/` — those are archived):
   - `.vbw-planning/PROJECT.md` — name, core value
   - `.vbw-planning/STATE.md` — decisions, todos, blockers
   - `.vbw-planning/ROADMAP.md` — phases overview
   - `.vbw-planning/.execution-state.json` — interrupted builds
   - `.vbw-planning/RESUME.md` — session notes
   - Glob `.vbw-planning/phases/**/*-PLAN.md` and `.vbw-planning/phases/**/*-SUMMARY.md` — plan/completion counts
   - Most recent SUMMARY.md from `.vbw-planning/phases/` — last work
   - Skip missing files. **Never read from `.vbw-planning/milestones/`.**
2. **Compute progress from phase-detect.sh output:** Use the pre-computed `phase_count`, `next_phase`, `next_phase_state`, `next_phase_plans`, `next_phase_summaries`, `uat_issues_phase`, `uat_issues_slug`, `uat_issues_phases`, and `uat_issues_count` values. Map `next_phase_state` to display: `needs_uat_remediation` → "⚠ Needs remediation", `needs_plan_and_execute` → "not started", `needs_execute` → "in progress", `all_done` → "complete". **Per-phase status:** any phase whose number appears in the comma-separated `uat_issues_phases` list has unresolved UAT issues — mark it "⚠ Needs remediation". Only mark a phase as "✓ Done" if its number is NOT in `uat_issues_phases` and it has completed execution (SUMMARY count ≥ PLAN count). Phases not yet executed are "not started".
3. **Detect interrupted builds:** If `.execution-state.json` status="running": all SUMMARYs present = completed since last session; some missing = interrupted.
4. **Present dashboard:** Phase Banner "Context Restored / {project name}" with: core value, phase/progress, overall progress bar, key decisions, todos, blockers (⚠), last completed, build status (✓ completed / ⚠ interrupted), session notes. Run `bash `!`echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`/scripts/suggest-next.sh resume`.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, Metrics Block, ⚠ warnings, ✓ completions, ➜ Next Up, no ANSI.
