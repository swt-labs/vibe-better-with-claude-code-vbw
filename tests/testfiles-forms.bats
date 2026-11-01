#!/usr/bin/env bats
# Named test file forms are their own requirement area (#735), apart from the
# single form of testfiles-form.bats, testfiles-spec.bats and prove-testfiles.bats.
# #735 (docs/proof.md, Test files): several named single-file forms, one per test
# runner. Each form's files run with its own run argv, in the form's dir when it
# has one ({file} is then the path relative to that dir); a change reruns only the
# files that read it, whatever their form; the summary and the evidence name the
# forms; a form that matches nothing fails the test command naming the form. One
# unnamed form without a dir keeps its fingerprint and its record shape. L1.

load helper
load fixture-helper

setup_file() { fixture_build forms forms_project; }
setup() { fixture_copy forms; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

sha() { if command -v sha256sum > /dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }

# forms_project: two subprojects, each with a runner that logs "<its folder> <its argument>"
# and runs the test file it is given, relative to its own folder; built once per file.
forms_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  local p
  for p in web mob; do
    mkdir -p "apps/$p/src" "apps/$p/tests"
    printf '%s\n' "$p" > "apps/$p/src/main.txt"
    printf 'printf "%%s %%s\\n" "${PWD##*/}" "$1" >> "$RANLOG"\nsh "$1"\n' > "apps/$p/run.sh"
    printf 'grep -q . src/main.txt\n[ ! -e "$TEST_ROOT/fail_%s" ]\n' "$p" > "apps/$p/tests/t_one.sh"
  done
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- web:\n  - dir: apps/web\n  - run: sh run.sh {file}\n  - files: apps/web/tests/*.sh\n- mob:\n  - dir: apps/mob\n  - run: sh run.sh {file}\n  - files: apps/mob/tests/*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'true\n' > check.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","check.sh"], files:["check.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["apps/web/src/main.txt"], after:[], status:"done"}]
    | .protected = ["check.sh"] | .schema = ([.schema, 4] | max)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  APPROVE_OUTPUT=$("$VBW" approve)
  run "$VBW" prove < /dev/null
  FIRST_STATUS=$status FIRST_OUTPUT=$output FIRST_RAN=$(sort "$RANLOG" | tr '\n' ',')
  : > "$RANLOG"
}

@test "#735: approve names each form with its dir" {
  [[ "$APPROVE_OUTPUT" == *"approved test file form: web: sh run.sh {file} (files apps/web/tests/*.sh, in apps/web/)"* ]] || { echo "$APPROVE_OUTPUT"; false; }
  [[ "$APPROVE_OUTPUT" == *"approved test file form: mob: sh run.sh {file} (files apps/mob/tests/*.sh, in apps/mob/)"* ]] || { echo "$APPROVE_OUTPUT"; false; }
  run "$VBW" show contract
  [[ "$output" == *"test file form web (in apps/web/): sh run.sh {file}"* ]] || { echo "$output"; false; }
}

@test "#735: each form's files run with its own argv, in its dir, with {file} relative to it" {
  [ "$FIRST_STATUS" -eq 0 ] || { echo "$FIRST_OUTPUT"; false; }
  [ "$FIRST_RAN" = "mob tests/t_one.sh,web tests/t_one.sh," ] || { echo "ran: $FIRST_RAN"; false; }
  jq -e '.evidence.test_files | (.["apps/web/tests/t_one.sh"].form == "web") and (.["apps/mob/tests/t_one.sh"].form == "mob")' .vbw/record.json
  jq -e '.evidence.commands.test | .of_files and (.command == "web: sh run.sh {file}; mob: sh run.sh {file} (one test file per run)")' .vbw/record.json
  [[ "$FIRST_OUTPUT" == *"test files: 2 ran, 0 reused (mob 1 ran, 0 reused; web 1 ran, 0 reused)"* ]] || { echo "$FIRST_OUTPUT"; false; }
}

@test "#735: a change in one subproject reruns only the files that read it" {
  printf 'more\n' >> apps/web/src/main.txt
  git add apps/web/src/main.txt && git commit -q -m "feat: web"
  run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sort "$RANLOG" | tr '\n' ',')" = "web tests/t_one.sh," ] || { cat "$RANLOG"; echo "$output"; false; }
  [[ "$output" == *"(mob 0 ran, 1 reused; web 1 ran, 0 reused)"* ]] || { echo "$output"; false; }
}

@test "#735: a form that matches no tracked file fails the test command, naming the form" {
  printf -- '- gone:\n  - dir: apps/gone\n  - run: sh run.sh {file}\n  - files: apps/gone/tests/*.sh\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(vbw): gone"
  "$VBW" approve > /dev/null
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  jq -e '.evidence.commands.test | .status == "fail" and (.tail | contains("test file form gone matches no tracked file (apps/gone/tests/*.sh)"))' .vbw/record.json
}

@test "#735: a unit whose folder is missing from the copy fails naming the folder, and runs nothing" {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/checks.sh"; mkdir -p "$VBW_RUNTIME"; CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX")
    checks_run_units '"'"'[{"name": "u", "out": "u.out", "argv": ["sh", "-c", "echo ran >> \"$RANLOG\""], "timeout": 30, "exit": 0, "output": "", "alone": false, "dir": "apps/nope"}]'"'"' > "$TEST_ROOT/u.json"'
  jq -e '.u.status == "fail" and (.u.tail | contains("the folder apps/nope/ (the dir of the test file form) is not in the commit"))' "$TEST_ROOT/u.json"
  [ ! -s "$RANLOG" ]
}

@test "#735: a unit whose folder leads outside the copy through a link fails naming the folder, and runs nothing" {
  ln -s ../.. apps/out
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/checks.sh"; mkdir -p "$VBW_RUNTIME"; CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX")
    checks_run_units '"'"'[{"name": "u", "out": "u.out", "argv": ["sh", "-c", "echo ran >> \"$RANLOG\""], "timeout": 30, "exit": 0, "output": "", "alone": false, "dir": "apps/out"}]'"'"' > "$TEST_ROOT/u.json"'
  jq -e '.u.status == "fail" and (.u.tail | contains("the folder apps/out/ (the dir of the test file form) leads outside the clean copy"))' "$TEST_ROOT/u.json" \
    || { jq . "$TEST_ROOT/u.json"; false; }
  [ ! -s "$RANLOG" ]
}

@test "#735: a file two forms match, committed after the forms were synced, fails the test command naming it and both forms" {
  printf -- '- extra:\n  - run: sh {file}\n  - files: apps/web/tests/x_*.sh\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(vbw): extra"
  "$VBW" approve > /dev/null
  printf 'true\n' > apps/web/tests/x_one.sh
  git add apps/web/tests/x_one.sh && git commit -q -m "test: x"
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  jq -e '.evidence.commands.test | .status == "fail" and (.tail | contains("apps/web/tests/x_one.sh is matched by forms web and extra"))' .vbw/record.json \
    || { jq .evidence.commands.test .vbw/record.json; false; }
}

@test "#735: one unnamed form without a dir keeps its fingerprint; a dir is part of a form's fingerprint" {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/proofreuse.sh"
    old=$(jq -c ".test_files = {run: [\"sh\", \"{file}\"], files: [\"tests/*.sh\"]} | .settings.command_timeout = 60" "$VBW_RECORD")
    printf "%s\n" "$(proofreuse_fp_of "$old" file:tests/t.sh)" > "$TEST_ROOT/fp"
    PROOFREUSE_TFMAP="{\"apps/web/tests/t_one.sh\": 0}"
    printf "%s\n" "$(proofreuse_fp_of "$(cat "$VBW_RECORD")" file:apps/web/tests/t_one.sh)" >> "$TEST_ROOT/fp"'
  [ "$(sed -n 1p "$TEST_ROOT/fp")" = "$(printf '60\0sh\0tests/t.sh\0' | sha)" ]
  [ "$(sed -n 2p "$TEST_ROOT/fp")" = "$(printf '3600\0dir:apps/web\0sh\0run.sh\0tests/t_one.sh\0' | sha)" ]
}

@test "#735: vbw fix done reruns the failed file of its form, in that form's dir, and reuses the other form's" {
  : > "$TEST_ROOT/fail_web"
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  FIX=$(jq -r '[.fixes[] | select(.command == "test" and .status == "open")][0].id' .vbw/record.json)
  rm -f "$TEST_ROOT/fail_web"
  : > "$RANLOG"
  run "$VBW" fix done "$FIX"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sort "$RANLOG" | tr '\n' ',')" = "web tests/t_one.sh," ] || { cat "$RANLOG"; echo "$output"; false; }
}

@test "#735: the stored legacy form keeps its approval hash, and adding a form needs a new approval" {
  printf '%s' '{"test_files": {"run": ["sh", "{file}"], "files": ["tests/*.sh"]}}' > "$TEST_ROOT/legacy.json"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  [ "$(vbw_kernel 'test_files_hash "$(cat "$TEST_ROOT/legacy.json")"')" = "$(printf '%s\n' '{"files":["tests/*.sh"],"run":["sh","{file}"]}' | sha)" ]
  printf -- '- more:\n  - run: sh {file}\n  - files: more/*.sh\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  run "$VBW" show contract
  [[ "$output" == *"NOT APPROVED"* ]] || { echo "$output"; false; }
  run "$VBW" show contract --changes
  [[ "$output" == *"added test file form more: sh {file} (files more/*.sh)"* ]] || { echo "$output"; false; }
}
