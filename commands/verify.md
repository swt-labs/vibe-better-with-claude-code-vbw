---
name: vbw:verify
category: monitoring
disable-model-invocation: true
description: Run human acceptance testing on completed phase work. Presents CHECKPOINT prompts one at a time.
argument-hint: "[phase-number] [--resume]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, LSP
---

# VBW Verify: $ARGUMENTS

## Context

Working directory:
```bash
!`pwd`
```
Plugin root:
```bash
!`VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"; R=""; if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi; if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi; if [ -z "$R" ]; then V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1); [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"; fi; if [ -z "$R" ]; then L=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1); [ -n "$L" ] && [ -f "${VBW_CACHE_ROOT}/${L}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${L}"; fi; if [ -z "$R" ]; then for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break; done; fi; if [ -z "$R" ]; then D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1); D="${D#--plugin-dir }"; [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"; fi; if [ -z "$R" ] || [ ! -d "$R" ]; then echo "VBW: plugin root resolution failed" >&2; exit 1; fi; SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || { echo "VBW: plugin root canonicalization failed" >&2; exit 1; }; bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R" >/dev/null 2>&1 || { echo "VBW: plugin root link failed" >&2; exit 1; }; bash "$LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$LINK"`
```

Current state:
```bash
!`head -40 .vbw-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook.

Phase directories:
```bash
!`ls .vbw-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:
```bash
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local VBW_CACHE_ROOT R V D REAL_R
  VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
  R=""
  if [ -z "$R" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi
  if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do
      [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break
    done
  fi
  if [ -z "$R" ]; then
    D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1)
    D="${D#--plugin-dir }"
    [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"
  fi
  if [ -z "$R" ] || [ ! -d "$R" ] || [ ! -f "$R/scripts/phase-detect.sh" ]; then
    return 1
  fi
  REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || return 1
  bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
  PD=$(bash "$REAL_R/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect; then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  echo "phase_detect_error=true"
fi`
```

!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/suggest-compact.sh" verify 2>/dev/null || true`

Pre-computed verify context (PLAN/SUMMARY aggregation):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local VBW_CACHE_ROOT R V D REAL_R
  VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
  R=""
  if [ -z "$R" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi
  if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do
      [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break
    done
  fi
  if [ -z "$R" ]; then
    D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1)
    D="${D#--plugin-dir }"
    [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"
  fi
  if [ -z "$R" ] || [ ! -d "$R" ] || [ ! -f "$R/scripts/phase-detect.sh" ]; then
    return 1
  fi
  REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || return 1
  bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
  PD=$(bash "$REAL_R/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect; then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
  echo "verify_context=unavailable"
else
  STATE=$(printf '%s' "$PD" | grep '^next_phase_state=' | head -1 | cut -d= -f2)
  SLUG=$(printf '%s' "$PD" | grep '^next_phase_slug=' | head -1 | cut -d= -f2)
  FU_SLUG=$(printf '%s' "$PD" | grep '^first_unverified_slug=' | head -1 | cut -d= -f2)
  if [ "$STATE" = "needs_reverification" ] || [ "$STATE" = "needs_verification" ]; then TARGET="$SLUG"; else TARGET="${FU_SLUG:-$SLUG}"; fi
  PDIR=".vbw-planning/phases/$TARGET"
  if [ -n "$TARGET" ] && [ -d "$PDIR" ] && [ -L "$L" ] && [ -f "$L/scripts/compile-verify-context-for-uat.sh" ]; then
    echo "verify_target_slug=$TARGET"
    bash "$L/scripts/compile-verify-context-for-uat.sh" "$PDIR" 2>/dev/null || echo "verify_context_error=true"
  else
    echo "verify_context=unavailable"
  fi
fi`
```

Pre-computed UAT resume metadata:
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local VBW_CACHE_ROOT R V D REAL_R
  VBW_CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
  R=""
  if [ -z "$R" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh" ]; then R="${CLAUDE_PLUGIN_ROOT}"; fi
  if [ -z "$R" ] && [ -f "${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh" ]; then R="${VBW_CACHE_ROOT}/local"; fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    V=$(find "${VBW_CACHE_ROOT}" -maxdepth 1 -mindepth 1 2>/dev/null | awk -F/ '{print $NF}' | sort | tail -1)
    [ -n "$V" ] && [ -f "${VBW_CACHE_ROOT}/${V}/scripts/hook-wrapper.sh" ] && R="${VBW_CACHE_ROOT}/${V}"
  fi
  if [ -z "$R" ]; then
    for f in /tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh; do
      [ -f "$f" ] && R="${f%/scripts/hook-wrapper.sh}" && break
    done
  fi
  if [ -z "$R" ]; then
    D=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1)
    D="${D#--plugin-dir }"
    [ -n "$D" ] && [ -f "$D/scripts/hook-wrapper.sh" ] && R="$D"
  fi
  if [ -z "$R" ] || [ ! -d "$R" ] || [ ! -f "$R/scripts/phase-detect.sh" ]; then
    return 1
  fi
  REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || return 1
  bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
  PD=$(bash "$REAL_R/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect; then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
  echo "uat_resume=unavailable"
else
  STATE=$(printf '%s' "$PD" | grep '^next_phase_state=' | head -1 | cut -d= -f2)
  SLUG=$(printf '%s' "$PD" | grep '^next_phase_slug=' | head -1 | cut -d= -f2)
  FU_SLUG=$(printf '%s' "$PD" | grep '^first_unverified_slug=' | head -1 | cut -d= -f2)
  if [ "$STATE" = "needs_reverification" ] || [ "$STATE" = "needs_verification" ]; then TARGET="$SLUG"; else TARGET="${FU_SLUG:-$SLUG}"; fi
  PDIR=".vbw-planning/phases/$TARGET"
  if [ -n "$TARGET" ] && [ -d "$PDIR" ] && [ -L "$L" ] && [ -f "$L/scripts/extract-uat-resume.sh" ]; then
    echo "uat_resume_target_slug=$TARGET"
    bash "$L/scripts/extract-uat-resume.sh" "$PDIR" 2>/dev/null || echo "uat_resume=error"
  else
    echo "uat_resume=unavailable"
  fi
fi`
```

QA verification summary (pre-extracted from VERIFICATION.md):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; if [ -L "$L" ] && [ -f "$L/scripts/extract-verified-items.sh" ]; then for d in .vbw-planning/phases/*/; do bash "$L/scripts/extract-verified-items.sh" "$d" 2>/dev/null; done; fi`
```

## Guard

- Not initialized (no .vbw-planning/ dir): STOP "Run /vbw:init first."
- **Phase-detect error guard (NON-NEGOTIABLE):** If Phase state (from Context above) contains `phase_detect_error=true`, display: "⚠ Phase detection failed. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh` manually to debug." STOP. Do NOT fall back to phase-dir scanning or ad-hoc `VERIFICATION.md` checks when phase-detect failed.
- **Verify-context error guard (NON-NEGOTIABLE):** If the pre-computed verify context block contains `verify_context_error=true` or `verify_context=unavailable`, display: "⚠ Verify context compilation failed. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context.sh .vbw-planning/phases/{NN}-{slug}` manually to debug." STOP. Do NOT improvise by reading individual PLAN/SUMMARY files unless the user explicitly targeted a different phase number (see Step 1).
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
  Use the refreshed phase-detect output for all subsequent guard checks and steps. Also regenerate pre-computed verify context and UAT resume metadata for the target phase after auto-detection (Step 1).
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above (or refreshed by normalization above). Use `next_phase` and `next_phase_slug` for the target phase.
  - If `next_phase_state=needs_reverification`: use `next_phase` directly — this is the phase that just completed remediation and needs re-verification.
  - If `next_phase_state=needs_verification`: use `next_phase` directly — this is the first fully-built phase that needs UAT verification (auto_uat routing).
  - If `first_unverified_phase` is set: use that phase directly — this is the first fully-built phase without a terminal UAT.
  - Fallback: scan phase dirs for first with `*-SUMMARY.md` but no canonical `*-UAT.md` (exclude `*-SOURCE-UAT.md` copies).
  - Found: announce "Auto-detected Phase {NN} ({slug})". All verified: STOP "All phases have UAT results. Specify: `/vbw:verify {NN}`"
- No SUMMARY.md in target phase dir: STOP "Phase {NN} has no completed plans. Run /vbw:vibe first."
- **QA gate (NON-NEGOTIABLE unless `--skip-qa`):** Before entering UAT Steps, check whether QA has passed for the target phase. Use `qa_status` from Phase state only when the target phase is the same as the auto-detected `verify_target_slug` / first-unverified phase. If the user specified an explicit phase number that differs from the auto-detected target, ignore the pre-computed `qa_status` and compute the gate from that explicit phase's own VERIFICATION.md + QA remediation state.
  ```bash
  PDIR=".vbw-planning/phases/{target-slug}"
  PHASE_NUM=$(echo "{target-slug}" | sed 's/^\([0-9]*\).*/\1/')
  VERIF_FILE=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-verification-path.sh phase "$PDIR" 2>/dev/null || true)
  [ -n "$VERIF_FILE" ] && [ ! -f "$VERIF_FILE" ] && VERIF_FILE=""
  QA_REM_FILE="$PDIR/remediation/qa/.qa-remediation-stage"
  QA_REM_STAGE="none"
  if [ -f "$QA_REM_FILE" ]; then
    QA_REM_STAGE=$(grep '^stage=' "$QA_REM_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    QA_REM_STAGE="${QA_REM_STAGE:-none}"
    case "$QA_REM_STAGE" in
      plan|execute|verify|done) ;;
      *) QA_REM_STAGE="none" ;;
    esac
  fi
  ```
  - If `QA_REM_STAGE` is `plan`, `execute`, or `verify`: STOP "Phase {NN} has active QA remediation (round {round}, stage {stage}). Run `/vbw:vibe` to continue QA remediation before UAT."
  - If `QA_REM_STAGE=done`: refresh `VERIF_FILE` before reading `result:` or running stale-QA checks:
    ```bash
    VERIF_FILE=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-verification-path.sh current "$PDIR" 2>/dev/null || true)
    [ -n "$VERIF_FILE" ] && [ ! -f "$VERIF_FILE" ] && VERIF_FILE=""
    if [ -z "$VERIF_FILE" ]; then
      echo "Phase {NN} QA remediation is done, but the round-scoped VERIFICATION artifact is missing. Run /vbw:vibe to restore the remediation artifact before UAT." >&2
      exit 1
    fi
    ```
    This requires the remediated round VERIFICATION.md. The phase-level VERIFICATION.md stays frozen and must not be reused once QA remediation reaches `done`.
  - If `QA_REM_FILE` exists but `QA_REM_STAGE=none` after normalization, treat it as corrupt/stale and continue using the resolved `VERIF_FILE` above.
  - If no VERIFICATION.md and no `--skip-qa`: STOP "Phase {NN} has no QA verification. Run `/vbw:vibe` to execute QA first, or use `/vbw:verify --skip-qa` to bypass."
  - If `VERIF_FILE` exists but `known-issues.json` is missing or malformed, restore the authoritative registry before trusting QA/UAT state:
    ```bash
    KNOWN_ISSUES_META=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh status "$PDIR" 2>/dev/null || true)
    KNOWN_ISSUES_STATUS=$(printf '%s\n' "$KNOWN_ISSUES_META" | awk -F= '/^known_issues_status=/{print $2; exit}')
    if [ -n "$VERIF_FILE" ] && { [ "$KNOWN_ISSUES_STATUS" = "missing" ] || [ "$KNOWN_ISSUES_STATUS" = "malformed" ]; }; then
      bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh sync-verification "$PDIR" "$VERIF_FILE" 2>/dev/null || true
      bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh promote-todos "$PDIR" 2>/dev/null || true
    fi
    ```
  - Before trusting any PASS artifact, re-run the deterministic QA gate for the target phase:
    ```bash
    QA_GATE_ROUTING=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-result-gate.sh "$PDIR" 2>/dev/null | awk -F= '/^qa_gate_routing=/{print $2; exit}')
    ```
    - `PROCEED_TO_UAT`: continue to the freshness checks below.
    - `REMEDIATION_REQUIRED`: STOP "Phase {NN} QA gate still requires remediation (including unresolved tracked known issues, if any). Run `/vbw:vibe` to continue QA remediation before UAT."
    - `QA_RERUN_REQUIRED` or empty output: STOP "Phase {NN} QA verification is not authoritative yet. Run `/vbw:qa {NN}` or `/vbw:vibe` to re-run QA before UAT, or use `/vbw:verify --skip-qa` to bypass."
  - If VERIFICATION.md exists, read its frontmatter `result:` field:
    - `PASS`: before proceeding, run the same stale-QA checks as phase-detect for this target phase: (1) if product-code working tree is dirty (`git status --porcelain --untracked-files=normal -- . ':!.vbw-planning' ':!CLAUDE.md'` non-empty) → STOP and rerun QA via `/vbw:vibe`; (2) if `verified_at_commit` exists and differs from current product-code `git log -1 --format='%H' -- . ':!.vbw-planning' ':!CLAUDE.md'` → STOP and rerun QA; (3) if `verified_at_commit` is absent (brownfield file), compare VERIFICATION.md mtime to the latest product-code commit timestamp and STOP if the commit is newer. Only proceed to UAT when the PASS is both gate-authoritative and fresh for the target phase.
    - `FAIL` or `PARTIAL`: STOP "Phase {NN} QA result is {result}. Run `/vbw:vibe` to continue QA remediation, or use `/vbw:verify --skip-qa` to bypass."
  - If `--skip-qa` flag is present: bypass QA execution and PASS freshness checks only. This does **not** bypass unresolved phase known issues. Before entering UAT, run:
    ```bash
    KNOWN_ISSUES_META=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh status "$PDIR" 2>/dev/null || true)
    KNOWN_ISSUES_STATUS=$(printf '%s\n' "$KNOWN_ISSUES_META" | awk -F= '/^known_issues_status=/{print $2; exit}')
    KNOWN_ISSUES_COUNT=$(printf '%s\n' "$KNOWN_ISSUES_META" | awk -F= '/^known_issues_count=/{print $2; exit}')
    ```
    If `KNOWN_ISSUES_STATUS=malformed` or `KNOWN_ISSUES_COUNT > 0`, STOP: "Phase {NN} still has unresolved or unreadable tracked known issues. Run `/vbw:vibe` to continue QA remediation before UAT."

## Steps

### 1. Resolve phase and load summaries

- Parse explicit phase number from $ARGUMENTS, or use auto-detected phase
- Use `.vbw-planning/phases/` for phase directories
- **If initial Phase state contained `misnamed_plans=true`:** re-run compile-verify-context.sh and extract-uat-resume.sh for the resolved target phase dir, since pre-computed blocks used stale filenames:
  ```bash
  PDIR=".vbw-planning/phases/{target-slug}"
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh" "$PDIR"
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-uat-resume.sh" "$PDIR"
  ```
  Use the refreshed output in place of the pre-computed blocks from Context.
- Use pre-computed verify context from the "Pre-computed verify context" block above (or refreshed output if normalization ran or Step 2 refreshed re-verification state) — it contains per-plan titles, must_haves, what was built, files modified, and status. Do NOT read individual `*-SUMMARY.md` or `*-PLAN.md` files.
- **Parse `verify_scope`** from the first line of the verify context block. When `verify_scope=remediation round=RR`, this is a re-verification session scoped to remediation round RR only. When `verify_scope=full`, standard full-scope verification. Use this in Step 4 to determine test framing.
- **Parse `uat_path`** from the second line of the verify context block. This is the relative path (from phase dir) where the UAT file should be written — e.g., `03-UAT.md` for full scope or `remediation/uat/round-01/R01-UAT.md` for remediation scope. Use this in Steps 4, 8, and 9 instead of hardcoding `{phase}-UAT.md`.
- **Remediation safety check:** If `verify_scope=remediation` and `uat_path` does not already point at the current remediation round's round-scoped UAT path (`remediation/uat/round-{RR}/R{RR}-UAT.md` for round-dir layout, `remediation/round-{RR}/R{RR}-UAT.md` for legacy layout), run:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh get-or-init "{phase-dir}" major
  ```
  Parse `round=RR` and `layout=...`, then override `uat_path` with the matching round-scoped path for that layout before Step 4 writes any UAT file. This applies to resumed `needs_reverification` sessions too.
