#!/usr/bin/env bats
# R185: after the fix, the plugindir scenario in tools/l3-suite.sh opens the
# real Claude Code with a VBW release installed and turned on, and the working
# tree loaded with claude --plugin-dir, launched with a PATH that already holds
# the installed release's bin/ (the hardest case: a session started from inside
# another one). It records the vbw the session and an agent it starts resolve
# and their version, the VBW version the status line shows, whether the
# session's first line named the kernel in use, and whether the installed
# copy's hooks ran. Passing means everything is the working tree's. As in
# tests/l3-results.bats, these tests do not run Claude Code (L1): they hold the
# committed result, written by the run, not by a person.

load helper

RESULT="$REPO_ROOT/tools/l3-results/plugindir.json"

@test "R185: the plugindir scenario's committed result is an honest, passing L3 run of two different versions" {
  grep -q '^scenario_plugindir()' "$REPO_ROOT/tools/l3-suite.sh"
  [ -f "$RESULT" ] || {
    echo "the plugindir scenario has not been run after the fix: no result is committed"
    false
  }
  jq -e '.scenario == "plugindir" and .evidence_level == "L3" and .passed == true
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string") and (.not_tested | type == "array" and length > 0)
    # The path is absolute, or masked as ~ or <checkout> by tools/mask-paths.jq (T213).
    and (.facts.tree_root | type == "string" and test("^(/|~/|<checkout>/)"))
    and (.facts.tree_version | type == "string" and length > 0)
    and (.facts.installed_version | type == "string" and length > 0)
    and .facts.tree_version != .facts.installed_version
    and .facts.launch_path_had_installed == true' "$RESULT"
}

@test "R185: the session and an agent it started ran the working tree's vbw, at the working tree's version" {
  [ -f "$RESULT" ] || {
    echo "no result is committed"
    false
  }
  jq -e '(.facts.tree_root + "/bin/vbw") as $k
    | .facts.session_vbw_path == $k and .facts.agent_vbw_path == $k
    and .facts.session_vbw_version == .facts.tree_version' "$RESULT"
}

@test "R185: the status line showed the working tree's version, the first line named the kernel, and the installed copy's hooks did not run" {
  [ -f "$RESULT" ] || {
    echo "no result is committed"
    false
  }
  jq -e '.facts.statusline_version_shown == .facts.tree_version
    and .facts.session_start_names_kernel == true
    and .facts.installed_hooks_ran == false' "$RESULT"
}
