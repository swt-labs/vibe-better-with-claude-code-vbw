#!/usr/bin/env bash
# Known-correct solution, applied in the workspace.
set -euo pipefail
sed 's/\$1 - \$2/$1 + $2/' calc.sh > calc.sh.new && mv calc.sh.new calc.sh && chmod +x calc.sh
