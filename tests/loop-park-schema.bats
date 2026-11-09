#!/usr/bin/env bats
# T153 (D399): a park never leaves the record unreadable. When the item's own
# commits changed the kernel that reads the record (VBW built with VBW: the
# kernel lives in the project), the park removes the item's work from the record
# before it reverts those commits, so the kernel the reverts bring back still
# reads the record; the reverts and the decision naming them are recorded after.
# 2026-10-14 23:43: the reverts ran first, the restored validator refused a
# field of the item's plans, and the project was left with 22 reverts and an
# unreadable record. L1: the project carries its own copy of the kernel.

load helper
load loop-helper

setup() { loop_project; }
teardown() { vbw_teardown; }

@test "T153: parking an item whose commits changed the record's validator leaves a record the restored kernel reads" {
  cp -R "$PLUGIN_ROOT" kplug
  git add kplug && git commit -qm "chore: the project's own kernel"
  VBW="$PWD/kplug/bin/vbw"
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 50 > /dev/null
  [ "$(loop_next s1 | jq -r .action)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  # The item's own work: the kernel learns a new plan field, and the item's plan carries it.
  # The plan rule's key list, whatever keys follow "awaits" (a later field must not break the edit).
  perl -pi -e 's/("amendments","awaits"[^\]]*)\]/$1,"probe"]/' kplug/lib/record.jq
  grep -q '"probe"' kplug/lib/record.jq
  git commit -qm "feat(kernel): plans may carry a probe" -- kplug/lib/record.jq
  edit_record '(.plans[] | select(.id == "P2.1")).probe = 1'
  git commit -qm "chore(vbw): record with a probe" -- .vbw/record.json
  "$VBW" status > /dev/null
  run env VBW_SESSION_ID=s1 "$VBW" loop park "a test park"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The kernel is back as before the item, and it reads the record.
  ! grep -q '"probe"' kplug/lib/record.jq || false
  run "$VBW" status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.loop.items[0].status == "parked" and (.loop.items[0].reverts | length) >= 1
    and ([.plans[] | select(.id == "P2.1")] | length) == 0' .vbw/record.json || { jq '{loop, plans}' .vbw/record.json; false; }
  jq -e '[.decisions[] | select(.text | test("Parked T1"))] | last | .text | test("[0-9a-f]{7}")' .vbw/record.json || { jq '.decisions[-2:]' .vbw/record.json; false; }
  [ -z "$(git status --porcelain -- .vbw)" ]
}
