#!/usr/bin/env bash
# Deterministic post-run check: MIGRATION.md has the three required headings and
# states each fact from the fixture's source files.
set -euo pipefail
f=MIGRATION.md
[ -s "$f" ]
for h in Overview "Breaking changes" "Upgrade steps"; do
  grep -Eqi "^#{1,3}[[:space:]]+${h}[[:space:]]*$" "$f"
done
# The document must name the path literally, tilde included.
# shellcheck disable=SC2088
grep -Fq '~/.local/share/backups' "$f"
grep -Fq -- '--dest' "$f"
grep -Fq -- '--output' "$f"
grep -Eqi 'bash[^0-9]*4\.4' "$f"
# The new code on a line about the exit code (the old one, 1, may come first).
grep -Eqi 'exit.*(^|[^0-9])66([^0-9]|$)' "$f"
