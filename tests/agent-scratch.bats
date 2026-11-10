#!/usr/bin/env bats
# R177 (docs/guards.md, D300): agents have one scratch folder inside the
# project, .vbw/runtime/scratch/, and every text that tells them where to write
# names that same folder: the guard's refusal, the Dev and Lead briefs and the
# guards documentation; the briefs never send an agent to /tmp. The Lead brief
# keeps its dependency rule on `after` (QA finding F136). L1.

load helper

SCRATCH='.vbw/runtime/scratch/'

@test "R177: the refusal's advice, the Dev brief, the Lead brief and docs/guards.md name the one scratch folder" {
  grep -qF "put scratch work in $SCRATCH" "$PLUGIN_ROOT/hooks/common.jq"
  grep -qF "$SCRATCH" "$PLUGIN_ROOT/agents/dev.md"
  grep -qF "$SCRATCH" "$PLUGIN_ROOT/agents/lead.md"
  grep -qF "$SCRATCH" "$PLUGIN_ROOT/../docs/guards.md"
}

@test "R177: no brief and no refusal sends an agent to /tmp or to .vbw/runtime/ itself" {
  ! grep -En 'go in `\.vbw/runtime/`|scratch work in \.vbw/runtime/"' "$PLUGIN_ROOT/agents/dev.md" "$PLUGIN_ROOT/agents/lead.md" "$PLUGIN_ROOT/hooks/common.jq" || false
  grep -qF 'never `/tmp`' "$PLUGIN_ROOT/agents/dev.md"
  grep -qF 'never `/tmp`' "$PLUGIN_ROOT/agents/lead.md"
}

@test "R177 (F136): the Lead brief keeps its dependency rule on after" {
  grep -qF '`after`' "$PLUGIN_ROOT/agents/lead.md"
}

# R290 (field report 2026-11-09, D685): a Dev's write under .vbw/runtime/ but outside
# .vbw/runtime/scratch/, outside its plan's files, is refused with a Next that names
# .vbw/runtime/scratch/ as the place for scratch files, never the replan advice; a write
# under the scratch folder still passes, and any other path outside the plan's files keeps
# today's answer. L1: the hooks.json commands of a build run's Dev.
load fixture-helper

leased() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  [ -z "$(git status --porcelain)" ] || { git add -A && git commit -q -m "feat(shop): start"; }
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
}
setup_file() { fixture_build leased leased; }
teardown_file() { fixture_teardown; }

dev_write() {
  jq -nc --arg d "$PROJECT" --arg p "$1" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Write", cwd: $d, agent_id: "a1", agent_type: "vbw:dev", tool_input: {file_path: $p, content: "x"}}' \
    | vbw_hook PreToolUse Write
}
dev_bash() {
  jq -nc --arg d "$PROJECT" --arg c "$1" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", cwd: $d, agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash
}
reason_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2> /dev/null; }

@test "R290: a Dev's write under .vbw/runtime/ outside the scratch folder is refused with a Next naming .vbw/runtime/scratch/, never a replan" {
  fixture_copy leased
  local out r
  for out in "$(dev_write .vbw/runtime/scratch_mut.out)" "$(dev_bash 'vbw mutate P1.1 --run > .vbw/runtime/scratch_mut.out')"; do
    r=$(reason_of "$out")
    [ -n "$r" ] || { echo "not refused: $out"; false; }
    printf '%s\n' "$r" | grep -E '^Next:' | grep -qF '.vbw/runtime/scratch/' || { echo "the Next does not name the scratch folder: $r"; false; }
    [[ "$r" != *"replanned"* && "$r" != *"vbw apply"* ]] || { echo "the refusal still advises a replan: $r"; false; }
  done
}

@test "R290: under the scratch folder a Dev's write still passes; another path outside the plan's files keeps the replan answer; the glance keeps its own" {
  fixture_copy leased
  local out
  out=$(dev_write .vbw/runtime/scratch/mut.out)
  [ -z "$out" ] || { echo "a scratch write was refused: $out"; false; }
  out=$(dev_write src/other.txt)
  [[ "$(reason_of "$out")" == *"report that the plan needs it, so the plan can be replanned with vbw apply"* ]] || { echo "$out"; false; }
  out=$(dev_write .vbw/runtime/glance.json)
  [[ "$(reason_of "$out")" == *"glance.json is written only by vbw"* ]] || { echo "$out"; false; }
}
