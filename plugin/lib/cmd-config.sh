#!/usr/bin/env bash
# vbw config [set KEY VALUE | models | autonomy]: project settings in
# record.settings, shared through git. Keys: profile (quality|balanced|budget),
# autonomy (guided|balanced|hands-off: how much /vbw:vibe does on its own;
# balanced when unset), autonomy_cap (steps per autonomous run), model.<role>
# (architect|lead|dev|qa|scout|debugger|docs, VBW 1's team: opus, sonnet,
# haiku or a model id; "default" removes the override), rigor (auto|express|
# standard|deep: auto computes each phase's tier, the others force it).

# Profiles name a model per workflow role (lib/profiles.json, shared with the
# status line). The session itself always runs the user's model, which must be
# auto-capable (build plan K7).
# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"
VBW_PROFILES=$(jq -c . "$VBW_LIB/profiles.json")
VBW_ROLES="architect lead dev qa scout debugger docs"

# Overrides saved under the earlier role names keep working under VBW 1's:
# planner -> lead, critic -> qa, builder -> dev (a one-time rename).
config_migrate_roles() {
  record_read | jq -e '(.settings.models // {}) | has("planner") or has("critic") or has("builder")' > /dev/null || return 0
  record_update '.settings.models |= (with_entries(.key |= ({planner: "lead", critic: "qa", builder: "dev"}[.] // .)))'
}

# config_rigor [MODE]: print the mode, or set it and re-tier the current
# milestone's phases whose plans are all still planned and that have no
# escalations (auto recomputes through rigor.sh, a forced mode sets the tier).
config_rigor() {
  local mode="${1:-}" old ids tiers
  if [ -z "$mode" ]; then
    record_read | jq -r '.settings.rigor // "auto"'
    return 0
  fi
  case "$mode" in auto|express|standard|deep) ;; *) vbw_usage_error "rigor must be auto, express, standard or deep" ;; esac
  old=$(record_read | jq -r '.settings.rigor // "auto"')
  record_update '.settings.rigor = $v' --arg v "$mode"
  if [ "$old" != "$mode" ]; then
    ids=()
    while IFS= read -r p; do ids+=("$p"); done < <(record_read | jq -r '.milestone.id as $m | . as $r
      | $r.phases[] | select(.milestone == $m and ((.escalations // []) | length) == 0)
      | select(.id as $i | [$r.plans[] | select(.phase == $i and .status != "planned")] | length == 0) | .id')
    if [ ${#ids[@]} -gt 0 ]; then
      tiers=$(record_read | jq 'del(.phases[].tier)' | rigor_assess "${ids[@]}")
      record_update '(.phases[] | select(.id as $i | $t | any(.[]; .id == $i))) |= (. as $ph
        | ([$t[] | select(.id == $ph.id)][0]) as $a
        | if $m == "auto" then .tier = $a.tier | .reasons = $a.reasons
          else .tier = $m | .reasons = $a.reasons + ["forced: vbw config rigor \($m)"] end)' \
        --argjson t "$tiers" --arg m "$mode"
    fi
  fi
  printf 'rigor = %s\n' "$mode"
}

cmd_config() {
  local sub="${1:-}"
  case "$sub" in
    "") [ $# -eq 0 ] || vbw_usage_error "usage: vbw config" ;;
    rigor) [ $# -le 2 ] || vbw_usage_error "usage: vbw config rigor [auto|express|standard|deep]" ;;
    models|autonomy) [ $# -eq 1 ] || vbw_usage_error "usage: vbw config $sub" ;;
    set) [ $# -eq 3 ] || vbw_usage_error "usage: vbw config set KEY VALUE" ;;
    *) vbw_usage_error "usage: vbw config | config models | config autonomy | config rigor [MODE] | config set KEY VALUE" ;;
  esac
  vbw_require_project
  config_migrate_roles
  case "$sub" in
    "")
      record_read | jq -r --argjson p "$VBW_PROFILES" '.settings as $s
        | "profile: \($s.profile)", "autonomy: \($s.autonomy // "balanced")", "autonomy_cap: \($s.autonomy_cap)", "rigor: \($s.rigor // "auto")",
          ($p[$s.profile] + ($s.models // {}) | to_entries[] | "model.\(.key): \(.value)")'
      ;;
    models)
      record_read | jq -c --argjson p "$VBW_PROFILES" '$p[.settings.profile] + (.settings.models // {})'
      ;;
    autonomy)
      record_read | jq -r '.settings.autonomy // "balanced"'
      ;;
    rigor) config_rigor "${2:-}" ;;
    set)
      local key="$2" value="$3"
      case "$key" in
        profile)
          printf '%s' "$VBW_PROFILES" | jq -e --arg v "$value" 'has($v)' > /dev/null \
            || vbw_usage_error "profile must be quality, balanced or budget"
          record_update '.settings.profile = $v' --arg v "$value" ;;
        autonomy)
          case "$value" in guided|balanced|hands-off) ;; *) vbw_usage_error "autonomy must be guided, balanced or hands-off" ;; esac
          record_update '.settings.autonomy = $v' --arg v "$value" ;;
        autonomy_cap)
          [[ "$value" =~ ^[0-9]+$ ]] || vbw_usage_error "autonomy_cap must be a number of steps"
          record_update '.settings.autonomy_cap = ($v | tonumber)' --arg v "$value" ;;
        model.architect|model.lead|model.dev|model.qa|model.scout|model.debugger|model.docs)
          if [ "$value" = default ]; then
            record_update '.settings.models |= del(.[$r]) | if (.settings.models // {}) == {} then .settings |= del(.models) else . end' --arg r "${key#model.}"
          else
            record_update '.settings.models = ((.settings.models // {}) + {($r): $v})' --arg r "${key#model.}" --arg v "$value"
          fi ;;
        *) vbw_usage_error "unknown setting $key (profile, autonomy, autonomy_cap, model.ROLE for $VBW_ROLES)" ;;
      esac
      printf '%s = %s\n' "$key" "$value"
      ;;
  esac
}
