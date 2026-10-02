#!/usr/bin/env bash
# Usage: check-contributor-files.sh [ROOT]
# Contributor files (CONTRIBUTING.md, AGENTS.md, .github PR/issue templates,
# copilot-instructions.md) may name only paths, tools and /vbw: commands that
# exist under ROOT, and never .vbw-planning. Exits 0 when clean, 1 otherwise.
set -u

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 2

files=()
for f in CONTRIBUTING.md AGENTS.md .github/PULL_REQUEST_TEMPLATE.md \
  .github/copilot-instructions.md .github/ISSUE_TEMPLATE/*; do
  [ -f "$f" ] && files+=("$f")
done

bad=0
report() { printf '%s: %s\n' "$1" "$2"; bad=1; }

for f in ${files[@]+"${files[@]}"}; do
  if grep -q -e '\.vbw-planning' "$f"; then
    report "$f" ".vbw-planning is VBW 1"
  fi
  # Every backticked span, one per line; words inside are checked individually.
  while IFS= read -r span; do
    for word in $span; do
      word="${word%[.,;:]}"
      case "$word" in
        /vbw:[a-z]*)
          name="${word#/vbw:}"
          case "$name" in
            *[!a-z-]*) ;; # placeholder such as /vbw:* or /vbw:...
            *) [ -f "plugin/skills/$name/SKILL.md" ] || report "$f" "$word (no such skill)" ;;
          esac
          ;;
        http*|*'$'*|*'*'*|*'<'*|*'{'*|*'['*|'~'*|/*|./*|../*|*..*) ;;
        tools/*|plugin/*|tests/*|docs/*|.github/*|a_non_prod_docs/*|assets/*|scripts/*)
          [ -e "$word" ] || report "$f" "$word (no such path)"
          ;;
      esac
    done
  done <<EOF2
$(grep -o '`[^`]*`' "$f" | tr -d '`')
EOF2
done
exit "$bad"
