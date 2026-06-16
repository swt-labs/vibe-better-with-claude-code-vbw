# Task completion checklist

- Run relevant targeted tests for the changed area, then run `bash testing/run-all.sh` before considering work complete.
- Investigate and fix every test/lint failure; do not dismiss failures as pre-existing.
- For behavior changes, update consumer-facing docs in docs/ or README.md when workflows or user-visible behavior change.
- Verify version consistency with `bash scripts/bump-version.sh --verify` when release/version files are touched.
- Before committing, run GitNexus detect_changes to verify affected scope.
- Do not commit directly to main; create a branch/PR for changes.
- Stage files explicitly; never use `git add .`.
- Commit message style: `{type}({scope}): {description}` or existing repo style such as `chore: release vX.Y.Z` for releases.