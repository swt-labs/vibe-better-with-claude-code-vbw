#!/usr/bin/env bats
# R261 (T241; docs/packs.md): the first stack pack, Rust. plugin/packs/rust/ holds a
# small manifest (the pack's name and the file patterns that select it) and one text
# per role (lead, dev, qa). A plan whose files match the patterns has its pack named in
# the answer of vbw next --json (packs.plans), a phase gets the packs of its plans
# (packs.phases) and the project the packs its tracked files match (packs.project, for
# the Lead at planning, when plans do not exist yet); the workflows hand each agent the
# path of its role text under packs_root, since they read no files themselves. A project
# with no match pays nothing: no packs key, no packs_root, and no more jq processes than
# a plugin tree without any pack. A pack is outside the contract and the record. Adding
# a stack is one more folder. Packs are not agents. L1: the kernel on fixture projects,
# plus a copied plugin tree with an extra pack and with an edited pack.

load helper
load fixture-helper

# rust_project: a shop with a Rust plan (P1.1) and a Python plan (P1.2), both ready to build.
rust_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests
  printf 'exit 0\n' > tests/pay.sh
  printf 'exit 0\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "express"},
                    {id: "P2", title: "Receipt", reqs: ["R2"], goal: "receipt", criteria: ["sends"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["crates/pay/Cargo.toml", "crates/pay/src/lib.rs"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["tool.py"], after: [], role: "dev", tasks: ["send"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}, {req: "R2", text: "sent is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

# plain_project: the same shop with no Rust anywhere (P1.1 builds C files).
plain_project() {
  rust_project
  jq '.plans[0].files = ["src/pay.c", "Makefile"]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "chore(vbw): no rust"
  "$VBW" approve > /dev/null
}

# plug_tree: a copy of the plugin at $TEST_ROOT/plug with an extra pack "python" (*.py), and
# a second copy at $TEST_ROOT/nopacks without any pack folder.
plug_tree() {
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plug"
  mkdir -p "$TEST_ROOT/plug/packs/python"
  printf '{"name": "python", "patterns": ["*.py"]}\n' > "$TEST_ROOT/plug/packs/python/pack.json"
  printf 'Python for the Lead.\n' > "$TEST_ROOT/plug/packs/python/lead.md"
  printf 'Python for the Dev.\n' > "$TEST_ROOT/plug/packs/python/dev.md"
  printf 'Python for QA.\n' > "$TEST_ROOT/plug/packs/python/qa.md"
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/nopacks"
  rm -rf "$TEST_ROOT/nopacks/packs"
}

setup_file() {
  fixture_build rust rust_project
  fixture_build plain plain_project
}
setup() {
  fixture_copy rust
  PACKS="$PLUGIN_ROOT/packs"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

next_json() { "$VBW" next --json < /dev/null; }
# role_names CONTENT_REGEX...: every role text of the Rust pack matches each regex.
role_names() {
  local role re
  for role in lead dev qa; do
    for re in "$@"; do
      grep -qiE -- "$re" "$PACKS/rust/$role.md" || { echo "packs/rust/$role.md does not name: $re"; return 1; }
    done
  done
}

@test "R261 folder: plugin/packs/rust holds a manifest with the pack's name and its two patterns, and one text per role" {
  [ -d "$PACKS/rust" ] || { echo "no plugin/packs/rust"; false; }
  jq -e '(keys | sort) == ["name", "patterns"] and .name == "rust" and .patterns == ["Cargo.toml", "*.rs"]' "$PACKS/rust/pack.json" \
    || { cat "$PACKS/rust/pack.json"; false; }
  local role
  for role in lead dev qa; do
    [ -s "$PACKS/rust/$role.md" ] || { echo "no plugin/packs/rust/$role.md"; false; }
  done
  [ "$(ls "$PACKS/rust" | LC_ALL=C sort | tr '\n' ' ')" = "dev.md lead.md pack.json qa.md " ] || { ls "$PACKS/rust"; false; }
}

@test "R261 folder: each role text carries the four first contents and the path rule" {
  # 1. a test target written ahead of its code: test = false in Cargo.toml, --test NAME still red, removed once it compiles
  role_names 'test = false' '--test' 'compiles'
  # 2. a dependency added to a crate updates every path-dependent workspace's Cargo.lock in the same commit
  role_names 'Cargo\.lock' 'same commit'
  # 3. one crate with -j 2; the whole workspace only as a check marked alone
  role_names '-j 2' 'alone'
  # 4. a behaviour change re-pins baselines, generated pages and digests in the same change
  role_names 'baseline' 'digest'
  # the path rule: paths in a nested workspace are written from the project root
  role_names 'project root'
}

@test "R261 folder: packs are not agents: plugin/agents still holds the seven agents and the pack folder holds no agent file" {
  [ "$(ls "$PLUGIN_ROOT/agents" | wc -l | tr -d ' ')" -eq 7 ]
  ! grep -rlE '^(name|tools|model):' "$PACKS" > /dev/null 2>&1 || { echo "a pack file carries agent frontmatter"; false; }
}

@test "R261 next: a plan whose files match the patterns has its pack named in vbw next --json, a Python plan in the same wave has none, and the phases and the project are named too" {
  run next_json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "build" and (.detail.plans | sort) == ["P1.1", "P2.1"]' > /dev/null || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.packs.plans == {"P1.1": ["rust"]} and .packs.phases == {"P1": ["rust"]} and .packs.project == ["rust"]' > /dev/null \
    || { echo "packs: $(printf '%s' "$output" | jq -c .packs)"; false; }
  [ "$(printf '%s' "$output" | jq -r '.packs_root')" = "$PACKS" ] || { echo "packs_root: $(printf '%s' "$output" | jq -r '.packs_root')"; false; }
}

@test "R261 next: a project with no Rust pays nothing: no packs key, no packs_root, and no more jq processes than a plugin tree without any pack" {
  fixture_copy plain
  run next_json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "build" and (has("packs") | not) and (has("packs_root") | not)' > /dev/null || { echo "$output"; false; }
  plug_tree
  mkdir -p "$TEST_ROOT/shim"
  printf '#!/bin/sh\necho jq >> "$JQLOG"\nexec "%s" "$@"\n' "$(command -v jq)" > "$TEST_ROOT/shim/jq"
  chmod +x "$TEST_ROOT/shim/jq"
  export JQLOG="$TEST_ROOT/jq.log"
  : > "$JQLOG"
  PATH="$TEST_ROOT/shim:$PATH" "$TEST_ROOT/plug/bin/vbw" next --json < /dev/null > /dev/null
  local with without
  with=$(wc -l < "$JQLOG" | tr -d ' ')
  : > "$JQLOG"
  PATH="$TEST_ROOT/shim:$PATH" "$TEST_ROOT/nopacks/bin/vbw" next --json < /dev/null > /dev/null
  without=$(wc -l < "$JQLOG" | tr -d ' ')
  [ "$with" -gt 0 ] && [ "$with" -eq "$without" ] || { echo "vbw next --json ran jq $with times with packs and $without times without any pack folder"; false; }
}

@test "R261 next: the Lead's pack comes from the project's tracked files: a tracked Cargo.toml selects it at the plan step, an untracked one does not" {
  jq '.phases = [] | .plans = [] | .checks = [] | .protected = [] | del(.requirements[].rules)' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  printf '[package]\nname = "pay"\n' > Cargo.toml
  run next_json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "plan" and (has("packs") | not)' > /dev/null || { echo "an untracked Cargo.toml selected a pack: $output"; false; }
  git add Cargo.toml && git commit -q -m "chore: cargo"
  run next_json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "plan" and .packs.project == ["rust"] and ((.packs.plans // {}) | length) == 0' > /dev/null || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | jq -r '.packs_root')" = "$PACKS" ]
}

@test "R261 next: adding a stack is one more folder: a plugin tree with an extra pack gives a .py plan that pack without any code change" {
  plug_tree
  run "$TEST_ROOT/plug/bin/vbw" next --json < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.packs.plans == {"P1.1": ["rust"], "P2.1": ["python"]} and .packs.phases == {"P1": ["rust"], "P2": ["python"]}
    and (.packs.project | sort) == ["python", "rust"]' > /dev/null || { echo "packs: $(printf '%s' "$output" | jq -c .packs)"; false; }
  [ "$(printf '%s' "$output" | jq -r '.packs_root')" = "$TEST_ROOT/plug/packs" ]
}

@test "R261 next: a pack is outside the contract and the record: editing a pack file changes no contract hash, un-approves no plan and adds no key to the record" {
  plug_tree
  [ -f "$TEST_ROOT/plug/packs/rust/dev.md" ] || { echo "no plugin/packs/rust/dev.md to edit"; false; }
  local before after schema
  before=$("$TEST_ROOT/plug/bin/vbw" show contract < /dev/null | head -n 1)
  [[ "$before" == *"(approved)"* ]] || { echo "$before"; false; }
  printf '\nEdited for the test.\n' >> "$TEST_ROOT/plug/packs/rust/dev.md"
  printf '{"name": "rust", "patterns": ["Cargo.toml", "*.rs", "build.rs"]}\n' > "$TEST_ROOT/plug/packs/rust/pack.json"
  after=$("$TEST_ROOT/plug/bin/vbw" show contract < /dev/null | head -n 1)
  [ "$before" = "$after" ] || { echo "before: $before"; echo "after:  $after"; false; }
  schema=$(jq '.schema' .vbw/record.json)
  "$TEST_ROOT/plug/bin/vbw" decide "Use blue buttons" "the owner prefers them" < /dev/null > /dev/null
  [ "$(jq '.schema' .vbw/record.json)" = "$schema" ] || { echo "the schema moved from $schema to $(jq '.schema' .vbw/record.json)"; false; }
  jq -e '[.. | objects | keys[]] | map(select(test("pack"; "i"))) == []' .vbw/record.json || { echo "the record names a pack"; false; }
  [[ "$("$TEST_ROOT/plug/bin/vbw" show contract < /dev/null | head -n 1)" == *"(approved)"* ]]
}

@test "R261 workflow: the build workflow hands a Dev its pack's dev text by path, only for a plan that has one; verify hands QA the qa text; planning hands the Lead the lead text" {
  local b="$PLUGIN_ROOT/workflows/building.js" v="$PLUGIN_ROOT/workflows/verifying.js" p="$PLUGIN_ROOT/workflows/planning.js"
  grep -q 'packs' "$b" && grep -q 'packs_root' "$b" && grep -q 'dev\.md' "$b" || { echo "building.js does not pass the pack's dev text"; false; }
  grep -q 'packs' "$v" && grep -q 'packs_root' "$v" && grep -q 'qa\.md' "$v" || { echo "verifying.js does not pass the pack's qa text"; false; }
  grep -q 'packs' "$p" && grep -q 'packs_root' "$p" && grep -q 'lead\.md' "$p" || { echo "planning.js does not pass the pack's lead text"; false; }
  # The Dev's prompt gains the pack note only when args.packs.plans names the plan: the note is
  # computed per plan and is the empty string otherwise, so the Python Dev's prompt is byte-identical to today's.
  grep -qE "packs[^;]*plans[^;]*\\[id\\]" "$b" || { echo "building.js does not look the pack up by the plan's id"; false; }
  grep -qE "(^|[^a-z])(no|without)[^\n]*pack[^\n]*''|: ''" "$b" || { echo "building.js has no empty note for a plan without a pack"; false; }
  # Workflows still read no files themselves.
  ! grep -qE 'readFile|require\(|^import ' "$b" "$v" "$p" || { echo "a workflow reads files"; false; }
  grep -q 'Execute VBW plan ${id}. Start with: vbw show plan ${id}; then ${SINCE(id)}${mutate}' "$b" || { echo "the Dev prompt's start changed"; false; }
  # The router passes the answer's top-level packs and packs_root into every workflow's args, as it does root.
  grep -E 'top-level' "$PLUGIN_ROOT/skills/vibe/SKILL.md" | grep -q 'packs_root' || { echo "the router does not pass packs_root to the workflows"; false; }
}
