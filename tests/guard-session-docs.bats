#!/usr/bin/env bats
# P225's documentation (D685, D686): R285, the session start's one PATH line in Claude
# Code's per-session env file, named as an exception to 'Nothing outside the project' in
# AGENTS.md and CLAUDE.md (the same rulebook) and doctor's comparison with the copy the
# session loaded in docs/diagnostics.md; R289, the record protected by its resolved path,
# and R290, the scratch folder named in a Dev's refusal, in docs/guards.md. L1: the docs alone.

load helper

@test "R285 docs: AGENTS.md and CLAUDE.md name the session's env file as an exception, with R285; docs/diagnostics.md says doctor compares the vbw on PATH with the copy this session loaded" {
  local f line
  for f in AGENTS.md CLAUDE.md; do
    line=$(grep 'Nothing outside the project' "$REPO_ROOT/$f")
    [[ "$line" == *"Four exceptions"* && "$line" == *"CLAUDE_ENV_FILE"* && "$line" == *"R285"* ]] || { echo "$f: $line"; false; }
  done
  grep -qiE 'copy (Claude Code|this session) loaded' "$REPO_ROOT/docs/diagnostics.md" || { echo "docs/diagnostics.md does not say doctor compares with the copy the session loaded"; false; }
  grep -qiE 'start or resume the session' "$REPO_ROOT/docs/diagnostics.md" || { echo "docs/diagnostics.md does not give the fix"; false; }
}

@test "R289 docs: docs/guards.md says the record is protected by its resolved path, and another folder's .vbw/record.json is not" {
  grep -qiE 'resolved path' "$REPO_ROOT/docs/guards.md" || { echo "docs/guards.md does not say the record is judged by its resolved path"; false; }
  grep -qiE 'another folder|other folder' "$REPO_ROOT/docs/guards.md" || { echo "docs/guards.md does not say another folder's record is not protected"; false; }
}

@test "R290 docs: docs/guards.md says a Dev's write under .vbw/runtime/ outside the scratch folder is refused with the scratch folder named" {
  grep -E '\.vbw/runtime/' "$REPO_ROOT/docs/guards.md" | grep -qiE 'scratch' || { echo "no line of docs/guards.md names the scratch folder for runtime writes"; false; }
  grep -qiE 'outside (the|its) scratch folder|not under \.vbw/runtime/scratch' "$REPO_ROOT/docs/guards.md" || { echo "docs/guards.md does not describe the refusal of a runtime write outside the scratch folder"; false; }
}
