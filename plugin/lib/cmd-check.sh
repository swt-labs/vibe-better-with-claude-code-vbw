#!/usr/bin/env bash
# vbw check [--expect-red] [CHECK...]: run approved checks (all when none are
# given) and report; writes nothing to the record. A builder uses it red-first
# (--expect-red: every check must fail, or it proves nothing) and to see its
# own checks go green before it commits.

# shellcheck source=checks.sh
. "$VBW_LIB/checks.sh"

cmd_check() {
  local red=0
  if [ "${1:-}" = "--expect-red" ]; then
    red=1
    shift
  fi
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  local record results
  record=$(record_read)
  checks_begin "$record"
  results=$(checks_run_all "$record" "$@")
  checks_end
  [ "$results" != "{}" ] || vbw_die "no checks to run"
  printf '%s' "$results" | jq -r --argjson red "$red" 'to_entries[]
    | if $red == 1 then
        (if .value.status == "pass" then "\(.key) passed before building: it proves nothing"
         else "\(.key) red (\(.value.status)), as expected" end)
      else
        "\(.key) \(.value.status) \(.value.seconds)s" + (if .value.status == "pass" then ""
          else ": " + (.value.tail | split("\n") | last // "") end)
      end'
  if [ $red -eq 1 ]; then
    printf '%s' "$results" | jq -e 'all(.[]; .status != "pass")' > /dev/null
  else
    printf '%s' "$results" | jq -e 'all(.[]; .status == "pass")' > /dev/null
  fi
}
