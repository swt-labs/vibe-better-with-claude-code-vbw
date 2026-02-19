#!/bin/bash
# VBW Status Line — 4-line dashboard (L1: project, L2: context, L3: usage+cache, L4: model/cost)
# Cache: {prefix}-fast (5s), {prefix}-slow (60s), {prefix}-cost (per-render), {prefix}-ok (permanent)

input=$(cat)

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

NOW=$(date +%s)

CTX_USED=$((IN_TOK + CACHE_W + CACHE_R))
CTX_USED_FMT=$(fmt_tok "$CTX_USED")
CTX_SIZE_FMT=$(fmt_tok "$CTX_SIZE")

# Cache context usage for pre-flight guard (suggest-compact.sh)
if [ -d ".vbw-planning" ]; then
  printf '%s\n' "${PCT}|${CTX_SIZE}" > .vbw-planning/.context-usage 2>/dev/null || true
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
  PD=0; PT=0; PPD=0; QA="--"; GH_URL=""
  if [ -f ".vbw-planning/STATE.md" ]; then
    PH=$(grep -m1 "^Phase:" .vbw-planning/STATE.md | grep -oE '[0-9]+' | head -1)
    TT=$(grep -m1 "^Phase:" .vbw-planning/STATE.md | grep -oE '[0-9]+' | tail -1)
  fi
  if [ -f ".vbw-planning/config.json" ]; then
    # Auto-migrate: add model_profile if missing
    if ! jq -e '.model_profile' .vbw-planning/config.json >/dev/null 2>&1; then
      TMP=$(mktemp)
      jq '. + {model_profile: "quality", model_overrides: {}}' .vbw-planning/config.json > "$TMP" && mv "$TMP" .vbw-planning/config.json
    fi
    EF=$(jq -r '.effort // "balanced"' .vbw-planning/config.json 2>/dev/null)
    MP=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json 2>/dev/null)
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
    PD=$(find .vbw-planning/phases -name '*-SUMMARY.md' 2>/dev/null | wc -l | tr -d ' ')
    if [ -n "$PH" ] && [ "$PH" != "0" ]; then
      PDIR=$(find .vbw-planning/phases -maxdepth 1 -type d -name "$(printf '%02d' "$PH")-*" 2>/dev/null | head -1)
      [ -n "$PDIR" ] && PPD=$(find "$PDIR" -name '*-SUMMARY.md' 2>/dev/null | wc -l | tr -d ' ')
      [ -n "$PDIR" ] && [ -n "$(find "$PDIR" -name '*VERIFICATION.md' 2>/dev/null | head -1)" ] && QA="pass"
    fi
  fi

  EXEC_STATUS=""; EXEC_WAVE=0; EXEC_TWAVES=0; EXEC_DONE=0; EXEC_TOTAL=0; EXEC_CURRENT=""
  if [ -f ".vbw-planning/.execution-state.json" ]; then
    IFS='|' read -r EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT <<< \
      "$(jq -r '[
        (.status // ""),
        (.wave // 0),
        (.total_waves // 0),
        ([.plans[] | select(.status == "complete")] | length),
        (.plans | length),
        ([.plans[] | select(.status == "running")][0].title // "")
      ] | join("|")' .vbw-planning/.execution-state.json 2>/dev/null)"
  fi

  AGENT_DATA="0"

  printf '%s\n' "${PH:-0}|${TT:-0}|${EF}|${MP}|${BR}|${PD}|${PT}|${PPD}|${QA}|${GH_URL}|${GIT_STAGED:-0}|${GIT_MODIFIED:-0}|${GIT_AHEAD:-0}|${EXEC_STATUS:-}|${EXEC_WAVE:-0}|${EXEC_TWAVES:-0}|${EXEC_DONE:-0}|${EXEC_TOTAL:-0}|${EXEC_CURRENT:-}|${AGENT_DATA:-0}" > "$FAST_CF" 2>/dev/null
fi

if [ -O "$FAST_CF" ]; then
  # shellcheck disable=SC2034
  IFS='|' read -r PH TT EF MP BR PD PT PPD QA GH_URL GIT_STAGED GIT_MODIFIED GIT_AHEAD \
                  EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT \
                  AGENT_N < "$FAST_CF"
fi

AGENT_LINE=""

# --- Slow cache (60s TTL): usage limits + update check ---
SLOW_CF="${_CACHE}-slow"

if ! cache_fresh "$SLOW_CF" 60; then
  OAUTH_TOKEN=""
  AUTH_METHOD=""

  # Priority 1: env var override (escape hatch for keychain issues)
  if [ -n "${VBW_OAUTH_TOKEN:-}" ]; then
    OAUTH_TOKEN="$VBW_OAUTH_TOKEN"
  fi

  # Priority 2: system credential store
  if [ -z "$OAUTH_TOKEN" ]; then
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

  # Priority 3: credentials file (check both with and without leading dot)
  if [ -z "$OAUTH_TOKEN" ]; then
    CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    for _cred in "$CLAUDE_DIR/.credentials.json" "$CLAUDE_DIR/credentials.json"; do
      if [ -f "$_cred" ]; then
        OAUTH_TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$_cred" 2>/dev/null)
        [ -n "$OAUTH_TOKEN" ] && break
      fi
    done
  fi

  # Priority 4: detect auth method via claude CLI (distinguishes OAuth vs API key)
  if [ -z "$OAUTH_TOKEN" ]; then
    AUTH_STATUS=$(CLAUDECODE="" claude auth status --json 2>/dev/null) || AUTH_STATUS=""
    if [ -n "$AUTH_STATUS" ]; then
      AUTH_METHOD=$(echo "$AUTH_STATUS" | jq -r '.authMethod // empty' 2>/dev/null)
    fi
  fi

  FIVE_PCT=0; FIVE_EPOCH=0; WEEK_PCT=0; WEEK_EPOCH=0; SONNET_PCT=-1
  EXTRA_ENABLED=0; EXTRA_PCT=-1; EXTRA_USED_C=0; EXTRA_LIMIT_C=0; FETCH_OK="noauth"

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

  printf '%s\n' "${FIVE_PCT:-0}|${FIVE_EPOCH:-0}|${WEEK_PCT:-0}|${WEEK_EPOCH:-0}|${SONNET_PCT:--1}|${EXTRA_ENABLED:-0}|${EXTRA_PCT:--1}|${EXTRA_USED_C:-0}|${EXTRA_LIMIT_C:-0}|${FETCH_OK}|${UPDATE_AVAIL:-}|${AUTH_METHOD:-}" > "$SLOW_CF" 2>/dev/null
fi

if [ -O "$SLOW_CF" ]; then
  IFS='|' read -r FIVE_PCT FIVE_EPOCH WEEK_PCT WEEK_EPOCH SONNET_PCT \
                  EXTRA_ENABLED EXTRA_PCT EXTRA_USED_C EXTRA_LIMIT_C \
                  FETCH_OK UPDATE_AVAIL AUTH_METHOD < "$SLOW_CF"
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
elif [ "$FETCH_OK" = "fail" ]; then
  USAGE_LINE="${D}Limits: fetch failed (retry in 60s)${X}"
elif [ "$AUTH_METHOD" = "claude.ai" ]; then
  USAGE_LINE="${D}Limits: keychain access denied (allow Terminal in Keychain Access.app or set VBW_OAUTH_TOKEN)${X}"
else
  USAGE_LINE="${D}Limits: N/A (using API key)${X}"
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

if [ "$EXEC_STATUS" = "running" ] && [ "${EXEC_TOTAL:-0}" -gt 0 ] 2>/dev/null; then
  EXEC_PCT=$((EXEC_DONE * 100 / EXEC_TOTAL))
  L1="${C}${B}[VBW]${X} Build: $(progress_bar "$EXEC_PCT" 8) ${EXEC_DONE}/${EXEC_TOTAL} plans"
  [ "${EXEC_TWAVES:-0}" -gt 1 ] 2>/dev/null && L1="$L1 ${D}│${X} Wave ${EXEC_WAVE}/${EXEC_TWAVES}"
  [ -n "$EXEC_CURRENT" ] && L1="$L1 ${D}│${X} ${C}◆${X} ${EXEC_CURRENT}"
elif [ "$EXEC_STATUS" = "complete" ]; then
  rm -f .vbw-planning/.execution-state.json "$FAST_CF" 2>/dev/null
  EXEC_STATUS=""
  L1="${C}${B}[VBW]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  [ "$PT" -gt 0 ] 2>/dev/null && L1="$L1 ${D}│${X} Plans: ${PD}/${PT} (${PPD} this phase)"
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  if [ "$QA" = "pass" ]; then L1="$L1 ${D}│${X} ${G}QA: pass${X}"
  else L1="$L1 ${D}│${X} ${D}QA: --${X}"; fi
elif [ -d ".vbw-planning" ]; then
  L1="${C}${B}[VBW]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  [ "$PT" -gt 0 ] 2>/dev/null && L1="$L1 ${D}│${X} Plans: ${PD}/${PT} (${PPD} this phase)"
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  if [ "$QA" = "pass" ]; then
    L1="$L1 ${D}│${X} ${G}QA: pass${X}"
  else
    L1="$L1 ${D}│${X} ${D}QA: --${X}"
  fi
else
  L1="${C}${B}[VBW]${X} ${D}no project${X}"
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
printf '%b\n' "$L3"
printf '%b\n' "$L4"

exit 0