- **If user specified an explicit phase number** that differs from `verify_target_slug`, ignore the pre-computed verify context, `next_phase_state`, `qa_status`, and UAT resume metadata from the auto-detected phase. Recompute target-specific verify context and UAT resume metadata:
  ```bash
  PDIR=".vbw-planning/phases/{target-slug}"
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh" "$PDIR"
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-uat-resume.sh" "$PDIR"
  ```
  Use this target-specific output instead of the auto-detected blocks from Context. Do NOT force full scope — let `compile-verify-context-for-uat.sh` decide whether the explicit target phase is full-scope verification or remediation re-verification. Apply the QA gate above to the explicit target phase only.
  Then check the explicit target's own remediation stage:
  ```bash
  bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh" get "{phase-dir}"
  ```
  If that stage is `research`, `plan`, `execute`, or `fix`, STOP: `Phase {NN} has active UAT remediation (stage {stage}). Run /vbw:vibe to continue remediation before re-verification.`

### 2. Handle re-verification state

- If the active target phase needs re-verification:
  - For auto-detected routing, use `next_phase_state=needs_reverification` from Context above.
  - For an explicit target phase, ignore the auto-detected `next_phase_state` and only enter this step when the explicit target's own current UAT status is `issues_found` and its UAT remediation stage is `done` or `verify`.
  - Run `prepare-reverification.sh {phase-dir}` to archive the old UAT and reset remediation stage
  - If the script outputs `skipped=already_archived`, display: `UAT already archived. Starting fresh re-verification.`
  - If the script fails (non-zero exit), display the error message and **STOP** — do not continue to Step 3
  - If `archived=kept`: display: `Phase UAT preserved. Starting fresh re-verification in round dir.`
  - Otherwise display: `Archived previous UAT → {round_file}. Starting fresh re-verification.`
  - Immediately refresh verify context and UAT resume metadata:
    ```bash
    bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "{phase-dir}"
    bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-uat-resume.sh "{phase-dir}"
    ```
  - Use this refreshed output instead of the pre-computed verify context and UAT resume metadata for the rest of the session.
  - Continue to Step 3 (generate new tests) — do NOT resume the old UAT

