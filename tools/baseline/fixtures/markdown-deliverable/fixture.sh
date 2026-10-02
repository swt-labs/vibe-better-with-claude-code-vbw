#!/usr/bin/env bash
# Seeds a tiny repo whose source files (backup.sh, CHANGES.txt) hold the facts a
# migration guide must state. No MIGRATION.md exists yet.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
cat > backup.sh <<'SH'
#!/usr/bin/env bash
# backup.sh v2: archive a source directory.
# Requires bash 4.4 or newer.
set -euo pipefail
DEFAULT_DEST="$HOME/.local/share/backups"
EXIT_SOURCE_MISSING=66
dest="$DEFAULT_DEST"
while [ $# -gt 1 ]; do
  case "$1" in
    --dest) dest="$2"; shift 2 ;;
    *) shift ;;
  esac
done
src="${1:?usage: backup.sh [--dest DIR] SOURCE}"
[ -d "$src" ] || exit "$EXIT_SOURCE_MISSING"
mkdir -p "$dest"
tar -czf "$dest/$(basename "$src").tar.gz" -C "$src" .
SH
cat > CHANGES.txt <<'TXT'
v2.0
- Default archive directory moved from ./out to ~/.local/share/backups.
- The --output flag is renamed --dest.
- bash 4.4 or newer is now required (v1 ran on bash 3.2).
- A missing source directory exits with code 66 (v1 exited 1).
TXT
chmod +x backup.sh
git add -A && git commit -q -m "chore: seed backup fixture"
