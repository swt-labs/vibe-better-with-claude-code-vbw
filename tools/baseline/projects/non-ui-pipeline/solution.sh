#!/usr/bin/env bash
# Known-correct solution, applied in the workspace.
set -euo pipefail
cat > logstat.sh <<'SH'
#!/usr/bin/env bash
# logstat.sh FILE: summarize an access log of "TIME METHOD PATH STATUS BYTES" lines.
set -euo pipefail
[ $# -eq 1 ] && [ -r "$1" ] || { echo "usage: logstat.sh FILE (a readable access log)" >&2; exit 2; }
summary=$(awk '
  NF == 5 && $4 ~ /^[0-9][0-9][0-9]$/ && $5 ~ /^[0-9]+$/ {
    n++; bytes += $5; cls[substr($4, 1, 1)]++; hits[$3]++; next
  }
  { bad++ }
  END {
    print "S requests: " n + 0
    for (c = 2; c <= 5; c++) print "S status " c "xx: " cls[c] + 0
    print "S bytes: " bytes + 0
    for (p in hits) print "H " hits[p] " " p
    print "M " bad + 0
  }' "$1")
printf '%s\n' "$summary" | sed -n 's/^S //p'
printf '%s\n' "$summary" | sed -n 's/^H //p' | sort -k1,1nr -k2,2 | head -3 | awk '{ print "top: " $2 " (" $1 ")" }'
printf '%s\n' "$summary" | sed -n 's/^M /malformed: /p' >&2
SH
chmod +x logstat.sh
