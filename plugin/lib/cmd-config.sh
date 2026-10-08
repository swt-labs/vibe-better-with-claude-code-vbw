#!/usr/bin/env bash
# vbw config [set KEY VALUE | models | autonomy | effort]: project settings in
# record.settings, shared through git. Keys: profile (quality|balanced|budget),
# autonomy (guided|balanced|hands-off: how much /vbw:vibe does on its own;
# balanced when unset), autonomy_cap (steps per autonomous run), model.<role>
# (architect|lead|dev|qa|scout|debugger|docs, VBW 1's team: opus, sonnet,
# haiku or a model id; "default" removes the override; model.qa refuses Haiku,
# naming the allowed models: sonnet, opus or a stronger model id, or default,
# since QA needs Sonnet or stronger), rigor (auto|express|
# standard|deep: auto computes each phase's tier, the others force it),
# motion (full|calm|off: the panel's animation; "default" removes it and the
# panel picks by the interview level), check_jobs (1 to 64, default 4: checks run at the same time; kept in this
# clone's own settings file in the git directory, not in the record).

# Profiles name a model per workflow role (lib/profiles.json, shared with the
# status line). The session itself always runs the user's model, which must be
# auto-capable (build plan K7).
# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"
# shellcheck source=effort.sh
. "$VBW_LIB/effort.sh"
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
# escalations (auto recomputes through rigor.sh and keeps a tier the Architect
# raised above the floor, a forced mode sets the tier).
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
      record_update "$VBW_JQ_DEFS"'(.phases[] | select(.id as $i | $t | any(.[]; .id == $i))) |= (. as $ph
        | ([$t[] | select(.id == $ph.id)][0]) as $a
        | if $m == "auto" then
            (if .proposed != null and (.proposed | tier_rank) > ($a.floor | tier_rank)
             then .tier = .proposed | .predicted = .proposed | .reasons = $a.reasons + ["raised by the Architect"]
             else .tier = $a.tier | .predicted = $a.tier | .reasons = $a.reasons end)
          else .tier = $m | .predicted = $m | .reasons = $a.reasons + ["forced: vbw config rigor \($m)"] end)' \
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
    models|autonomy|effort) [ $# -eq 1 ] || vbw_usage_error "usage: vbw config $sub" ;;
    set) [ $# -eq 3 ] || vbw_usage_error "usage: vbw config set KEY VALUE" ;;
    *) vbw_usage_error "usage: vbw config | config models | config autonomy | config effort | config rigor [MODE] | config set KEY VALUE" ;;
  esac
  vbw_require_project
  config_migrate_roles
  case "$sub" in
    "")
      printf 'check_jobs: %s\n' "$(vbw_check_jobs)"
      record_read | jq -r --argjson p "$VBW_PROFILES" '.settings as $s
        | "profile: \($s.profile)", "autonomy: \($s.autonomy // "balanced")", "autonomy_cap: \($s.autonomy_cap)", "rigor: \($s.rigor // "auto")", "motion: \($s.motion // "default")",
          ($p[$s.profile] + ($s.models // {}) | (if ((.qa // "") | ascii_downcase | contains("haiku")) then .qa = "sonnet" else . end) | to_entries[] | "model.\(.key): \(.value)")'
      ;;
    models)
      record_read | jq -c --argjson p "$VBW_PROFILES" '$p[.settings.profile] + (.settings.models // {}) | (if ((.qa // "") | ascii_downcase | contains("haiku")) then .qa = "sonnet" else . end)'
      ;;
    effort)
      effort_table "$(record_read | jq -r ".settings.profile")"
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
        motion)
          case "$value" in
            full|calm|off) record_update '.settings.motion = $v' --arg v "$value" ;;
            default) record_update '.settings |= del(.motion)' ;;
            *) vbw_usage_error "motion must be full, calm or off (or default): how much the VBW panel animates" ;;
          esac ;;
        check_jobs)
          case "$value" in
            default) ;;
            [1-9] | [1-5][0-9] | 6[0-4]) ;;
            *) vbw_usage_error "check_jobs must be a whole number from 1 to 64 (or default): how many checks run at the same time" ;;
          esac
          vbw_check_jobs_set "$value" ;;
        model.qa)
          case $(printf '%s' "$value" | tr '[:upper:]' '[:lower:]') in
            *haiku*) vbw_usage_error "model.qa cannot be Haiku: QA needs Sonnet or stronger. Allowed: sonnet, opus or a stronger model id, or default" ;;
          esac
          if [ "$value" = default ]; then
            record_update '.settings.models |= del(.qa) | if (.settings.models // {}) == {} then .settings |= del(.models) else . end'
          else
            record_update '.settings.models = ((.settings.models // {}) + {qa: $v})' --arg v "$value"
          fi ;;
        model.architect|model.lead|model.dev|model.scout|model.debugger|model.docs)
          if [ "$value" = default ]; then
            record_update '.settings.models |= del(.[$r]) | if (.settings.models // {}) == {} then .settings |= del(.models) else . end' --arg r "${key#model.}"
          else
            record_update '.settings.models = ((.settings.models // {}) + {($r): $v})' --arg r "${key#model.}" --arg v "$value"
          fi ;;
        *) vbw_usage_error "unknown setting $key (profile, autonomy, autonomy_cap, motion, check_jobs, model.ROLE for $VBW_ROLES)" ;;
      esac
      printf '%s = %s\n' "$key" "$value"
      ;;
  esac
}