### 3. Check for existing UAT session (resume support)

- Use UAT resume metadata for the active target phase (the pre-computed auto-detected block, the target-specific refresh from Step 1, or the refreshed metadata from Step 2 for re-verification):
  - `uat_resume=none`: no existing UAT session — proceed to Step 4 (generate tests)
  - `uat_resume=all_done uat_completed=N uat_total=N`: all tests already have results — display the summary, STOP
  - `uat_resume=<test-id> uat_completed=N uat_total=N`: resume at `<test-id>`. Display: `Resuming UAT session -- {completed}/{total} tests done`. Read the UAT.md once to load checkpoint text, then jump to the CHECKPOINT loop at the resume point.
- Do NOT scan-parse the UAT file to find the resume point — the pre-computed metadata already identifies it.

### 4. Generate test scenarios from pre-computed verify context

**Check `verify_scope` in the pre-computed verify context block.** Two modes:

**Re-verification mode** (`verify_scope=remediation round=RR`): The context contains ONLY plans from the latest remediation round. These plans fixed issues found in a previous UAT session. Frame test scenarios to verify the remediation worked:
- Each plan's `must_haves` reference the original UAT issues that were remediated
- Generate 1-3 tests per plan focused on: "The original issue was {must_have description}. Verify the fix resolves it."
- Tests should confirm the specific bug/issue is no longer present, not re-test the entire phase
- Same test ID format (`P{plan}-T{NN}`), same UAT.md template, same rules below

