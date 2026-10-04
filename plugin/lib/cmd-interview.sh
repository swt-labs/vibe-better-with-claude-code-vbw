#!/usr/bin/env bash
# vbw interview [--json] | set KEY VALUE | keep private|project: the interview's
# answers (level, depth, involvement), kept private or in the project record
# (docs/interview.md). Only these three answers are stored: what is being built
# and for whom is not a personal answer and is refused.
# shellcheck source=interview.sh
. "$VBW_LIB/interview.sh"

cmd_interview() {
  local sub="${1:-}" e k v kept
  vbw_require_project
  case "$sub" in
    "" | --json)
      e=$(interview_effective)
      if [ "$sub" = "--json" ]; then
        printf '%s\n' "$e"
      else
        printf '%s\n' "$e" | jq -r '(.kept // "not kept yet") as $w | "kept: \($w)", (["level","depth","involvement"][] as $k | "\($k): \(.[$k] // "-")")'
      fi
      ;;
    set)
      [ $# -eq 3 ] || vbw_usage_error "usage: vbw interview set level|depth|involvement VALUE"
      k="$2"
      v="$3"
      case "$k" in
        level | depth | involvement) ;;
        *) vbw_die "$k is not an interview answer (level, depth or involvement); what is being built is never stored here" 2 ;;
      esac
      jq -e --arg k "$k" --arg v "$v" '.[$k] | any(. == $v)' "$VBW_LIB/interview.json" > /dev/null \
        || vbw_die "$v is not a $k answer; choose one of: $(jq -r --arg k "$k" '.[$k] | join("; ")' "$VBW_LIB/interview.json")"
      kept=$(interview_effective | jq -r '.kept // ""')
      if [ "$kept" = "project" ]; then
        record_update '.project.interview[$k] = $v | .project.interview.at = $at' --arg k "$k" --arg v "$v" --arg at "$(vbw_now)"
      else
        interview_private_update '.[$k] = $v' --arg k "$k" --arg v "$v"
      fi
      printf '%s = %s\n' "$k" "$v"
      ;;
    keep)
      [ $# -eq 2 ] || vbw_usage_error "usage: vbw interview keep private|project"
      case "$2" in private | project) ;; *) vbw_usage_error "keep private or project" ;; esac
      e=$(interview_effective)
      k=$(printf '%s' "$e" | jq -r 'if .pending == "keep" then "" else .pending // "" end')
      [ -z "$k" ] || vbw_die "the $k answer is missing: vbw interview set $k VALUE, then keep"
      if [ "$2" = "private" ]; then
        interview_private_update '. + $a + {done: true}' --argjson a "$(printf '%s' "$e" | jq -c '{level, depth, involvement}')"
        record_update 'del(.project.interview)'
      else
        record_update '.project.interview = ($a + {at: $at})' --argjson a "$(printf '%s' "$e" | jq -c '{level, depth, involvement}')" --arg at "$(vbw_now)"
        interview_private_update 'del(.level, .depth, .involvement, .done)'
      fi
      printf 'the interview answers are kept %s\n' "$2"
      ;;
    *) vbw_usage_error "usage: vbw interview [--json] | set KEY VALUE | keep private|project" ;;
  esac
}
