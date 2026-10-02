#!/usr/bin/env bash
# Known-correct solution, applied in the workspace.
set -euo pipefail
cat > todo.sh <<'SH'
#!/usr/bin/env bash
# todo.sh add TEXT | list | done N. Items live in $TODO_FILE (default ./todos.txt), one per line.
set -euo pipefail
f="${TODO_FILE:-./todos.txt}"
case "${1:-}" in
  add) shift; echo "[ ] $*" >> "$f" ;;
  list) [ -f "$f" ] && nl -w1 -s'. ' "$f" || true ;;
  done)
    n="${2:-}"
    total=0; [ -f "$f" ] && total="$(wc -l < "$f" | tr -d ' ')"
    case "$n" in ''|*[!0-9]*) echo "done: bad item number" >&2; exit 1 ;; esac
    if [ "$n" -lt 1 ] || [ "$n" -gt "$total" ]; then echo "done: no item $n" >&2; exit 1; fi
    sed "${n}s/^\[ \]/[x]/" "$f" > "$f.new" && mv "$f.new" "$f" ;;
  *) echo "usage: todo.sh add TEXT | list | done N" >&2; exit 2 ;;
esac
SH