**Full-scope mode** (`verify_scope=full`): Standard verification of all phase plans. Use the rules below as-is.

For each plan in the pre-computed verify context block:
- Use the pre-computed `what_was_built`, `files_modified`, and `must_haves` data. Do NOT read SUMMARY.md or PLAN.md files.
- Generate 1-3 test scenarios that require HUMAN judgment — things only a person can verify
- Minimum 1 test per plan, even for pure refactors (use "verify nothing broke" regression test)
- Test IDs follow the format: `P{plan}-T{NN}` (e.g., P01-T1, P01-T2, P02-T1)

**UAT tests must be things only a human can judge.** Good examples:
- Open the app and navigate to screen X — does it display Y correctly?
- Perform user workflow A → B → C — does the result look right?
- Check that the UI reflects the change — is the label/value/layout correct?

**NEVER generate tests that ask the user to run automated checks.** These belong in the QA phase, not UAT:
- ✗ Run a test suite or individual test (xcodebuild test, pytest, bats, jest, etc.)
- ✗ Run a CLI command and check its exit code or output
- ✗ Execute a script and verify it passes
- ✗ Run a linter, type-checker, or build command

If a plan only contains backend/test/script changes with no user-facing behavior, generate a scenario that asks the human to verify the *effect* is visible (e.g., "confirm the migration preview no longer shows phantom entries") rather than asking them to run the tests themselves.

