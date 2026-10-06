#!/usr/bin/env bats
# R23: a phase whose signals call for a higher tier is never planned below it.
# The kernel computes a floor from the signals; the Architect may submit a tier
# in its phase and the kernel refuses one below the floor and accepts a higher one.

load helper
load rigor-helper

teardown() { vbw_teardown; }

tier_of() { jq -r '.phases[0].tier' .vbw/record.json; }

@test "control: a phase with no risk signals is express" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  [ "$(tier_of)" = express ]
}

@test "a risk path (sign-in, payments, data migration, secrets, deletion, CI) puts a phase at deep" {
  local f
  for f in src/auth/login.js src/payments/charge.js db/migrations/001_users.sql config/secrets.yml src/delete_account.js .github/workflows/ci.yml; do
    rigor_project 1
    rigor_apply "$(rigor_doc 1 "" "$f")" > /dev/null
    [ "$(tier_of)" = deep ] || { echo "$f is $(tier_of)"; false; }
    vbw_teardown
  done
}

@test "a risk named by a requirement counts, not only a path" {
  rigor_project 1
  edit_record '.requirements[0].text = "A visitor can sign in with a password"'
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  [ "$(tier_of)" = deep ]
}

@test "many requirements raise the floor: 2 express, 3 standard, 6 deep" {
  rigor_project 6
  rigor_apply "$(rigor_doc 2 "" src/note.txt)" > /dev/null
  [ "$(tier_of)" = express ]
  rigor_apply "$(rigor_doc 3 "" src/note.txt)" > /dev/null
  [ "$(tier_of)" = standard ]
  rigor_apply "$(rigor_doc 6 "" src/note.txt)" > /dev/null
  [ "$(tier_of)" = deep ]
}

@test "many planned files and a large size raise the floor" {
  rigor_project 1
  edit_record '.commands.test = ["bash", "tools/test.sh"]'
  rigor_apply "$(rigor_doc 1 "" src/a.txt src/b.txt src/c.txt src/d.txt)" > /dev/null
  [ "$(tier_of)" = express ]
  rigor_apply "$(rigor_doc 1 "" src/a.txt src/b.txt src/c.txt src/d.txt src/e.txt)" > /dev/null
  [ "$(tier_of)" = standard ]
  rigor_apply "$(rigor_doc 1 "" src/a.txt src/b.txt src/c.txt src/d.txt src/e.txt src/f.txt src/g.txt src/h.txt src/i.txt src/j.txt)" > /dev/null
  [ "$(tier_of)" = deep ]
  head -c 120000 /dev/zero | tr '\0' 'x' > src/big.txt
  rigor_apply "$(rigor_doc 1 "" src/big.txt)" > /dev/null
  [ "$(tier_of)" = standard ]
  head -c 600000 /dev/zero | tr '\0' 'x' > src/huge.txt
  rigor_apply "$(rigor_doc 1 "" src/huge.txt)" > /dev/null
  [ "$(tier_of)" = deep ]
}

@test "touching files that proven requirements depend on is at least standard" {
  rigor_project 2
  rigor_second_milestone
  edit_record '.commands.test = ["bash", "tools/test.sh"]'
  rigor_apply "$(PH=P2 R0=2 rigor_doc 1 "" src/new.js)" > /dev/null
  [ "$(jq -r '.phases[] | select(.id == "P2") | .tier' .vbw/record.json)" = express ]
  rigor_apply "$(PH=P2 R0=2 rigor_doc 1 "" src/old.js)" > /dev/null
  [ "$(jq -r '.phases[] | select(.id == "P2") | .tier' .vbw/record.json)" = standard ]
  jq -e '.phases[] | select(.id == "P2") | .reasons | any(.[]; . == "breaks: R1")' .vbw/record.json
}

@test "changing existing files with no project test command is at least standard" {
  rigor_project 1
  printf 'x' > src/exists.js
  rigor_apply "$(rigor_doc 1 "" src/exists.js)" > /dev/null
  [ "$(tier_of)" = standard ]
  jq -e '.phases[0].reasons | any(.[]; . == "tests: no project test command")' .vbw/record.json
  edit_record '.commands.test = ["bash", "tools/test.sh"]'
  rigor_apply "$(rigor_doc 1 "" src/exists.js)" > /dev/null
  [ "$(tier_of)" = express ]
}

@test "the kernel refuses an Architect tier below the risk floor, and changes nothing" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  cp .vbw/record.json "$TEST_ROOT/before.json"
  run rigor_apply "$(rigor_doc 1 express src/payments/charge.js)"
  [ "$status" -ne 0 ]
  [[ "$output" == *P1* ]]
  [[ "$output" == *deep* ]]
  run rigor_apply "$(rigor_doc 1 standard src/payments/charge.js)"
  [ "$status" -ne 0 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "the kernel accepts an Architect tier above the floor, and says so in the reasons" {
  rigor_project 3
  run rigor_apply "$(rigor_doc 3 deep src/note.txt)"
  [ "$status" -eq 0 ]
  [ "$(tier_of)" = deep ]
  jq -e '.phases[0].reasons | any(.[]; test("Architect"))' .vbw/record.json
  run rigor_apply "$(rigor_doc 3 standard src/note.txt)"
  [ "$status" -eq 0 ]
  [ "$(tier_of)" = standard ]
  run rigor_apply "$(rigor_doc 3 express src/note.txt)"
  [ "$status" -ne 0 ]
  [ "$(tier_of)" = standard ]
}

@test "an Architect tier that is not a tier is refused with the allowed list" {
  rigor_project 1
  run rigor_apply "$(rigor_doc 1 huge src/note.txt)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"express, standard or deep"* ]]
}
