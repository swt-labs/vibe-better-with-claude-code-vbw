#!/usr/bin/env bash
# Known-correct solution: fix the bug, touch nothing else.
set -euo pipefail
sed 's/Helo/Hello/' greet.sh > greet.sh.new && mv greet.sh.new greet.sh && chmod +x greet.sh
