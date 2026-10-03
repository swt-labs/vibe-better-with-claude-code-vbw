#!/usr/bin/env bash
# Usage: check-contributor-files.sh [ROOT]
# Contributor files (CONTRIBUTING.md, AGENTS.md, .github PR/issue templates,
# copilot-instructions.md) may name only paths and /vbw: commands that exist
# under ROOT, and vbw commands its plugin/bin/vbw help lists; a_non_prod_docs/,
# the maintainer's local working documents, is named on purpose and never
# committed; and never .vbw-planning. Exits 0 when clean, 1 otherwise.
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

# The kernel's commands, from its help: the first word of each indented line.
vbw_commands=" "
if [ -f plugin/bin/vbw ]; then
  vbw_commands=" $(bash plugin/bin/vbw help 2> /dev/null | sed -n 's/^  \([a-z][a-z-]*\).*/\1/p' | tr '\n' ' ')"
fi

for f in ${files[@]+"${files[@]}"}; do
  if grep -q -e '\.vbw-planning' "$f"; then
    report "$f" ".vbw-planning is VBW 1"
  fi
  # Every backticked span, one per line; words inside are checked individually.
  while IFS= read -r span; do
    prev=""
    for word in $span; do
      word="${word%[.,;:]}"
      # `vbw NAME ...`: NAME must be a kernel command (placeholders aside).
      if [ "$prev" = vbw ] && [ "$vbw_commands" != " " ]; then
        case "$word" in
          *[!a-z-]* | -*) ;;
          *) case "$vbw_commands" in *" $word "*) ;; *) report "$f" "vbw $word (no such vbw command)" ;; esac ;;
        esac
      fi
      prev=$word
      case "$word" in
        /vbw:[a-z]*)
          name="${word#/vbw:}"
          case "$name" in
            *[!a-z-]*) ;; # placeholder such as /vbw:* or /vbw:...
            *) [ -f "plugin/skills/$name/SKILL.md" ] || report "$f" "$word (no such skill)" ;;
          esac
          ;;
        http*|*'$'*|*'*'*|*'<'*|*'{'*|*'['*|'~'*|/*|./*|../*|*..*) ;;
        # Maintainer-local working documents: named on purpose, never committed.
        a_non_prod_docs/*) ;;
        tools/*|plugin/*|tests/*|docs/*|.github/*|assets/*|scripts/*)
          [ -e "$word" ] || report "$f" "$word (no such path)"
          ;;
      esac
    done
  done <<EOF2
$(grep -o '`[^`]*`' "$f" | tr -d '`')
EOF2
done
exit "$bad"
