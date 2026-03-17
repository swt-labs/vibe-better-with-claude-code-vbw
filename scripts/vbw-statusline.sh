#!/bin/bash
# VBW Status Line — 4-line dashboard (L1: project, L2: context, L3: usage+cache, L4: model/cost)
# Cache: {prefix}-fast (5s), {prefix}-slow (60s), {prefix}-cost (per-render), {prefix}-ok (permanent)

# Read stdin with timeout — CC may not pipe data on the first dsR() invocation
# (no cost/model info yet), and bare `cat` would block until the 5s dsR timeout
# kills us. Use a read loop: 1s timeout per line handles multi-line JSON while
# bailing fast when CC sends nothing. Total budget: ~2s for read + ~1s for render
# = 3s well within dsR's 5s timeout.
input=""
while IFS= read -t 1 -r _line; do
  input="${input}${_line}"
done 2>/dev/null
# Capture trailing data after last newline (if no final \n)
[ -n "${_line:-}" ] && input="${input}${_line}"
# Replace stdin with /dev/null — prevents downstream commands (jq, curl, etc.)
# from inheriting a hung pipe and blocking indefinitely.
exec 0</dev/null

# Colors
C='\033[36m' G='\033[32m' Y='\033[33m' R='\033[31m'
D='\033[2m' B='\033[1m' X='\033[0m'

# --- Cached platform info ---
_UID=$(id -u)
_OS=$(uname)
_VER=$(cat "$(dirname "$0")/../VERSION" 2>/dev/null | tr -d '[:space:]')
_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
if command -v md5sum &>/dev/null; then
  _REPO_HASH=$(echo "$_REPO_ROOT" | md5sum | cut -c1-8)
elif command -v md5 &>/dev/null; then
  _REPO_HASH=$(echo "$_REPO_ROOT" | md5 -q | cut -c1-8)
else
  _REPO_HASH=$(printf '%s' "$_REPO_ROOT" | cksum | cut -d' ' -f1)
fi
_CACHE="/tmp/vbw-${_VER:-0}-${_UID}-${_REPO_HASH}"

# Clean stale caches from previous versions on first run
if ! [ -f "${_CACHE}-ok" ] || ! [ -O "${_CACHE}-ok" ]; then
  rm -f /tmp/vbw-*-"${_UID}"-* /tmp/vbw-sl-cache-"${_UID}" /tmp/vbw-usage-cache-"${_UID}" /tmp/vbw-gh-cache-"${_UID}" /tmp/vbw-team-cache-"${_UID}" /tmp/vbw-*-"${_UID}" 2>/dev/null
  touch "${_CACHE}-ok"
fi

# --- Helpers ---

# Source shared summary-status helpers for status-aware SUMMARY detection
_SL_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$_SL_SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$_SL_SCRIPT_DIR/summary-utils.sh"
else
  # Safe default: report zero completions when helpers unavailable
  count_complete_summaries() { echo "0"; }
  count_done_summaries() { echo "0"; }
fi

cache_fresh() {
  local cf="$1" ttl="$2"
  [ ! -f "$cf" ] && return 1
  [ ! -O "$cf" ] && rm -f "$cf" 2>/dev/null && return 1
  local mt
  if [ "$_OS" = "Darwin" ]; then
    mt=$(stat -f %m "$cf" 2>/dev/null || echo 0)
  else
    mt=$(stat -c %Y "$cf" 2>/dev/null || echo 0)
  fi
  [ $((NOW - mt)) -le "$ttl" ]
}

# Resolve CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC from env var or settings.json.
# Sets _NOTRAFFIC_ACTIVE=1 if the flag is truthy, empty otherwise.
_resolve_notraffic() {
  _NOTRAFFIC_ACTIVE=""
  local _val="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
  if [ -z "$_val" ]; then
    local _sdir
    for _sdir in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do
      [ -z "$_sdir" ] && continue
      [ -f "$_sdir/settings.json" ] || continue
      _val=$(jq -r '.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC // ""' "$_sdir/settings.json" 2>/dev/null)
      [ -n "$_val" ] && break
    done
  fi
  case "$_val" in
    1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) _NOTRAFFIC_ACTIVE=1 ;;
  esac
}

