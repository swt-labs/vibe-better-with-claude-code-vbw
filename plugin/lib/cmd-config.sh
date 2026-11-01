#!/usr/bin/env bash
# vbw config [set KEY VALUE | models | autonomy | effort]: project settings in
# record.settings, shared through git. Keys: profile (quality|balanced|budget),
# autonomy (guided|balanced|hands-off: how much /vbw:vibe does on its own;
# balanced when unset), autonomy_cap (steps per autonomous run), model.<role>
# (architect|lead|dev|qa|scout|debugger|docs, VBW 1's team: opus, sonnet,
# haiku or a model id; "default" removes the override; model.qa refuses Haiku,
# naming the allowed models: sonnet, opus or a stronger model id, or default,
# since QA needs Sonnet or stronger), effort.<role> (the same roles: low, medium,
# high, xhigh or max for every step of that role, over the profile's table in
# lib/efforts.json; "default" removes it; a record holding one is schema 5), rigor (auto|express|
# standard|deep: auto computes each phase's tier, the others force it),
# motion (full|calm|off: the panel's animation; "default" removes it and the
# panel picks by the interview level), check_jobs (1 to 64; without a setting three quarters of the processor cores: checks run at the same time; kept in this
# clone's own settings file in the git directory, not in the record; the line
# after check_jobs, "machine limit: L (...)", names the computer-wide limit
# shared by every VBW project, not a setting, and says when it overrides check_jobs),
# command_timeout (1 to 86400 seconds a project command may run under vbw prove; 3600 when unset, "default" removes it),
# check_budget (1 to 86400 seconds a unit of a proof may take before the reports name it over
# budget; 120 when unset, "default" removes it; a report, never a limit: lib/unittime.sh),
# sound (off, or a folder name under assets/audio/ that holds an mp3: the panel's "needs you"
# sound plays from that folder; "default" removes it and the panel picks among every shipped sound;
# this clone's own choice, kept with check_jobs in the clone's settings file, not in the record),
# mcp (entries separated by spaces: SERVER, SERVER:read-only or SERVER:read-only=TOOL,TOOL; the MCP
# servers whose tools the agents may use, "default" removes it; a record holding one is schema 7).

# Profiles name a model per workflow role (lib/profiles.json, shared with the
# status line). The session itself always runs the user's model, which must be
# auto-capable (build plan K7).
# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"
# shellcheck source=effort.sh
. "$VBW_LIB/effort.sh"
# shellcheck source=qa-inputs.sh
. "$VBW_LIB/qa-inputs.sh"
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
  local mode="${1:-}" old ids tiers tiersf
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
      vbw_scratch_json tiersf "$tiers"
      record_update "$VBW_JQ_DEFS"'$tiers[0] as $t | (.phases[] | select(.id as $i | $t | any(.[]; .id == $i))) |= (. as $ph
        | ([$t[] | select(.id == $ph.id)][0]) as $a
        | if $m == "auto" then
            (if .proposed != null and (.proposed | tier_rank) > ($a.floor | tier_rank)
             then .tier = .proposed | .predicted = .proposed | .reasons = $a.reasons + ["raised by the Architect"]
             else .tier = $a.tier | .predicted = $a.tier | .reasons = $a.reasons end)
          else .tier = $m | .predicted = $m | .reasons = $a.reasons + ["forced: vbw config rigor \($m)"] end)' \
        --slurpfile tiers "$tiersf" --arg m "$mode"
      vbw_guard_drop "$tiersf"
    fi
  fi
  printf 'rigor = %s\n' "$mode"
}

# config_machine_limit_line: the computer-wide limit in plain words; when the
# check_jobs in force is above it, it says the limit applies.
config_machine_limit_line() {
  local limit cores jobs tail="; shared by every VBW project on this computer; not a setting)"
  limit=$(vbw_machine_limit)
  jobs=$(vbw_check_jobs)
  if cores=$(vbw_cores); then
    printf "machine limit: %s (three quarters of this computer's processor cores (%s), rounded down, at least 1 and at most 64%s" "$limit" "$cores" "$tail"
  else
    printf "machine limit: %s (this computer's processor core count could not be read%s" "$limit" "$tail"
  fi
  if [ "$jobs" -gt "$limit" ]; then printf ' - it applies, not check_jobs %s' "$jobs"; fi
  printf '\n'
}

