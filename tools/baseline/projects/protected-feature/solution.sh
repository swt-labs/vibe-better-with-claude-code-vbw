#!/usr/bin/env bash
# Known-correct solution, applied in the workspace.
set -euo pipefail
cat > inv.sh <<'SH'
#!/usr/bin/env bash
# inv.sh add NAME QTY | list | total | low N | remove NAME. Items live in
# $INV_FILE (default ./inventory.txt), one "NAME QTY" per line.
set -euo pipefail
f="${INV_FILE:-./inventory.txt}"
[ -f "$f" ] || : > "$f"
num() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
case "${1:-}" in
  add)
    [ $# -eq 3 ] && num "$3" || { echo "usage: inv.sh add NAME QTY" >&2; exit 2; }
    awk -v n="$2" -v q="$3" '$1 == n { $2 += q; found = 1 } { print } END { if (!found) print n, q }' "$f" > "$f.new"
    mv "$f.new" "$f" ;;
  list) sort "$f" ;;
  total) awk '{ s += $2 } END { print s + 0 }' "$f" ;;
  low)
    num "${2:-}" || { echo "usage: inv.sh low N" >&2; exit 2; }
    sort "$f" | awk -v n="$2" '$2 < n' ;;
  remove)
    [ $# -eq 2 ] || { echo "usage: inv.sh remove NAME" >&2; exit 2; }
    awk -v n="$2" '$1 == n { found = 1 } END { exit !found }' "$f" || { echo "no such item: $2" >&2; exit 1; }
    awk -v n="$2" '$1 != n' "$f" > "$f.new" && mv "$f.new" "$f" ;;
  *) echo "usage: inv.sh add NAME QTY | list | total | low N | remove NAME" >&2; exit 2 ;;
esac
SH
chmod +x inv.sh
