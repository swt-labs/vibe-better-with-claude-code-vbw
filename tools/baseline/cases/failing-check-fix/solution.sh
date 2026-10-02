#!/usr/bin/env bash
# Known-correct solution, applied in the workspace.
set -euo pipefail
cat > slug.sh <<'SH'
#!/usr/bin/env bash
# slugify TEXT: lowercase, runs of non-alphanumerics become one "-", edges trimmed.
slugify() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//'; }
SH