# config_sound_names: the folders under assets/audio/ that hold at least one mp3,
# one per line, sorted.
config_sound_names() {
  local d f
  for d in "$VBW_LIB/../assets/audio"/*/; do
    [ -d "$d" ] || continue
    for f in "$d"*.mp3; do
      [ -f "$f" ] || continue
      basename "$d"
      break
    done
  done
}

# config_sound_usage: the refusal naming every value sound accepts.
config_sound_usage() {
  local n list="off" count=0 total=0 all=()
  while IFS= read -r n; do [ -n "$n" ] && all+=("$n"); done < <(config_sound_names)
  total=${#all[@]}
  for n in ${all[@]+"${all[@]}"}; do
    count=$((count + 1))
    if [ "$count" -eq "$total" ]; then list="$list or $n"; else list="$list, $n"; fi
  done
  vbw_usage_error "sound must be $list (or default): the folder under assets/audio the panel's 'needs you' sound plays from, or off"
}

# config_sound_value: the sound set in this clone's settings (off or a folder
# that exists), else "default": a missing, damaged or stale value reads as default.
config_sound_value() {
  local file v
  file=$(vbw_clone_settings_file) || return 1
  v=$(jq -r '.sound // empty | strings' "$file" 2> /dev/null) || v=""
  if [ "$v" = off ] || { [ -n "$v" ] && [ -n "$(config_sound_names | awk -v v="$v" '$0 == v')" ]; }; then
    printf '%s\n' "$v"
  else
    printf 'default\n'
  fi
}

# config_mcp_usage: the refusal naming every form mcp accepts.
config_mcp_usage() {
  vbw_usage_error "mcp must be SERVER, SERVER:read-only or SERVER:read-only=TOOL,TOOL (names: letters, digits, _ . -), separated by spaces, or default"
}

# config_mcp_set VALUE: store the entries of VALUE as settings.mcp (default
# removes it). Validates every entry before anything is written.
config_mcp_set() {
  local value="$1" e name rest tools t lines="" seen=" " entries=()
  if [ "$value" = default ]; then
    record_update '.settings |= del(.mcp)'
    return 0
  fi
  case "$value" in *[!\ A-Za-z0-9_.:,=-]*) config_mcp_usage ;; esac
  for e in $value; do entries+=("$e"); done
  [ ${#entries[@]} -gt 0 ] || config_mcp_usage
  for e in "${entries[@]}"; do
    name="${e%%:*}"
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || config_mcp_usage
    case "$seen" in *" $name "*) config_mcp_usage ;; esac
    seen="$seen$name "
    if [ "$name" = "$e" ]; then
      lines="$lines$name"$'\topen\n'
      continue
    fi
    rest="${e#*:}"
    case "$rest" in
      read-only) lines="$lines$name"$'\tall\n' ;;
      read-only=*)
        tools="${rest#read-only=}"
        [ -n "$tools" ] || config_mcp_usage
        case ",$tools," in *",,"*) config_mcp_usage ;; esac
        for t in ${tools//,/ }; do
          [[ "$t" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || config_mcp_usage
        done
        lines="$lines$name"$'\ttools\t'"$tools"$'\n' ;;
      *) config_mcp_usage ;;
    esac
  done
  record_update '.settings.mcp = [$l | split("\n")[] | select(. != "") | split("\t")
    | {server: .[0], read_only: (if .[1] == "open" then false elif .[1] == "all" then true else (.[2] | split(",")) end)}]' --arg l "$lines"
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
      printf 'check_jobs: %s (%s)\n' "$(vbw_check_jobs)" "$(vbw_check_jobs_source)"
      config_machine_limit_line
      printf 'sound: %s\n' "$(config_sound_value)"
      record_read | jq -r --argjson p "$VBW_PROFILES" '.settings as $s
        | "profile: \($s.profile)", "autonomy: \($s.autonomy // "balanced")", "autonomy_cap: \($s.autonomy_cap)", "rigor: \($s.rigor // "auto")", "motion: \($s.motion // "default")", "command_timeout: \($s.command_timeout // 3600) seconds",
          "check_budget: \($s.check_budget // 120) seconds a unit (reported, never enforced)",
          ($p[$s.profile] + ($s.models // {}) | (if ((.qa // "") | ascii_downcase | contains("haiku")) then .qa = "sonnet" else . end) | to_entries[] | "model.\(.key): \(.value)"),
          ($p[$s.profile] | keys_unsorted[] as $r | "effort.\($r): \(($s.efforts // {})[$r] // "default")"),
          "mcp: \(if ($s.mcp // null) == null then "none" else [$s.mcp[] | .server + (if .read_only == false then "" elif .read_only == true then ":read-only" else ":read-only=" + (.read_only | join(",")) end)] | join(" ") end)"'
      ;;
    models)
      record_read | jq -c --argjson p "$VBW_PROFILES" '$p[.settings.profile] + (.settings.models // {}) | (if ((.qa // "") | ascii_downcase | contains("haiku")) then .qa = "sonnet" else . end)'
      ;;
    effort)
      effort_table "$(record_read | jq -r ".settings.profile")" "$(record_read | jq -c ".settings.efforts // null")"
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
        mcp) config_mcp_set "$value" ;;
        sound)
          case "$value" in
            default) vbw_clone_setting_set sound default ;;
            off) vbw_clone_setting_set sound '"off"' ;;
            "" | *[!a-z0-9_-]*) config_sound_usage ;;
            *)
              [ -n "$(config_sound_names | awk -v v="$value" '$0 == v')" ] || config_sound_usage
              vbw_clone_setting_set sound "\"$value\"" ;;
          esac ;;
        check_jobs)
          case "$value" in
            default) ;;
            [1-9] | [1-5][0-9] | 6[0-4]) ;;
            *) vbw_usage_error "check_jobs must be a whole number from 1 to 64 (or default): how many checks run at the same time" ;;
          esac
          vbw_check_jobs_set "$value" ;;
        command_timeout)
          case "$value" in
            default) record_update '.settings |= del(.command_timeout)' ;;
            0* | *[!0-9]* | "") vbw_usage_error "command_timeout must be a whole number of seconds from 1 to 86400 (or default): how long vbw prove lets a project command run" ;;
            *)
              [ "${#value}" -le 5 ] && [ "$value" -le 86400 ] || vbw_usage_error "command_timeout must be a whole number of seconds from 1 to 86400 (or default): how long vbw prove lets a project command run"
              record_update '.settings.command_timeout = ($v | tonumber)' --arg v "$value" ;;
          esac ;;
        check_budget)
          case "$value" in
            default) record_update '.settings |= del(.check_budget)' ;;
            0* | *[!0-9]* | "") vbw_usage_error "check_budget must be a whole number of seconds from 1 to 86400 (or default): how long a unit of a proof may take before the reports name it over budget" ;;
            *)
              [ "${#value}" -le 5 ] && [ "$value" -le 86400 ] || vbw_usage_error "check_budget must be a whole number of seconds from 1 to 86400 (or default): how long a unit of a proof may take before the reports name it over budget"
              record_update '.settings.check_budget = ($v | tonumber)' --arg v "$value" ;;
          esac ;;
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
        effort.architect|effort.lead|effort.dev|effort.qa|effort.scout|effort.debugger|effort.docs)
          case "$value" in
            default) record_update '.settings.efforts |= del(.[$r]) | if (.settings.efforts // {}) == {} then .settings |= del(.efforts) else . end' --arg r "${key#effort.}" ;;
            low|medium|high|xhigh|max) record_update '.settings.efforts = ((.settings.efforts // {}) + {($r): $v})' --arg r "${key#effort.}" --arg v "$value" ;;
            *) vbw_usage_error "$key must be low, medium, high, xhigh or max (or default): how hard that helper thinks at every step, over the profile's choice" ;;
          esac ;;
        *) vbw_usage_error "unknown setting $key (profile, autonomy, autonomy_cap, motion, sound, check_jobs, command_timeout, check_budget, mcp, model.ROLE or effort.ROLE for $VBW_ROLES)" ;;
      esac
      printf '%s = %s\n' "$key" "$value"
      ;;
  esac
}
