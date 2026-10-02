#!/usr/bin/env bash
# Deterministic post-run check: the check was not edited and now passes.
set -euo pipefail
git diff --quiet HEAD -- check-slug.sh
./check-slug.sh | grep -qx 'CHECK PASS'
