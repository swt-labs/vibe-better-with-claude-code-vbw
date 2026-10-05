---
name: vbw-release
description: Release a new VBW version - tests on both shells, the real-user scenarios, the version bump and changelog, CI, and publishing only on the owner's word.
---

# Releasing VBW

Every step runs; a failure stops the release until its root cause is fixed.

1. **Tests:** `bash tools/test.sh` (bash 5), then the same suite under macOS
   `/bin/bash` 3.2. Both must pass in full; the hook benchmark must be within
   budget on an idle machine.
2. **Real-user scenarios:** `bash tools/l3-suite.sh [SCENARIO...]` (the real
   Claude Code TUI, driven as a user, 4 at a time; about $1-3 per scenario).
   Run `greenfield` plus every scenario that exercises what the release
   changed; the milestone already ran its own scenarios while it was built.
   Run the full suite before the 2.1 launch and when the release changes the
   core `/vbw:vibe` loop (the router or `vbw next`). The release record names
   the scenarios run and those not run. Every check must pass.
3. **Version:** `bash tools/bump-version.sh --set X.Y.Z` (all five version files),
   then a `plugin/CHANGELOG.md` entry written for users: what they can do now,
   what was fixed, anything they must do. Every build a user is meant to receive
   gets a new version: Claude Code updates a plugin only when its version changes.
4. **Docs:** `README.md` and `docs/` match what was built (commands, settings,
   requirements).
5. **Publish, only on the owner's word:** push the branch; wait for CI (macOS
   bash 3.2, Linux bash 5, manifest validation) to be green.
6. **Verify the update path:** in a throwaway `CLAUDE_CONFIG_DIR`, install the
   previous release, then update with `claude plugin marketplace update` and
   `claude plugin update`; the new version must be installed and load.
7. **Record** the release in the progress log with its evidence levels and a
   Not tested list.
