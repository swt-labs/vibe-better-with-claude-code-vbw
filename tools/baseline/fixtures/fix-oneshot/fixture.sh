#!/usr/bin/env bash
# Seeds a tiny repo with one bug: add() subtracts. test.sh prints TESTS PASS or
# TESTS FAIL. When v1-defaults.json sits beside this script, it also creates a
# minimal initialized v1 project (.vbw-planning/) so /vbw:fix can run.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
cat > calc.sh <<'SH'
#!/usr/bin/env bash
add() { echo $(( $1 - $2 )); }
SH
cat > test.sh <<'SH'
#!/usr/bin/env bash
. ./calc.sh
if [ "$(add 2 3)" = "5" ] && [ "$(add -1 1)" = "0" ]; then echo "TESTS PASS"; else echo "TESTS FAIL"; exit 1; fi
SH
chmod +x calc.sh test.sh
V1_DEFAULTS="$(cd "$(dirname "$0")" && pwd)/v1-defaults.json"
if [ -f "$V1_DEFAULTS" ]; then
  mkdir -p .vbw-planning/phases
  cp "$V1_DEFAULTS" .vbw-planning/config.json
  printf '# Calc\n\nA tiny calculator.\n' > .vbw-planning/PROJECT.md
  printf 'Phase: 1 of 1 (Calc)\nStatus: in-progress\nProgress: 0%%\n\n## Todos\n' > .vbw-planning/STATE.md
  # v1 finds its plugin root through the marketplace cache. Mirror a real
  # install by linking the assembled plugin there (this script is in
  # <plugin>/evals/<case>/).
  # Only inside `claude plugin eval`, where HOME is the run's own temp home;
  # direct.sh sets VBW_BASELINE_NO_CACHE_LINK so the real ~/.claude is never touched.
  if [ -z "${VBW_BASELINE_NO_CACHE_LINK:-}" ]; then
    plugin_root="$(cd "$(dirname "$0")/../.." && pwd)"
    cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw"
    mkdir -p "$cache" && ln -sfn "$plugin_root" "$cache/local"
  fi
fi
git add -A && git commit -q -m "chore: seed calc fixture"
