#!/usr/bin/env bash
# check-hook-answers.sh HOOKS_DIR TEST_FILE: every answer a VBW hook can give
# Claude Code is pinned by a test, and no hook can allow (R128).
# On the non-comment lines of each *.jq and *.sh file in HOOKS_DIR it lists the
# answer shapes: a permissionDecision value, a use of the jq `deny` helper, or
# one of the keys updatedInput, additionalContext, systemMessage, decision,
# continue, stopReason, suppressOutput written as an object key. Each
# (file, shape) needs a `@test` line in TEST_FILE whose name gives the file
# name and then the shape. Any hook code that can answer permissionDecision
# "allow" (or decision "approve") fails, whatever tests exist.
set -euo pipefail
[ $# -eq 2 ] || { printf 'usage: check-hook-answers.sh HOOKS_DIR TEST_FILE\n' >&2; exit 2; }
dir="$1"
tests="$2"
[ -d "$dir" ] || { printf 'no hooks directory: %s\n' "$dir" >&2; exit 2; }
[ -f "$tests" ] || { printf 'no test file: %s\n' "$tests" >&2; exit 2; }
status=0
keys='updatedInput|additionalContext|systemMessage|decision|continue|stopReason|suppressOutput'

# pinned FILE SHAPE: a @test line names the file, then the shape.
pinned() {
  awk -v f="$1" -v s="$2" '
    /^@test/ { i = index($0, f); if (i > 0 && index(substr($0, i + length(f)), s) > 0) found = 1 }
    END { exit found ? 0 : 1 }' "$tests"
}

for path in "$dir"/*.jq "$dir"/*.sh; do
  [ -f "$path" ] || continue
  name=$(basename "$path")
  code=$(grep -vE '^[[:space:]]*#' "$path" || true)
  if printf '%s\n' "$code" | grep -Eq 'permissionDecision[^:]*:[[:space:]]*\\?["'\'']?allow|decision[^:]*:[[:space:]]*\\?["'\'']?approve'; then
    printf '%s can answer allow (a hook never answers or allows in the user'\''s place)\n' "$name" >&2
    status=1
  fi
  shapes=$({
    printf '%s\n' "$code" | grep -oE 'permissionDecision"?:[[:space:]]*\\?"[a-z]+' | sed -E 's/.*"//' || true
    printf '%s\n' "$code" | grep -Eq '(^|[^[:alnum:]_.:])deny([^[:alnum:]_:]|$)' && printf 'deny\n' || true
    printf '%s\n' "$code" | grep -oE "(^|[^[:alnum:]_.\$])($keys)\"?[[:space:]]*:" | sed -E 's/^[^[:alpha:]]*//; s/[^[:alnum:]].*//' || true
  } | sort -u)
  for shape in $shapes; do
    [ "$shape" = allow ] && continue
    pinned "$name" "$shape" || { printf '%s answer %s has no @test naming it in %s\n' "$name" "$shape" "$(basename "$tests")" >&2; status=1; }
  done
done
exit "$status"
