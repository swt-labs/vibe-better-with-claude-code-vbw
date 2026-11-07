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

# R263 (T245; docs/packs.md): the Rust pack's wording fits parallel plans and real
# commands. The Lead is told that a plan names every file it changes in a crate and
# that two plans may share a crate when their file lists have no file in common;
# that a change to Cargo.toml or a lockfile goes in one plan at a time; that a file
# many plans would touch (a module list in lib.rs or mod.rs, a shared enum, a
# manifest, a lockfile) is set up once in an early skeleton plan or split so each
# later plan owns its own module file; and that a later plan needing a dependency
# the skeleton did not add waits (an `after` entry) on the plan that adds it, and
# says so. QA treats a workspace-wide command inside an ordinary check as a finding
# only when it compiles or runs tests; a command that only reads the lockfile or the
# manifest is no finding. Dev, Lead and QA cover a dependency added or moved, one
# reached through a path dependency included. L1: wording pins, one case per sentence.

# lead_states REGEX: plugin/packs/rust/lead.md, folded to one line, matches REGEX (extended, case-insensitive).
lead_states() { tr '\n' ' ' < "$PACKS/rust/lead.md" | grep -Eiq -- "$1" || { echo "packs/rust/lead.md does not state /$1/"; return 1; }; }
qa_states() { tr '\n' ' ' < "$PACKS/rust/qa.md" | grep -Eiq -- "$1" || { echo "packs/rust/qa.md does not state /$1/"; return 1; }; }

@test "R263 lead: a plan names every file it changes in a crate, and two plans may share a crate when their file lists have no file in common; the whole-crate rule is gone" {
  lead_states 'names every file it changes'
  lead_states 'share a crate'
  lead_states 'no file in common'
  ! grep -qi 'whole crate it changes' "$PACKS/rust/lead.md" || { echo "lead.md still gives a plan the whole crate"; false; }
}

@test "R263 lead: a change to Cargo.toml or a lockfile goes in one plan at a time" {
  lead_states '(Cargo\.toml|manifest)[^.]*(Cargo\.lock|lockfile)[^.]*one plan at a time'
}

@test "R263 lead: a file many plans would touch (a module list in lib.rs or mod.rs, a shared enum, a manifest, a lockfile) is set up once in an early skeleton plan or split so each later plan owns its own module file" {
  lead_states 'skeleton'
  lead_states 'lib\.rs'
  lead_states 'mod\.rs'
  lead_states 'enum'
  lead_states 'split[^.]*(own|each)[^.]*module'
}

@test "R263 lead: a later plan that needs a dependency the skeleton did not add waits (an after entry) on the plan that adds it, and the plan says so" {
  lead_states 'dependency[^.]*skeleton[^.]*(did not|does not) (add|cover)[^.]*`after`'
  lead_states '(plan that adds it|adding plan)'
  lead_states '(says so|stated in the plan|states it)'
}

@test "R263 qa: a workspace-wide command inside an ordinary check is a finding only when it compiles or runs tests; a command that only reads the lockfile or the manifest is no finding" {
  qa_states 'workspace-wide command[^.]*only when[^.]*(compiles|runs tests)'
  qa_states 'cargo test'
  qa_states 'cargo (build|check|clippy)'
  qa_states '(cargo metadata|cargo tree|cargo pkgid)[^.]*(no finding|not a finding)'
  qa_states 'lockfile diff'
  ! grep -qE 'A workspace-wide command inside an ordinary check is a finding\.' "$PACKS/rust/qa.md" || { echo "qa.md still calls every workspace-wide command a finding"; false; }
}

@test "R263 all: dev.md, lead.md and qa.md each cover a dependency added or moved between crates, one reached through a path dependency (the other workspace's manifest never names it) included: the Dev commits every affected lockfile, the Lead lists them, QA treats a missing one as a finding" {
  local role
  for role in lead dev qa; do
    tr '\n' ' ' < "$PACKS/rust/$role.md" | grep -Eiq 'added or moved|moved (between|to another|from one) crate' || { echo "packs/rust/$role.md does not cover a moved dependency"; false; }
    tr '\n' ' ' < "$PACKS/rust/$role.md" | grep -Eiq 'path dependency' || { echo "packs/rust/$role.md does not name a path dependency"; false; }
    tr '\n' ' ' < "$PACKS/rust/$role.md" | grep -Eiq 'manifest never names|never names (it|the dependency)|(does|do) not name' || { echo "packs/rust/$role.md does not say the other workspace's manifest never names it"; false; }
  done
  tr '\n' ' ' < "$PACKS/rust/dev.md" | grep -Eiq 'commit[^.]*(every|each) affected (lockfile|Cargo\.lock)' || { echo "dev.md does not tell the Dev to commit every affected lockfile"; false; }
  tr '\n' ' ' < "$PACKS/rust/lead.md" | grep -Eiq 'list[^.]*(lockfile|Cargo\.lock)[^.]*plan' || { echo "lead.md does not tell the Lead to list the lockfiles in the plan"; false; }
  tr '\n' ' ' < "$PACKS/rust/qa.md" | grep -Eiq '(missing|absent|stale)[^.]*(lockfile|Cargo\.lock)[^.]*finding' || { echo "qa.md does not call a missing lockfile a finding"; false; }
}

@test "R271: the express plan step of the router tells the session to read the project's stack pack text for the Lead first, in the planning workflow's words" {
  local skill="$PLUGIN_ROOT/skills/vibe/SKILL.md" express wf
  express=$(awk '/^\*\*plan\*\* with `detail.tier` express/ { p = 1 } /^\*\*plan\*\*:/ { p = 0 } p' "$skill")
  [ -n "$express" ] || { echo "no express plan step in SKILL.md"; false; }
  wf=$(grep -o 'Stack pack text: read .*lead\.md.* first\.' "$PLUGIN_ROOT/workflows/planning.js" | head -n 1)
  [ -n "$wf" ] || { echo "planning.js no longer says 'Stack pack text: read .../lead.md first'"; false; }
  printf '%s' "$express" | grep -q 'Stack pack text: read ' || { echo "the express step does not say 'Stack pack text: read'"; false; }
  printf '%s' "$express" | grep -q '/lead\.md first' || { echo "the express step does not name lead.md first"; false; }
  printf '%s' "$express" | grep -q 'packs_root' || { echo "the express step does not say where the packs are (packs_root)"; false; }
  printf '%s' "$express" | grep -q 'packs\.project' || { echo "the express step does not say which packs apply (packs.project)"; false; }
}