progress_bar() {
  local pct="$1" width="$2"
  local filled=$((pct * width / 100))
  [ "$filled" -gt "$width" ] && filled="$width"
  [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  local empty=$((width - filled))
  local color
  if [ "$pct" -ge 80 ]; then color="$R"
  elif [ "$pct" -ge 50 ]; then color="$Y"
  else color="$G"
  fi
  local bar=""
  [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | sed 's/ /█/g')
  [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | sed 's/ /░/g')"
  printf '%b%s%b' "$color" "$bar" "$X"
}

fmt_tok() {
  local v=$1
  if [ "$v" -ge 1000000 ]; then
    local d=$((v / 1000000)) r=$(( (v % 1000000 + 50000) / 100000 ))
    [ "$r" -ge 10 ] && d=$((d + 1)) && r=0
    printf "%d.%dM" "$d" "$r"
  elif [ "$v" -ge 1000 ]; then
    local d=$((v / 1000)) r=$(( (v % 1000 + 50) / 100 ))
    [ "$r" -ge 10 ] && d=$((d + 1)) && r=0
    printf "%d.%dK" "$d" "$r"
  else
    printf "%d" "$v"
  fi
}

fmt_cost() {
  local whole="${1%%.*}" frac="${1#*.}"
  local cents="${frac:0:2}"
  cents=$((10#${cents:-0}))
  whole=$((10#${whole:-0}))
  local total_cents=$(( whole * 100 + cents ))
  if [ "$total_cents" -ge 10000 ]; then printf "\$%d" "$whole"
  elif [ "$total_cents" -ge 1000 ]; then printf "\$%d.%d" "$whole" $((cents / 10))
  else printf "\$%d.%02d" "$whole" "$cents"
  fi
}

fmt_dur() {
  local s=$(($1 / 1000))
  if [ "$s" -ge 3600 ]; then
    printf "%dh %dm" $((s / 3600)) $(( (s % 3600) / 60 ))
  elif [ "$s" -ge 60 ]; then
    printf "%dm %ds" $((s / 60)) $((s % 60))
  else
    printf "%ds" "$s"
  fi
}

IFS='|' read -r PCT REM IN_TOK OUT_TOK CACHE_W CACHE_R CTX_SIZE \
               COST DUR_MS API_MS ADDED REMOVED MODEL VER <<< \
  "$(echo "$input" | jq -r '[
    (.context_window.used_percentage // 0 | floor),
    (.context_window.remaining_percentage // 100 | floor),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.output_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.context_window_size // 200000),
    (.cost.total_cost_usd // 0),
    (.cost.total_duration_ms // 0),
    (.cost.total_api_duration_ms // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.model.display_name // "Claude"),
    (.version // "?")
  ] | join("|")' 2>/dev/null)"

PCT=${PCT:-0}; REM=${REM:-100}; IN_TOK=${IN_TOK:-0}; OUT_TOK=${OUT_TOK:-0}
CACHE_W=${CACHE_W:-0}; CACHE_R=${CACHE_R:-0}; COST=${COST:-0}
DUR_MS=${DUR_MS:-0}; API_MS=${API_MS:-0}; ADDED=${ADDED:-0}; REMOVED=${REMOVED:-0}
MODEL=${MODEL:-Claude}; VER=${VER:-?}

# --- Autocompact buffer normalization (#237) ---
# Claude Code reserves context for autocompact that's never usable. Raw percentages
# make users think they have more headroom than they do. Normalize so 100% = trigger.
#
# Algorithm (reverse-engineered from cli.js v2.1.76):
#   effective_window = context_window - min(max_output_tokens, 20000)
#   default_trigger  = effective_window - 13000
#   override_trigger = floor(effective_window * pct / 100)   [if override set]
#   trigger          = min(override_trigger, default_trigger)
#   buffer           = context_window - trigger
#
# Constants: OUTPUT_TOKEN_CAP=20000, HEADROOM=13000
# Results:   200K → buffer=33K (16.5%), 1M → buffer=33K (3.3%)
#            1M + override=95 → buffer=69K (6.9%)
#
# Also respects:
#   CLAUDE_CODE_AUTO_COMPACT_WINDOW — caps context window for compact math
#   CLAUDE_CODE_MAX_OUTPUT_TOKENS   — min(value, 20000) for output deduction
# Notes:
#   - Override decimals (e.g., 95.5) handled via fixed-point x10 math.
#   - Output token deduction defaults to 20K (correct for Claude 4 family).
#     Older models (3.5 Sonnet=8K, Claude 3=4K) use smaller deductions internally,
#     making our buffer estimate ~12K too large (pessimistic/safe direction).
#     Users on older models can set CLAUDE_CODE_MAX_OUTPUT_TOKENS for accuracy.

_AC_DISABLED=""
_AC_OVERRIDE=""
_AC_WINDOW_CAP=""
_AC_MAX_OUTPUT=""

# Resolve env vars: real env > settings.json env block (single jq call for all 4)
# Note: first settings.json with any env value wins — values are NOT merged across files.
# This matches the credential lookup pattern elsewhere in this script.
_AC_SETTINGS_ENV=""
for _sdir in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do
  [ -z "$_sdir" ] && continue
  [ -f "$_sdir/settings.json" ] || continue
  _AC_SETTINGS_ENV=$(jq -r '[
    .env.DISABLE_AUTO_COMPACT // "",
    .env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE // "",
    .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // "",
    .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS // ""
  ] | join("|")' "$_sdir/settings.json" 2>/dev/null)
  # Only break if at least one value was found (jq returns "|||" for empty .env)
  [ -n "$_AC_SETTINGS_ENV" ] && [ "$_AC_SETTINGS_ENV" != "|||" ] && break
done
IFS='|' read -r _S_DISABLED _S_OVERRIDE _S_WINDOW _S_OUTPUT <<< "$_AC_SETTINGS_ENV"

# Real env vars take priority over settings.json
_AC_DISABLED="${DISABLE_AUTO_COMPACT:-$_S_DISABLED}"
_AC_OVERRIDE="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-$_S_OVERRIDE}"
_AC_WINDOW_CAP="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-$_S_WINDOW}"
_AC_MAX_OUTPUT="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-$_S_OUTPUT}"

# Match Claude Code's truthiness check: "1", "true", "yes", "on" all disable
# Uses case-insensitive patterns for bash 3.2 compatibility (macOS default)
_AC_SKIP=false
case "$_AC_DISABLED" in
  1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) _AC_SKIP=true ;;
esac

# Strip leading zeros to prevent bash octal interpretation (e.g., "08000" → "8000")
_ac_dec() { local v="${1#"${1%%[!0]*}"}"; echo "${v:-0}"; }

if [ "$_AC_SKIP" = "false" ] && [ "${CTX_SIZE:-0}" -gt 0 ] 2>/dev/null; then
  # Apply AUTO_COMPACT_WINDOW cap (if set, use the smaller of window and cap)
  _AC_CTX="$CTX_SIZE"
  if [ -n "$_AC_WINDOW_CAP" ]; then
    _WC="$(_ac_dec "${_AC_WINDOW_CAP%%.*}")"
    if [ "$_WC" -gt 0 ] 2>/dev/null && [ "$_WC" -lt "$_AC_CTX" ] 2>/dev/null; then
      _AC_CTX="$_WC"
    fi
  fi

  # Output token deduction: min(max_output_tokens, 20000), default 20000
  _OUT_CAP=20000
  if [ -n "$_AC_MAX_OUTPUT" ]; then
    _MO="$(_ac_dec "${_AC_MAX_OUTPUT%%.*}")"
    if [ "$_MO" -gt 0 ] 2>/dev/null && [ "$_MO" -lt 20000 ] 2>/dev/null; then
      _OUT_CAP="$_MO"
    fi
  fi

  # Effective window after output token reservation
  _EFF=$((_AC_CTX - _OUT_CAP))
  [ "$_EFF" -lt 0 ] && _EFF=0

  # Default trigger: effective - 13K headroom
  _DEF_TRIGGER=$((_EFF - 13000))
  [ "$_DEF_TRIGGER" -lt 0 ] && _DEF_TRIGGER=0

  _TRIGGER="$_DEF_TRIGGER"

  # Override: floor(effective * pct / 100), then min with default
  # Fixed-point x10 to handle decimals like "95.5" without floating point.
  # "95.5" → whole=95 frac=5 → pct_x10=955 → effective * 955 / 1000
  if [ -n "$_AC_OVERRIDE" ]; then
    _OV_WHOLE="$(_ac_dec "${_AC_OVERRIDE%%.*}")"
    _OV_FRAC="0"
    case "$_AC_OVERRIDE" in
      *.*) _OV_FRAC="${_AC_OVERRIDE#*.}"; _OV_FRAC="$(_ac_dec "${_OV_FRAC:0:1}")"; _OV_FRAC="${_OV_FRAC:-0}" ;;
    esac
    # Guard: ensure both parts are numeric
    if [ "$_OV_WHOLE" -ge 0 ] 2>/dev/null && [ "$_OV_FRAC" -ge 0 ] 2>/dev/null; then
      _OV_PCT_X10=$((_OV_WHOLE * 10 + _OV_FRAC))
      if [ "$_OV_PCT_X10" -gt 0 ] && [ "$_OV_PCT_X10" -le 1000 ]; then
        _OV_TRIGGER=$((_EFF * _OV_PCT_X10 / 1000))
        [ "$_OV_TRIGGER" -lt "$_DEF_TRIGGER" ] && _TRIGGER="$_OV_TRIGGER"
      fi
    fi
  fi

  if [ "$_TRIGGER" -gt 0 ]; then
    # Buffer as percentage of RAW window (CTX_SIZE) because REM from Claude Code
    # is also a percentage of the raw window. Both must use the same reference frame.
    # Use CTX_SIZE - _TRIGGER (not _AC_CTX - _TRIGGER) so the buffer spans from
    # the raw window down to the trigger point, regardless of any window cap.
    _BUFFER=$((CTX_SIZE - _TRIGGER))
    _BUF_PCT_X10=$((_BUFFER * 1000 / CTX_SIZE))

    # Normalize remaining: strip buffer zone, rescale to usable range
    # REM is 0-100 integer from Claude Code. Convert to x10 for precision.
    _REM_X10=$((REM * 10))
    [ "$_BUF_PCT_X10" -ge 1000 ] && _BUF_PCT_X10=999  # defensive: prevent division by zero
    _USABLE_REM=$(( (_REM_X10 - _BUF_PCT_X10) * 1000 / (1000 - _BUF_PCT_X10) ))
    [ "$_USABLE_REM" -lt 0 ] && _USABLE_REM=0
    [ "$_USABLE_REM" -gt 1000 ] && _USABLE_REM=1000

    PCT=$(( 100 - (_USABLE_REM + 5) / 10 ))
    [ "$PCT" -lt 0 ] && PCT=0
    [ "$PCT" -gt 100 ] && PCT=100
    REM=$((100 - PCT))
    CTX_SIZE="$_TRIGGER"
  fi
fi

NOW=$(date +%s)

CTX_USED=$((IN_TOK + CACHE_W + CACHE_R))
CTX_USED_FMT=$(fmt_tok "$CTX_USED")
CTX_SIZE_FMT=$(fmt_tok "$CTX_SIZE")

# Cache context usage for pre-flight guard (suggest-compact.sh).
# Include session ID so suggest-compact.sh can detect stale cross-session data (#238).
if [ -d ".vbw-planning" ]; then
  printf '%s\n' "${CLAUDE_SESSION_ID:-unknown}|${PCT}|${CTX_SIZE}" > .vbw-planning/.context-usage 2>/dev/null || true
fi
IN_TOK_FMT=$(fmt_tok "$IN_TOK")
OUT_TOK_FMT=$(fmt_tok "$OUT_TOK")
CACHE_W_FMT=$(fmt_tok "$CACHE_W")
CACHE_R_FMT=$(fmt_tok "$CACHE_R")
DUR_FMT=$(fmt_dur "$DUR_MS")
API_DUR_FMT=$(fmt_dur "$API_MS")
TOTAL_INPUT=$((IN_TOK + CACHE_W + CACHE_R))
CACHE_HIT_PCT=0
[ "$TOTAL_INPUT" -gt 0 ] && CACHE_HIT_PCT=$(( CACHE_R * 100 / TOTAL_INPUT ))
if [ "$CACHE_HIT_PCT" -ge 70 ]; then CACHE_COLOR="$G"
elif [ "$CACHE_HIT_PCT" -ge 40 ]; then CACHE_COLOR="$Y"
else CACHE_COLOR="$R"
fi

# --- Fast cache (5s TTL): VBW state + execution + agents ---
FAST_CF="${_CACHE}-fast"

if ! cache_fresh "$FAST_CF" 5; then
  PH=""; TT=""; EF="balanced"; MP="quality"; BR=""
  PD=0; PT=0; PPD=0; PPT=0; QA="--"; QA_COLOR="D"; GH_URL=""
  PP_LABEL="this phase"; REM_ACTIVE="false"
  if [ -f ".vbw-planning/STATE.md" ]; then
    # Parse "Phase: N of M (slug)" — extract N and M before parenthetical
    # to avoid picking up numbers from phase name slugs like "01-context-diet"
    _phase_line=$(grep -m1 "^Phase:" .vbw-planning/STATE.md 2>/dev/null)
    PH=$(echo "$_phase_line" | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    TT=$(echo "$_phase_line" | sed -n 's/.*[[:space:]]of[[:space:]]*\([0-9][0-9]*\).*/\1/p')
  fi
  if [ -f ".vbw-planning/config.json" ]; then
    # Auto-migrate: add model_profile if missing
    if ! jq -e '.model_profile' .vbw-planning/config.json >/dev/null 2>&1; then
      TMP=$(mktemp)
      jq '. + {model_profile: "quality", model_overrides: {}}' .vbw-planning/config.json > "$TMP" && mv "$TMP" .vbw-planning/config.json
    fi
    EF=$(jq -r '.effort // "balanced"' .vbw-planning/config.json 2>/dev/null)
    MP=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json 2>/dev/null)
    HIDE_AGENT_TMUX=$(jq -r '.statusline_hide_agent_in_tmux // false' .vbw-planning/config.json 2>/dev/null)
    COLLAPSE_AGENT_TMUX=$(jq -r '.statusline_collapse_agent_in_tmux // false' .vbw-planning/config.json 2>/dev/null)
  fi
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BR=$(git branch --show-current 2>/dev/null)
    GH_URL=$(git remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||' | sed 's|https://[^@]*@|https://|')
    GIT_STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    GIT_MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    # shellcheck disable=SC1083
    GIT_AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  fi
  if [ -d ".vbw-planning/phases" ]; then
    PT=$(find .vbw-planning/phases -name '*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
    PD=0
    for _sl_pdir in .vbw-planning/phases/*/; do
      [ -d "$_sl_pdir" ] || continue
      PD=$((PD + $(count_complete_summaries "$_sl_pdir")))
      # Count remediation round summaries (round-dir layout)
      for _sl_rdir in "$_sl_pdir"remediation/round-*/; do
        [ -d "$_sl_rdir" ] || continue
        PD=$((PD + $(count_complete_summaries "$_sl_rdir")))
      done
    done
    if [ -n "$PH" ] && [ "$PH" != "0" ]; then
      PDIR=$(find .vbw-planning/phases -maxdepth 1 -type d -name "$(printf '%02d' "$PH")-*" 2>/dev/null | head -1)
      [ -n "$PDIR" ] && PPD=$(count_complete_summaries "$PDIR")
      [ -n "$PDIR" ] && PPT=$(find "$PDIR" -maxdepth 1 -name '*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')
      # Remediation-aware plan counts: override PPT/PPD with remediation round totals
      if [ -n "$PDIR" ] && [ -f "$PDIR/remediation/.uat-remediation-stage" ]; then
        REM_ACTIVE="true"
        PP_LABEL="this remediation"
        _rem_ppt=0; _rem_ppd=0
        for _rem_rdir in "$PDIR"/remediation/round-*/; do
          [ -d "$_rem_rdir" ] || continue
          _rem_ppt=$((_rem_ppt + $(find "$_rem_rdir" -maxdepth 1 -name '*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')))
          _rem_ppd=$((_rem_ppd + $(count_complete_summaries "$_rem_rdir")))
        done
        PPT="$_rem_ppt"
        PPD="$_rem_ppd"
      elif [ -n "$PDIR" ] && [ -f "$PDIR/.uat-remediation-stage" ]; then
        REM_ACTIVE="true"
        PP_LABEL="this remediation"
      fi
      # Lifecycle-aware QA/UAT indicator: UAT supersedes VERIFICATION.md
      if [ -n "$PDIR" ]; then
        _uat_file=$(find "$PDIR" -maxdepth 1 -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' ! -name '*-UAT-round-*' 2>/dev/null | head -1)
        # Round-dir fallback: check remediation/round-*/R*-UAT.md
        if [ -z "$_uat_file" ]; then
          _uat_file=$(find "$PDIR/remediation" -path '*/round-*/R*-UAT.md' 2>/dev/null | sort -t/ -k2 -V | tail -1)
        fi
        if [ -n "$_uat_file" ]; then
          _uat_status=$(awk 'NR==1 && /^---/{f=1;next} f && /^---/{exit} f && /^status:/{gsub(/^status:[[:space:]]*/,""); print; exit}' "$_uat_file" 2>/dev/null)
          case "$_uat_status" in
            complete|passed) QA="UAT: pass"; QA_COLOR="G" ;;
            issues_found)
              _rem_stage="none"
              if [ -f "$PDIR/remediation/.uat-remediation-stage" ]; then
                _rem_stage=$(grep '^stage=' "$PDIR/remediation/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
                _rem_stage="${_rem_stage:-none}"
              elif [ -f "$PDIR/.uat-remediation-stage" ]; then
                _rem_stage=$(tr -d '[:space:]' < "$PDIR/.uat-remediation-stage")
              fi
              case "$_rem_stage" in
                none)         QA="UAT: Issues";       QA_COLOR="R" ;;
                research)     QA="UAT: Researching";  QA_COLOR="Y" ;;
                plan)         QA="UAT: Planning";     QA_COLOR="Y" ;;
                execute|fix)  QA="UAT: Fixing";       QA_COLOR="Y" ;;
                done|verify)  QA="UAT: Verification"; QA_COLOR="Y" ;;
                *)            QA="UAT: Fixing";       QA_COLOR="Y" ;;
              esac ;;
            *) QA="UAT: ?"; QA_COLOR="Y" ;;
          esac
        elif [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ]; then
          QA="QA: pass"; QA_COLOR="G"
        fi
      fi
    fi
  fi

  EXEC_STATUS=""; EXEC_WAVE=0; EXEC_TWAVES=0; EXEC_DONE=0; EXEC_TOTAL=0; EXEC_CURRENT=""
  if [ -f ".vbw-planning/.execution-state.json" ]; then
    IFS='|' read -r EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT <<< \
      "$(jq -r '[
        (.status // ""),
        (.wave // 0),
        (.total_waves // 0),
        ([.plans[] | select(.status == "complete" or .status == "partial")] | length),
        (.plans | length),
        ([.plans[] | select(.status == "running")][0].title // "")
      ] | join("|")' .vbw-planning/.execution-state.json 2>/dev/null)"
    # Reconcile EXEC_DONE against actual SUMMARY.md files on disk.
    # After a reset/undo, .execution-state.json retains stale "complete"
    # statuses but SUMMARY.md files may no longer exist.
    if [ "$EXEC_STATUS" = "running" ] && [ "${EXEC_DONE:-0}" -gt 0 ] 2>/dev/null; then
      _exec_phase=$(jq -r '.phase // ""' .vbw-planning/.execution-state.json 2>/dev/null)
      if [ -n "$_exec_phase" ]; then
        _exec_pdir=$(find .vbw-planning/phases -maxdepth 1 -type d -name "$(printf '%02d' "$_exec_phase")-*" 2>/dev/null | head -1)
        if [ -n "$_exec_pdir" ] && [ -d "$_exec_pdir" ]; then
          _actual_done=$(count_done_summaries "$_exec_pdir")
          if [ "${_actual_done:-0}" -lt "${EXEC_DONE:-0}" ] 2>/dev/null; then
            EXEC_DONE="$_actual_done"
          fi
        fi
      fi
    fi
  fi

  AGENT_DATA="0"

  # Sanitize pipe characters in EXEC_CURRENT (user-defined plan title) to
  # prevent field misalignment in the pipe-delimited fast cache.
  _EXEC_CURRENT_SAFE="${EXEC_CURRENT//|/-}"

  printf '%s\n' "${PH:-0}|${TT:-0}|${EF}|${MP}|${BR}|${PD}|${PT}|${PPD}|${QA}|${GH_URL}|${GIT_STAGED:-0}|${GIT_MODIFIED:-0}|${GIT_AHEAD:-0}|${EXEC_STATUS:-}|${EXEC_WAVE:-0}|${EXEC_TWAVES:-0}|${EXEC_DONE:-0}|${EXEC_TOTAL:-0}|${_EXEC_CURRENT_SAFE:-}|${AGENT_DATA:-0}|${PPT:-0}|${QA_COLOR:-D}|${HIDE_AGENT_TMUX:-false}|${COLLAPSE_AGENT_TMUX:-false}|${PP_LABEL:-this phase}|${REM_ACTIVE:-false}" > "$FAST_CF" 2>/dev/null
fi

if [ -O "$FAST_CF" ]; then
  # shellcheck disable=SC2034
  IFS='|' read -r PH TT EF MP BR PD PT PPD QA GH_URL GIT_STAGED GIT_MODIFIED GIT_AHEAD \
                  EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT \
                  AGENT_N PPT QA_COLOR HIDE_AGENT_TMUX COLLAPSE_AGENT_TMUX \
                  PP_LABEL REM_ACTIVE < "$FAST_CF"
  # Defaults for caches written by older statusline versions
  PP_LABEL="${PP_LABEL:-this phase}"
  REM_ACTIVE="${REM_ACTIVE:-false}"
fi

# Badge color: live check (not cached) so transitions are immediate.
# [ -f ] is a single stat() syscall — negligible cost vs cache TTL staleness.
VBW_CTX=0; [ -f ".vbw-planning/.vbw-context" ] && VBW_CTX=1
if [ "$VBW_CTX" = "1" ]; then
  VC="${C}${B}"
else
  VC="${D}"
fi

AGENT_LINE=""

# --- Early collapse exit: skip slow cache for collapsed worktree panes ---
# In collapsed worktrees, the output only uses input-parsed values (MODEL, PCT,
# CTX_USED_FMT, etc.), so we can skip OAuth/API/cost/update work entirely.
if [ -n "${TMUX:-}" ]; then
  _GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
  _GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$_GIT_DIR" ] && [ -n "$_GIT_COMMON" ] && [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
    _MAIN_ROOT=$(dirname "$_GIT_COMMON")
    _COLLAPSE_WT=$(jq -r '.statusline_collapse_agent_in_tmux // false' \
      "$_MAIN_ROOT/.vbw-planning/config.json" 2>/dev/null)
    if [ "$_COLLAPSE_WT" = "true" ]; then
      [ "$PCT" -ge 90 ] && BC="$R" || { [ "$PCT" -ge 70 ] && BC="$Y" || BC="$G"; }
      printf '%b\n' "Model: ${D}${MODEL}${X} ${D}│${X} Context: ${BC}${PCT}%${X} ${CTX_USED_FMT}/${CTX_SIZE_FMT} ${D}│${X} Tokens: ${IN_TOK_FMT}"
      exit 0
    fi
  fi
fi

# --- Slow cache (60s TTL, 300s on persistent failure): usage limits + update check ---
SLOW_CF="${_CACHE}-slow"

# Backoff: use 300s TTL when previous fetch failed or was rate-limited (#249)
_SLOW_TTL=60
if [ -O "$SLOW_CF" ]; then
  _PREV_STATUS=$(awk -F'|' '{print $10}' "$SLOW_CF" 2>/dev/null)
  [ "$_PREV_STATUS" = "fail" ] || [ "$_PREV_STATUS" = "ratelimited" ] && _SLOW_TTL=300
fi
# If notraffic flag just became active, skip backoff so it takes effect promptly (#249 QA R3/R4)
if [ "$_SLOW_TTL" -gt 60 ] 2>/dev/null; then
  _resolve_notraffic
  [ -n "$_NOTRAFFIC_ACTIVE" ] && _SLOW_TTL=60
fi

if ! cache_fresh "$SLOW_CF" "$_SLOW_TTL"; then
  FIVE_PCT=0; FIVE_EPOCH=0; WEEK_PCT=0; WEEK_EPOCH=0; SONNET_PCT=-1
  EXTRA_ENABLED=0; EXTRA_PCT=-1; EXTRA_USED_C=0; EXTRA_LIMIT_C=0; FETCH_OK="noauth"
  OAUTH_TOKEN=""
  AUTH_METHOD=""
  HIDE_LIMITS=$(jq -r '.statusline_hide_limits // false' .vbw-planning/config.json 2>/dev/null)
  HIDE_LIMITS_API=$(jq -r '.statusline_hide_limits_for_api_key // false' .vbw-planning/config.json 2>/dev/null)

  # Respect CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC — skip ALL outbound requests (#249)
  _resolve_notraffic
  [ -n "$_NOTRAFFIC_ACTIVE" ] && FETCH_OK="notraffic"

  if [ "$FETCH_OK" = "notraffic" ]; then
    : # skip token lookup, usage fetch, and version check entirely
  else

  # Priority 1: env var override (escape hatch for keychain issues)
  if [ -n "${VBW_OAUTH_TOKEN:-}" ]; then
    OAUTH_TOKEN="$VBW_OAUTH_TOKEN"
  fi

  # Priority 2: system credential store (skip if VBW_SKIP_KEYCHAIN=1, e.g. in tests)
  if [ -z "$OAUTH_TOKEN" ] && [ "${VBW_SKIP_KEYCHAIN:-0}" != "1" ]; then
    if [ "$_OS" = "Darwin" ]; then
      CRED_JSON=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
      if [ -n "$CRED_JSON" ]; then
        OAUTH_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      fi
    else
      # Linux: try secret-tool (GNOME Keyring) then pass (password-store)
      if command -v secret-tool &>/dev/null; then
        CRED_JSON=$(secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$CRED_JSON" ]; then
          OAUTH_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        fi
      elif command -v pass &>/dev/null; then
        CRED_JSON=$(pass show "claude-code/credentials" 2>/dev/null)
        if [ -n "$CRED_JSON" ]; then
          OAUTH_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        fi
      fi
    fi
  fi

  # Priority 3: credentials file (check both with and without leading dot,
  # across all common Claude config locations)
  # When VBW_SKIP_KEYCHAIN=1 (e.g. in tests), only check the explicitly-set
  # CLAUDE_CONFIG_DIR — skip hardcoded fallback paths that may hold real credentials.
  if [ -z "$OAUTH_TOKEN" ]; then
    if [ "${VBW_SKIP_KEYCHAIN:-0}" = "1" ]; then
      _p3_dirs=("${CLAUDE_CONFIG_DIR:-}")
    else
      _p3_dirs=("${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude")
    fi
    for _cdir in "${_p3_dirs[@]}"; do
      [ -z "$_cdir" ] && continue
      for _cred in "$_cdir/.credentials.json" "$_cdir/credentials.json"; do
        if [ -f "$_cred" ]; then
          OAUTH_TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$_cred" 2>/dev/null)
          [ -n "$OAUTH_TOKEN" ] && break 2
        fi
      done
    done
  fi

  # Priority 4: detect auth method via claude CLI (distinguishes OAuth vs API key)
  # Skip if VBW_SKIP_AUTH_CLI=1 (e.g. in tests on dev machines with real auth)
  if [ -z "$OAUTH_TOKEN" ] && [ "${VBW_SKIP_AUTH_CLI:-0}" != "1" ]; then
    AUTH_STATUS=$(CLAUDECODE="" claude auth status --json 2>/dev/null) || AUTH_STATUS=""
    if [ -n "$AUTH_STATUS" ]; then
      AUTH_METHOD=$(echo "$AUTH_STATUS" | jq -r '.authMethod // empty' 2>/dev/null)
    fi
  fi

  if [ -n "$OAUTH_TOKEN" ]; then
    HTTP_CODE=$(curl -s -o /tmp/vbw-usage-body-"${_UID}" -w '%{http_code}' --max-time 3 \
      -H "Authorization: Bearer ${OAUTH_TOKEN}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || HTTP_CODE="000"
    USAGE_RAW=$(cat /tmp/vbw-usage-body-"${_UID}" 2>/dev/null)
    rm -f /tmp/vbw-usage-body-"${_UID}" 2>/dev/null

    if [ -n "$USAGE_RAW" ] && echo "$USAGE_RAW" | jq -e '.five_hour' >/dev/null 2>&1; then
      IFS='|' read -r FIVE_PCT FIVE_EPOCH WEEK_PCT WEEK_EPOCH SONNET_PCT \
                      EXTRA_ENABLED EXTRA_PCT EXTRA_USED_C EXTRA_LIMIT_C <<< \
        "$(echo "$USAGE_RAW" | jq -r '
          def pct: floor;
          def epoch: gsub("\\.[0-9]+"; "") | gsub("Z$"; "+00:00") | split("+")[0] + "Z" | fromdate;
          [
            ((.five_hour.utilization // 0) | pct),
            ((.five_hour.resets_at // "") | if . == "" or . == null then 0 else epoch end),
            ((.seven_day.utilization // 0) | pct),
            ((.seven_day.resets_at // "") | if . == "" or . == null then 0 else epoch end),
            ((.seven_day_sonnet.utilization // -1) | pct),
            (if .extra_usage.is_enabled == true then 1 else 0 end),
            ((.extra_usage.utilization // -1) | pct),
            ((.extra_usage.used_credits // 0) | floor),
            ((.extra_usage.monthly_limit // 0) | floor)
          ] | join("|")
        ' 2>/dev/null)"
      FETCH_OK="ok"
    else
      if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        FETCH_OK="auth"
      elif [ "$HTTP_CODE" = "429" ]; then
        FETCH_OK="ratelimited"
      else
        FETCH_OK="fail"
      fi
    fi
  fi

  UPDATE_AVAIL=""
  REMOTE_VER=$(curl -sf --max-time 3 "https://raw.githubusercontent.com/yidakee/vibe-better-with-claude-code-vbw/main/VERSION" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$REMOTE_VER" ] && [ -n "$_VER" ] && [ "$REMOTE_VER" != "$_VER" ]; then
    NEWEST=$(printf '%s\n%s\n' "$_VER" "$REMOTE_VER" | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)
    [ "$NEWEST" = "$REMOTE_VER" ] && UPDATE_AVAIL="$REMOTE_VER"
  fi

  fi # end: notraffic guard

  printf '%s\n' "${FIVE_PCT:-0}|${FIVE_EPOCH:-0}|${WEEK_PCT:-0}|${WEEK_EPOCH:-0}|${SONNET_PCT:--1}|${EXTRA_ENABLED:-0}|${EXTRA_PCT:--1}|${EXTRA_USED_C:-0}|${EXTRA_LIMIT_C:-0}|${FETCH_OK}|${UPDATE_AVAIL:-}|${AUTH_METHOD:-}|${HIDE_LIMITS:-false}|${HIDE_LIMITS_API:-false}" > "$SLOW_CF" 2>/dev/null
fi

if [ -O "$SLOW_CF" ]; then
  IFS='|' read -r FIVE_PCT FIVE_EPOCH WEEK_PCT WEEK_EPOCH SONNET_PCT \
                  EXTRA_ENABLED EXTRA_PCT EXTRA_USED_C EXTRA_LIMIT_C \
                  FETCH_OK UPDATE_AVAIL AUTH_METHOD HIDE_LIMITS HIDE_LIMITS_API < "$SLOW_CF"
fi

# --- Cost cache: delta attribution per render ---
COST_CF="${_CACHE}-cost"
PREV_COST=""
[ -O "$COST_CF" ] && PREV_COST=$(cat "$COST_CF" 2>/dev/null)
printf '%s\n' "${COST}" > "$COST_CF" 2>/dev/null

LEDGER_FILE=".vbw-planning/.cost-ledger.json"
if [ -n "$PREV_COST" ] && [ -d ".vbw-planning" ]; then
  _to_cents() {
    local val="$1" w f
    w="${val%%.*}"
    if [ "$w" = "$val" ]; then f="00"; else f="${val#*.}"; f="${f}00"; f="${f:0:2}"; fi
    echo $(( 10#${w:-0} * 100 + 10#$f ))
  }
  PREV_CENTS=$(_to_cents "$PREV_COST")
  CURR_CENTS=$(_to_cents "$COST")
  DELTA_CENTS=$((CURR_CENTS - PREV_CENTS))

  if [ "$DELTA_CENTS" -gt 0 ]; then
    ACTIVE_AGENT="other"
    [ -f ".vbw-planning/.active-agent" ] && ACTIVE_AGENT=$(cat .vbw-planning/.active-agent 2>/dev/null)
    [ -z "$ACTIVE_AGENT" ] && ACTIVE_AGENT="other"

    if [ -f "$LEDGER_FILE" ] && jq empty "$LEDGER_FILE" 2>/dev/null; then
      jq --arg agent "$ACTIVE_AGENT" --argjson delta "$DELTA_CENTS" \
        '.[$agent] = ((.[$agent] // 0) + $delta)' "$LEDGER_FILE" > "${LEDGER_FILE}.tmp" 2>/dev/null \
        && mv "${LEDGER_FILE}.tmp" "$LEDGER_FILE"
    else
      printf '{"%s":%d}\n' "$ACTIVE_AGENT" "$DELTA_CENTS" > "$LEDGER_FILE"
    fi
  fi
fi

# --- Usage rendering ---
USAGE_LINE=""
if [ "$FETCH_OK" = "ok" ]; then
  countdown() {
    local epoch="$1"
    if [ "${epoch:-0}" -gt 0 ] 2>/dev/null; then
      local diff=$((epoch - NOW))
      if [ "$diff" -gt 0 ]; then
        if [ "$diff" -ge 86400 ]; then
          local dd=$((diff / 86400)) hh=$(( (diff % 86400) / 3600 ))
          echo "~${dd}d ${hh}h"
        else
          local hh=$((diff / 3600)) mm=$(( (diff % 3600) / 60 ))
          echo "~${hh}h${mm}m"
        fi
      else
        echo "now"
      fi
    fi
  }

  FIVE_REM=$(countdown "$FIVE_EPOCH")
  WEEK_REM=$(countdown "$WEEK_EPOCH")

  USAGE_LINE="Session: $(progress_bar "${FIVE_PCT:-0}" 10) ${FIVE_PCT:-0}%"
  [ -n "$FIVE_REM" ] && USAGE_LINE="$USAGE_LINE $FIVE_REM"
  USAGE_LINE="$USAGE_LINE ${D}│${X} Weekly: $(progress_bar "${WEEK_PCT:-0}" 10) ${WEEK_PCT:-0}%"
  [ -n "$WEEK_REM" ] && USAGE_LINE="$USAGE_LINE $WEEK_REM"
  if [ "${SONNET_PCT:--1}" -ge 0 ] 2>/dev/null; then
    USAGE_LINE="$USAGE_LINE ${D}│${X} Sonnet: $(progress_bar "${SONNET_PCT}" 10) ${SONNET_PCT}%"
  fi
  if [ "${EXTRA_ENABLED:-0}" = "1" ] && [ "${EXTRA_PCT:--1}" -ge 0 ] 2>/dev/null; then
    EXTRA_USED_D="$((EXTRA_USED_C / 100)).$( printf '%02d' $((EXTRA_USED_C % 100)) )"
    EXTRA_LIMIT_D="$((EXTRA_LIMIT_C / 100)).$( printf '%02d' $((EXTRA_LIMIT_C % 100)) )"
    USAGE_LINE="$USAGE_LINE ${D}│${X} Extra: $(progress_bar "${EXTRA_PCT}" 10) ${EXTRA_PCT}% \$${EXTRA_USED_D}/\$${EXTRA_LIMIT_D}"
  fi
elif [ "$FETCH_OK" = "auth" ]; then
  USAGE_LINE="${D}Limits: auth expired (run /login)${X}"
elif [ "$FETCH_OK" = "ratelimited" ]; then
  USAGE_LINE="${D}Limits: rate limited (retry in 5m — re-login if persistent)${X}"
elif [ "$FETCH_OK" = "fail" ]; then
  USAGE_LINE="${D}Limits: fetch failed (retry in 5m)${X}"
elif [ "$FETCH_OK" = "notraffic" ]; then
  USAGE_LINE="${D}Limits: skipped (nonessential traffic disabled)${X}"
elif [ "$AUTH_METHOD" = "claude.ai" ]; then
  USAGE_LINE="${D}Limits: keychain access denied (allow Terminal in Keychain Access.app or set VBW_OAUTH_TOKEN)${X}"
elif [ "$FETCH_OK" = "noauth" ]; then
  USAGE_LINE="${D}Limits: N/A (using API key)${X}"
else
  USAGE_LINE="${D}Limits: unavailable${X}"
fi

# --- Hide-limits suppression ---
if [ "$HIDE_LIMITS" = "true" ]; then
  USAGE_LINE=""
elif [ "$HIDE_LIMITS_API" = "true" ] && [ "$FETCH_OK" = "noauth" ]; then
  USAGE_LINE=""
fi

# --- GitHub link (OSC 8 clickable) ---
GH_LINK=""
REPO_LABEL=""
if [ -n "$GH_URL" ]; then
  GH_NAME=$(basename "$GH_URL")
  REPO_LABEL="$GH_NAME"
  if [ -n "$BR" ]; then
    GH_BRANCH_URL="${GH_URL}/tree/${BR}"
    GH_LINK="\033]8;;${GH_BRANCH_URL}\a${GH_NAME}:${BR}\033]8;;\a"
  else
    GH_LINK="\033]8;;${GH_URL}\a${GH_NAME}\033]8;;\a"
  fi
else
  # No remote — use directory name as repo label
  REPO_LABEL=$(basename "$_REPO_ROOT")
fi

[ "$PCT" -ge 90 ] && BC="$R" || { [ "$PCT" -ge 70 ] && BC="$Y" || BC="$G"; }
FL=$((PCT * 10 / 100)); EM=$((10 - FL))
CTX_BAR=""; [ "$FL" -gt 0 ] && CTX_BAR=$(printf "%${FL}s" | sed 's/ /▓/g')
[ "$EM" -gt 0 ] && CTX_BAR="${CTX_BAR}$(printf "%${EM}s" | sed 's/ /░/g')"

_HIDE_EXEC_TMUX=false
if [ "$HIDE_AGENT_TMUX" = "true" ] && [ -n "${TMUX:-}" ] && [ "$EXEC_STATUS" = "running" ]; then
  _HIDE_EXEC_TMUX=true
fi

if [ "$_HIDE_EXEC_TMUX" != "true" ] && [ "$EXEC_STATUS" = "running" ] && [ "${EXEC_TOTAL:-0}" -gt 0 ] 2>/dev/null; then
  EXEC_PCT=$((EXEC_DONE * 100 / EXEC_TOTAL))
  L1="${VC}[VBW]${X} Build: $(progress_bar "$EXEC_PCT" 8) ${EXEC_DONE}/${EXEC_TOTAL} plans"
  [ "${EXEC_TWAVES:-0}" -gt 1 ] 2>/dev/null && L1="$L1 ${D}│${X} Wave ${EXEC_WAVE}/${EXEC_TWAVES}"
  [ -n "$EXEC_CURRENT" ] && L1="$L1 ${D}│${X} ${C}◆${X} ${EXEC_CURRENT}"
elif [ "$EXEC_STATUS" = "complete" ]; then
  rm -f .vbw-planning/.execution-state.json "$FAST_CF" 2>/dev/null
  EXEC_STATUS=""
  L1="${VC}[VBW]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  if [ "$PT" -gt 0 ] 2>/dev/null; then
    L1="$L1 ${D}│${X} Plans: ${PD}/${PT}"
    if [ "${TT:-0}" -gt 1 ] 2>/dev/null && [ "${PPT:-0}" -gt 0 ] 2>/dev/null; then
      if [ "$PD" -lt "$PT" ] 2>/dev/null || [ "$REM_ACTIVE" = "true" ]; then
        L1="$L1 (${PPD}/${PPT} ${PP_LABEL})"
      fi
    fi
  fi
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  _qc="$D"; case "${QA_COLOR:-D}" in G) _qc="$G";; Y) _qc="$Y";; R) _qc="$R";; esac
  L1="$L1 ${D}│${X} ${_qc}${QA}${X}"
elif [ -d ".vbw-planning" ]; then
  L1="${VC}[VBW]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  if [ "$PT" -gt 0 ] 2>/dev/null; then
    L1="$L1 ${D}│${X} Plans: ${PD}/${PT}"
    if [ "${TT:-0}" -gt 1 ] 2>/dev/null && [ "${PPT:-0}" -gt 0 ] 2>/dev/null; then
      if [ "$PD" -lt "$PT" ] 2>/dev/null || [ "$REM_ACTIVE" = "true" ]; then
        L1="$L1 (${PPD}/${PPT} ${PP_LABEL})"
      fi
    fi
  fi
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  _qc="$D"; case "${QA_COLOR:-D}" in G) _qc="$G";; Y) _qc="$Y";; R) _qc="$R";; esac
  L1="$L1 ${D}│${X} ${_qc}${QA}${X}"
else
  L1="${VC}[VBW]${X} ${D}no project${X}"
fi
if [ -n "$BR" ] || [ -n "$GH_LINK" ] || [ -n "$REPO_LABEL" ]; then
  if [ -n "$GH_LINK" ]; then
    L1="$L1 ${D}│${X} ${GH_LINK}"
  elif [ -n "$REPO_LABEL" ] && [ -n "$BR" ]; then
    L1="$L1 ${D}│${X} ${REPO_LABEL}:${BR}"
  elif [ -n "$REPO_LABEL" ]; then
    L1="$L1 ${D}│${X} ${REPO_LABEL}"
  elif [ -n "$BR" ]; then
    L1="$L1 ${D}│${X} $BR"
  fi
  GIT_IND=""
  [ "${GIT_STAGED:-0}" -gt 0 ] 2>/dev/null && GIT_IND="${G}+${GIT_STAGED}${X}"
  [ "${GIT_MODIFIED:-0}" -gt 0 ] 2>/dev/null && GIT_IND="${GIT_IND}${Y}~${GIT_MODIFIED}${X}"
  [ -n "$GIT_IND" ] && L1="$L1 ${D}Files:${X} $GIT_IND"
  [ "${GIT_AHEAD:-0}" -gt 0 ] 2>/dev/null && L1="$L1 ${D}Commits:${X} ${C}↑${GIT_AHEAD}${X}"
  L1="$L1 ${D}Diff:${X} ${G}+${ADDED}${X} ${R}-${REMOVED}${X}"
fi

L2="Context: ${BC}${CTX_BAR}${X} ${BC}${PCT}%${X} ${CTX_USED_FMT}/${CTX_SIZE_FMT}"
L2="$L2 ${D}│${X} Tokens: ${IN_TOK_FMT} in  ${OUT_TOK_FMT} out"
L2="$L2 ${D}│${X} Prompt Cache: ${CACHE_COLOR}${CACHE_HIT_PCT}% hit${X} ${CACHE_W_FMT} write ${CACHE_R_FMT} read"

L3="$USAGE_LINE"
L4="Model: ${D}${MODEL}${X} ${D}│${X} Time: ${DUR_FMT} (API: ${API_DUR_FMT})"
[ -n "$AGENT_LINE" ] && L4="$L4 ${D}│${X} ${AGENT_LINE}"
if [ -n "$UPDATE_AVAIL" ]; then
  L4="$L4 ${D}│${X} ${Y}${B}VBW ${_VER:-?} → ${UPDATE_AVAIL}${X} ${Y}/vbw:update${X} ${D}│${X} ${D}CC ${VER}${X}"
else
  L4="$L4 ${D}│${X} ${D}VBW ${_VER:-?}${X} ${D}│${X} ${D}CC ${VER}${X}"
fi

printf '%b\n' "$L1"
printf '%b\n' "$L2"
[ -n "$L3" ] && printf '%b\n' "$L3"
printf '%b\n' "$L4"

exit 0
