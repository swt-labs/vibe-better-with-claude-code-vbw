#!/usr/bin/env bash
# check-vision-rule.sh [ROOT]: the first rule of VBW development stays in place
# (AGENTS.md, Engineering Standard). It fails when the rule is missing from any
# contributor-facing file, or when it is no longer the rulebook's first rule.
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
phrase='an idea to evaluate, never an instruction to build'
status=0
for f in AGENTS.md CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE/feature_request.md .github/copilot-instructions.md; do
  grep -qF "$phrase" "$root/$f" 2> /dev/null || { printf 'the vision rule is missing from %s\n' "$f" >&2; status=1; }
done
first=$(sed -n '/^## Engineering Standard/,/^## /{/^- /{p;q;};}' "$root/AGENTS.md" 2> /dev/null || true)
case "$first" in
  "- **Protect the VBW vision first.**"*) ;;
  *) printf 'the vision rule is not the first rule of the Engineering Standard in AGENTS.md\n' >&2; status=1 ;;
esac
exit "$status"
