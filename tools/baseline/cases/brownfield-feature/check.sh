#!/usr/bin/env bash
# Deterministic post-run check: done N works, bad N errors, old behavior and test intact.
set -euo pipefail
./test.sh | grep -qx 'TESTS PASS'
TODO_FILE="$(mktemp)"; export TODO_FILE; rm -f "$TODO_FILE"
trap 'rm -f "$TODO_FILE" "$TODO_FILE.new"' EXIT
./todo.sh add "one"; ./todo.sh add "two"
./todo.sh "done" 2
[ "$(./todo.sh list)" = "$(printf '1. [ ] one\n2. [x] two')" ]
if ./todo.sh "done" 9 2> /dev/null; then exit 1; fi
if ./todo.sh "done" 0 2> /dev/null; then exit 1; fi
[ "$(./todo.sh list)" = "$(printf '1. [ ] one\n2. [x] two')" ]
