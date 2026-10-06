---
name: vbw-release
description: Release a new VBW version - tests on both shells, the real-user scenarios, the version bump and changelog, CI, and publishing only on the owner's word.
---

# Releasing VBW

Every step runs; a failure stops the release until its root cause is fixed.

1. **Tests:** `bash tools/test.sh` (bash 5), then the same suite under macOS
   `/bin/bash` 3.2, then on Linux with `bash tools/test-linux.sh` (Docker). Both must pass in full; the hook benchmark must be within
   budget on an idle machine.
2. **Real-user scenarios:** `bash tools/l3-suite.sh [SCENARIO...]` (the real
   Claude Code TUI, driven as a user, 4 at a time; about $1-3 per scenario).
   Run `greenfield` plus every scenario that exercises what the release
   changed; the milestone already ran its own scenarios while it was built.
   Run the full suite before the 2.1 launch. Until 2.1 (owner decision D140:
   the owner is the only user) a release that changes the core `/vbw:vibe` loop
   runs only those scenarios too. The release record names
   the scenarios run and those not run. Every check must pass.
3. **Version:** `bash tools/bump-version.sh --set X.Y.Z` (all five version files),
   then a `plugin/CHANGELOG.md` entry written for users: what they can do now,
   what was fixed, anything they must do. Every build a user is meant to receive
   gets a new version: Claude Code updates a plugin only when its version changes.
4. **Claude Code changes:** read the Claude Code changelog for every version
   since the last release and check what touches plugins, hooks, mods, skills,
   the status line or settings (a maintainer step, never part of VBW).
5. **Docs:** `README.md` and `docs/` match what was built (commands, settings,
   requirements).
6. **Publish, only on the owner's word:** push the branch; wait for CI (macOS
   bash 3.2, Linux bash 5, manifest validation) to be green.
7. **Verify the update path:** in a throwaway `CLAUDE_CONFIG_DIR`, install the
   previous release, then update with `claude plugin marketplace update` and
   `claude plugin update`; the new version must be installed and load.
8. **Record** the release in the progress log with its evidence levels and a
   Not tested list.