**What belongs in UAT (ask the user):**
- Visual/UI correctness ("Does the migration preview show the correct symbols?")
- Domain-specific data validation ("Does the reconciliation output match your expected portfolio?")
- UX flows and usability ("Navigate to Settings > Import, does the flow feel right?")
- Behavior that requires the running app or hardware ("Open the app on your device, tap X, verify Y")
- Subjective quality ("Does the chart render clearly at different screen sizes?")

**What does NOT belong in UAT (the agent or QA already handles these):**
- Running test suites — QA runs these during execution. Do NOT ask the user to run tests.
- Checking command output, exit codes, or build success
- Grepping files for expected content
- Verifying file existence or structure
- Any check that can be performed programmatically via Bash, Grep, or Glob

**Skill-aware exclusion:** If any active skill, tool, or MCP server gives the model UI automation capabilities (e.g., describe-UI, tap/click simulation, accessibility inspection, screenshot capture, DOM querying), then UI interactions that can be verified programmatically via those capabilities also belong in QA, not UAT. Only include scenarios that require true human judgment — subjective quality, visual design assessment, domain-specific data correctness, or hardware-dependent behavior that available tooling cannot automate.

If a plan's work is purely internal (refactor, test infrastructure, script changes) with no user-facing behavior, generate a single lightweight checkpoint asking the user to confirm the app still works as expected from their perspective, rather than asking them to run automated checks.

Write the initial UAT file at `{phase-dir}/{uat_path}` (using the pre-computed `uat_path` from Step 1) using the `templates/UAT.md` format. If the parent directory doesn't exist (e.g., `remediation/uat/round-01/`), create it first.
- Populate YAML frontmatter: phase, plan_count, status=in_progress, started=today, total_tests
- Write all test entries with Result fields empty (no placeholder values)

**Result field values (NON-NEGOTIABLE):** The `**Result:**` field in each test entry MUST be exactly one of three lowercase values: `pass`, `skip`, or `issue`. Never write `FAIL`, `PARTIAL`, `PASS`, `PASSED`, or any other value — downstream scripts depend on this exact vocabulary to extract issues and compute status.

