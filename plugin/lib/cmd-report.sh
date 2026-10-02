#!/usr/bin/env bash
# vbw report: the diagnostic facts for a bug report about VBW, as markdown:
# versions, the doctor's checks, and the project's state as counts and ids.
# Never the spec's text, code, file contents or check output.

# shellcheck source=cmd-doctor.sh
. "$VBW_LIB/cmd-doctor.sh"

cmd_report() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw report"
  printf '### Environment\n\n'
  printf -- '- VBW %s\n' "$(jq -r .version "$VBW_PLUGIN/.claude-plugin/plugin.json")"
  printf -- '- %s\n' "$(uname -sr 2> /dev/null)"
  printf -- '- bash %s\n' "${BASH_VERSION:-?}"
  printf '\n### vbw doctor\n\n```\n'
  cmd_doctor 2>&1 || true
  printf '```\n'
  local root
  root=$(git rev-parse --show-toplevel 2> /dev/null) || return 0
  [ -f "$root/.vbw/record.json" ] || return 0
  printf '\n### Project state\n\n```\n'
  if ! jq -e . "$root/.vbw/record.json" > /dev/null 2>&1; then
    printf 'record: corrupt (.vbw/record.json does not parse; content not shown)\n```\n'
    return 0
  fi
  jq -r '"milestone \(.milestone.id) \(.milestone.status)",
    "requirements: \(.requirements | group_by(.status) | map("\(.[0].status) \(length)") | join(", ") | if . == "" then "none" else . end)",
    "plans: \(.plans | group_by(.status) | map("\(.[0].status) \(length)") | join(", ") | if . == "" then "none" else . end)",
    "checks: \(.checks | length)",
    "fixes: \(.fixes | map("\(.id) \(.status) attempts \(.attempts)") | join(", ") | if . == "" then "none" else . end)",
    "lease: \(if .lease then "\(.lease.kind) since \(.lease.started_at)" else "none" end)",
    "evidence: \(if .evidence then "\(.evidence.at) passed=\(.evidence.passed) failing=\([.evidence.checks | to_entries[] | select(.value.status != "pass") | .key] | join(" "))" else "none" end)",
    "profile: \(.settings.profile)"' "$root/.vbw/record.json" 2>&1
  [ ! -f "$root/.vbw/runtime/next.json" ] || jq -r '"last next: \(.action)"' "$root/.vbw/runtime/next.json" 2> /dev/null
  printf '```\n'
}