### 5. CHECKPOINT loop (one test at a time — conversational, blocking)

**This is a conversational loop. Present ONE test, then STOP and wait for the user to respond. Do NOT present multiple tests at once. Do NOT skip ahead. Do NOT end the session after presenting a test.**

> **CRITICAL BOUNDARY:** The UAT interviewer MUST NOT investigate, debug, or implement fixes during the UAT session — regardless of user tone, urgency, or explicit requests to fix issues. The interviewer's ONLY job is to record responses and advance to the next checkpoint. All user frustration, bug descriptions, and fix requests are recorded as issue text in the UAT report. Fixes happen in the remediation phase AFTER the UAT session is complete. If the user explicitly asks you to stop the UAT and fix something, respond: "Issue recorded. Let's finish the remaining checkpoints first — remediation will address this immediately after."

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md for all output formatting (symbols, bars, AskUserQuestion spacing).

For the FIRST test without a result, display a CHECKPOINT followed by AskUserQuestion:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CHECKPOINT {NN}/{total} — {plan-id}: {plan-title}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{scenario description}
```

Then call the `AskUserQuestion` tool (this MUST be a tool_use call, NOT text output):

```yaml
question: "Expected: {expected result}"
header: "UAT"
multiSelect: false
options:
  - label: "Pass"
    description: "Behavior matches expected result"
  - label: "Skip"
    description: "Cannot test right now — skip this checkpoint"
```

The tool automatically provides a freeform "Other" option for the user to describe issues.

**AskUserQuestion is a tool call (NON-NEGOTIABLE):** You MUST invoke AskUserQuestion via the tool_use mechanism — never emit the question parameters as text, JSON, or any other inline format in your response body. If AskUserQuestion appears in your text output instead of as a tool call, the checkpoint will not be presented to the user and the session will end prematurely.

**STOP HERE.** Wait for the AskUserQuestion response. Do NOT continue to the next test, do NOT skip to Step 6, and do NOT end the turn. The tool call blocks until the user responds.

**After the user responds:** process the response (Step 6), persist to disk (Step 8), then present the NEXT test using the same CHECKPOINT + AskUserQuestion format. **STOP and wait again.** Repeat until all tests are done, then go to Step 9.

### 6. Response mapping

Map the AskUserQuestion response:

**"Pass" selected:** Record as passed. **However**, if the user's response also mentions a separate bug/issue (e.g., "Pass, but I noticed X is broken"), record the test as passed AND capture the separate observation as a discovered issue (see Step 6a).

**"Skip" selected:** Record as skipped. **However**, if the user selected "Skip" but also typed additional text describing a bug/issue (e.g., the response body contains "but the sidebar is broken" alongside the Skip selection), record the test as skipped AND capture the additional text as a discovered issue (see Step 6a). The additional text is the response content beyond the option selection itself.

**Freeform text (via "Other"):** Apply case-insensitive matching in this order after normalization.

**Normalization (required first):**
- Trim surrounding whitespace.
- Lowercase.
- Treat curly apostrophes as straight apostrophes (`can’t` == `can't`).
- Treat em/en dashes as dash separators.

**Word-boundary rule:** Match intent keywords as whole words only — a keyword matches when it is surrounded by whitespace, punctuation, or string boundaries (equivalent to regex `\b`). Examples: "pass" matches in "pass, but..." and "Pass." but NOT in "passport"; "works" matches in "it works" but NOT in "worksmanship"; "good" matches in "looks good" but NOT in "goodness".

**Idiomatic-positive exceptions:** These should count as pass-intent (not issues): `not bad`, `can't complain`, `cant complain`, `cannot complain`.

**Uncertainty exclusion (NON-NEGOTIABLE):** Hedging/uncertainty phrases are NOT pass-intent — they indicate the user is unsure and needs investigation, not rubber-stamping. If the response contains any of these phrases WITHOUT a clear pass-intent keyword (pass, passed, looks good, works, correct, confirmed, yes, good, fine, ok, okay), fall through to "anything else" → issue. Uncertainty phrases: `I think`, `I think so`, `I guess`, `maybe`, `not sure`, `possibly`, `I believe so`, `probably`, `hard to tell`, `I suppose`. Examples: "I think so? ORCX still shows cost basis" → issue (no pass keyword, uncertainty + observation); "pass, I think it works" → passed (explicit pass keyword present). When uncertainty is present, the agent MUST investigate before recording — never assume the user means pass.

**Negation guard (expanded scope):** Before classifying as pass-intent, detect negation in the same clause even when not immediately adjacent. If a negation term appears up to a few words before pass-intent (or in patterns like "I don't think it works"), treat as issue (Step 6), unless the text matches an idiomatic-positive exception above. Negation terms: not, don't, doesn't, didn't, isn't, wasn't, no, never, neither, nor, hardly, barely, cannot, can't, won't, wouldn't, shouldn't. Examples: "not good, still broken" → issue; "I don't think it works" → issue; "it works" → pass.

**Observation extraction guard:** Only create a discovered issue when text after a separator includes a defect/issue signal (e.g., broken, bug, error, wrong, missing, not working, fails, crash, exception, regression, problem, still). The word "still" is a defect signal because in UAT context it means an expected fix was not applied (e.g., "X still shows Y" = the behavior persists unchanged = issue). **Exception:** "still" followed by a positive word (works, working, fine, good, correct, properly, functioning, responsive, loads, launches, runs, ok, okay, passes, functions, operates, running) is temporal (meaning "continues to work"), NOT a defect signal — do NOT create a discovered issue. Examples: "pass, it still works fine" → pass (no discovered issue); "pass, but it still shows the old value" → pass + discovered issue. If trailing text is neutral/positive only (e.g., "pass: looks great"), do NOT create a discovered issue.

**Dual-intent tie-break (pass + skip in one response):**
- If the response explicitly defers the **current checkpoint** (e.g., "skip this checkpoint", "skip for now", "can't test right now"), classify checkpoint outcome as **skip**.
- Otherwise, use the first intent word left-to-right as fallback.

Evaluate in this order:
- **Skip-intent with issue observation:** If the text contains a skip-intent whole word (skip, skipped, next, n/a, na, later, defer) AND contains post-separator text with an issue signal, then: record the test as **skipped** AND capture the post-separator observation text as a discovered issue (Step 6a). Separators: but, however, also, although, though, comma, semicolon, period, dash, colon, em dash, newline. Example: "skip, but the sidebar is completely broken" → skipped + discovered issue.
- **Skip-intent only:** If skip-intent is present but no issue observation in post-separator text → record as skipped.
- **Pass-intent with issue observation:** If the text contains pass-intent as whole words/phrases (pass, passed, looks good, works, correct, confirmed, yes, good, fine, ok, okay, not bad, can't complain, cant complain, cannot complain), is not negated by the expanded negation guard, and has post-separator issue text, then: record the test as **passed** AND capture the post-separator observation text as a discovered issue (Step 6a). Example: "pass, but I noticed the stats section still shows for positions with no covered calls" → passed + discovered issue.
- **Pass-intent only:** Pass-intent present, not negated, and no issue observation in post-separator text → record as passed.
- **Anything else:** treat the entire response text as an issue description (Step 6).

### 7. Issue handling (when response = issue)

The user's response text IS the issue description. Infer severity from keywords (never ask the user):

| Keywords | Severity |
| --- | --- |
| crash, broken, error, doesn't work, fails, exception | critical |
| wrong, incorrect, missing, not working, bug | major |
| minor, cosmetic, nitpick, small, typo, polish | minor |
| (no keyword match) | major |

Record: description, inferred severity.

Display:
```text
Issue recorded (severity: {level}). Final next-step routing shown at UAT summary.
```

### 7a. Discovered issue handling (observations during passing/skipping tests)

When a user passes or skips a test but also mentions a separate bug, issue, or observation unrelated to the test's expected behavior, capture it as a **discovered issue**.

Assign a discovered-issue ID: `D{NN}` (D01, D02, ...) — sequential across the UAT session. **On resumed sessions:** scan existing `D{NN}` entries in the UAT.md to find the highest existing number, then continue from max+1 (e.g., if D01 and D02 exist, the next discovered issue is D03).

Infer severity using the same keyword table from Step 6. Infer category from context:
- If the user identifies a specific view/screen/component: use that as the description prefix
- If vague: use the verbatim observation

Append a new test entry to the UAT.md `## Tests` section:

```markdown
### D{NN}: {short-title}

- **Plan:** (discovered during {test-id})
- **Scenario:** User observation during UAT
- **Expected:** (not applicable — discovered issue)
- **Result:** issue
- **Issue:**
  - Description: {observation text}
  - Severity: {inferred severity}
```

Increment `total_tests` and `issues` in frontmatter. This ensures discovered issues flow into UAT remediation alongside test failures.

Display:
```text
Discovered issue D{NN} recorded (severity: {level}).
```

### 8. After each response: persist immediately

- Update the UAT file at `{phase-dir}/{uat_path}` with the result for this test. The `**Result:**` value MUST be exactly `pass`, `skip`, or `issue` (lowercase). Map user responses: Pass→`pass`, Skip→`skip`, any issue/fail/problem→`issue`. Never write FAIL, PARTIAL, or any other value.
- Write the file to disk (survives /clear)
- Display progress: `✓ {completed}/{total} tests`

### 9. Session complete

- **Finalize UAT status (script-based — NON-NEGOTIABLE):** Run the finalize script to deterministically compute and update frontmatter status, counts, and completed date:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/finalize-uat-status.sh "{phase-dir}/{uat_path}"
  ```
  If the script fails or reports unrecognized `**Result:**` values, STOP and surface the error. Do NOT patch the UAT frontmatter manually. The script reads all `**Result:**` lines, counts pass/skip/issue, and updates the YAML frontmatter (`status`, `completed`, `passed`, `skipped`, `issues`, `total_tests`). Its output (`status={status} passed={N} ...`) provides the values for the summary display below. Do NOT manually update frontmatter fields — the script is the source of truth.
- Display summary:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase {NN}: {name} — UAT Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Result:   {✓ PASS | ✗ ISSUES FOUND}
  Passed:   {N}
  Skipped:  {N}
  Issues:   {N}

  Report:   {path to UAT.md}
```

**Discovered Issues in summary:** If any discovered issues (`D{NN}` entries) were recorded during the session, list them after the result box so the user sees them at a glance:
```text
  Discovered Issues:
    ⚠ D01: {short-title} (severity: {level})
    ⚠ D02: {short-title} (severity: {level})
```
These are already recorded in the UAT.md and will flow into remediation alongside test failures. If no discovered issues: omit the section.

**Remediation lifecycle advance (ONLY when `verify_scope=remediation` — skip entirely for first-time UAT):**
First, verify that UAT remediation state actually exists before running any lifecycle commands. If no state file exists (neither new-format nor legacy location), this is a first-time UAT — do NOT call `needs-round` or any remediation state command:
```bash
_uat_state_file="{phase-dir}/remediation/uat/.uat-remediation-stage"
_uat_legacy_remed_file="{phase-dir}/remediation/.uat-remediation-stage"
_uat_legacy_file="{phase-dir}/.uat-remediation-stage"
_uat_state_exists=false
{ [ -f "$_uat_state_file" ] || [ -f "$_uat_legacy_remed_file" ] || [ -f "$_uat_legacy_file" ]; } && _uat_state_exists=true
```
**If `_uat_state_exists=false`:** Skip this entire block — this is a first-time UAT, not a re-verification after remediation.
**If `_uat_state_exists=true` AND `verify_scope=remediation`:**
- If `status=issues_found`: Advance to the next remediation round:
  ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh needs-round "{phase-dir}"
  ```
  This increments the round counter, creates the next round directory, and resets stage to `research`.
- If `status=complete`: Remediation verified successfully. Mark remediation as verified (do NOT delete the state file — `current_uat()` needs it to locate the round-dir UAT):
  ```bash
  # Mark remediation as verified — preserves round/layout so current_uat() can still find the active round-scoped UAT
  _state_file="{phase-dir}/remediation/uat/.uat-remediation-stage"
  _legacy_remed_file="{phase-dir}/remediation/.uat-remediation-stage"
  _legacy_phase_file="{phase-dir}/.uat-remediation-stage"
  _write_state_file=""
  if [ -f "$_state_file" ]; then
    _write_state_file="$_state_file"
  elif [ -f "$_legacy_remed_file" ]; then
    _write_state_file="$_legacy_remed_file"
  elif [ -f "$_legacy_phase_file" ]; then
    _write_state_file="$_legacy_phase_file"
  fi
  if [ -n "$_write_state_file" ]; then
    _cur_round=$(grep '^round=' "$_write_state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    _cur_layout=$(grep '^layout=' "$_write_state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    case "$_write_state_file" in
      */remediation/.uat-remediation-stage|*/.uat-remediation-stage)
        _cur_round="${_cur_round:-01}"
        _cur_layout="${_cur_layout:-legacy}"
        ;;
      *)
        _cur_round="${_cur_round:-01}"
        _cur_layout="${_cur_layout:-round-dir}"
        ;;
    esac
    printf 'stage=verified\nround=%s\nlayout=%s\n' "$_cur_round" "$_cur_layout" > "$_write_state_file"
  fi
  ```

- If issues found:
  - Any issue severity is `critical` or `major`:
    - `Suggest /vbw:vibe to continue UAT remediation directly from {uat_path}`
  - All issues are `minor`:
    - `Suggest /vbw:fix to address recorded issues.`

**Planning artifact boundary commit (conditional):**
```bash
PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" commit-boundary "verify phase {NN}" .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable; skipping planning git boundary commit" >&2
fi
```
- `planning_tracking=commit`: commits `.vbw-planning/` + `CLAUDE.md` when changed (includes UAT report)
- `planning_tracking=manual|ignore`: no-op
- `auto_push=always`: push happens inside the boundary commit command when upstream exists

Run `bash "$(echo /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default})/scripts/suggest-next.sh" verify {result} {phase}` and display.
