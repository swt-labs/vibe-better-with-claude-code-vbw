#!/usr/bin/env bats
# Contract tests for the workflows and agents (docs/workflows.md): the
# structural rules Claude Code's workflow runtime and plugin loader enforce,
# checked without spending a token.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

workflows() { find "$PLUGIN_ROOT/workflows" -name '*.js' | LC_ALL=C sort; }
agents() { find "$PLUGIN_ROOT/agents" -name '*.md' | LC_ALL=C sort; }

@test "the workflows and VBW 1's seven agents exist, and nothing else" {
  local f
  for f in planning building fixing verifying mapping investigating researching; do [ -f "$PLUGIN_ROOT/workflows/$f.js" ]; done
  [ "$(ls "$PLUGIN_ROOT/agents" | LC_ALL=C sort | tr "\n" " ")" = "architect.md debugger.md dev.md docs.md lead.md qa.md scout.md " ]
}

@test "each workflow starts with a pure-literal meta naming itself after its file" {
  local f name
  while IFS= read -r f; do
    [ "$(head -n 1 "$f")" = "export const meta = {" ] || { echo "meta is not the first statement: $f"; false; }
    name=$(basename "$f" .js)
    grep -q "^  name: '$name',$" "$f" || { echo "meta.name is not '$name': $f"; false; }
    grep -q "^  description: '[^']*',$" "$f" || { echo "meta.description missing: $f"; false; }
    # The meta block (up to the first line that is exactly "}") holds only literals.
    awk 'NR > 1 && /^}$/ { exit } NR > 1' "$f" | grep -vqE '\$\{|\.\.\.|\(' || true
    ! awk 'NR > 1 && /^}$/ { exit } NR > 1' "$f" | grep -qE '\$\{|\.\.\.[a-zA-Z]|[a-zA-Z_]\(' \
      || { echo "meta is not a pure literal: $f"; false; }
  done < <(workflows)
}

@test "workflows never use what breaks resume or is unavailable (time, randomness, modules)" {
  local f
  while IFS= read -r f; do
    ! grep -nE 'Date\.now\(|Math\.random\(|new Date\(\)|import\(|require\(' "$f" || { echo "in $f"; false; }
  done < <(workflows)
}

@test "every phase() title is declared in meta.phases" {
  local f t
  while IFS= read -r f; do
    while IFS= read -r t; do
      grep -q "{ title: '$t'" "$f" || { echo "phase('$t') not in meta.phases: $f"; false; }
    done < <(grep -oE "phase\('[^']+'\)" "$f" | sed -E "s/phase\('([^']+)'\)/\1/" | sort -u)
  done < <(workflows)
}

@test "every agentType names an agent this plugin ships" {
  local f a
  while IFS= read -r f; do
    while IFS= read -r a; do
      [ -f "$PLUGIN_ROOT/agents/$a.md" ] || { echo "agentType vbw:$a has no agents/$a.md ($f)"; false; }
    done < <({ grep -oE "agentType: 'vbw:[a-z-]+'" "$f" | sed -E "s/.*vbw:([a-z-]+).*/\1/"
               grep -oE "opts\('[a-z-]+'" "$f" | sed -E "s/opts\('([a-z-]+)'/\1/"; } | sort -u)
  done < <(workflows)
}

@test "agents have a name matching the file, a single-line description and a disallowedTools line (no tools: allowlist)" {
  local f name
  while IFS= read -r f; do
    name=$(basename "$f" .md)
    [ "$(sed -n 1p "$f")" = "---" ]
    grep -qx "name: $name" "$f" || { echo "name is not $name: $f"; false; }
    grep -qE '^description: .{20,}$' "$f" || { echo "description missing or empty: $f"; false; }
    grep -qE '^disallowedTools: [A-Z]' "$f" || { echo "disallowedTools missing: $f"; false; }
    ! grep -q '^tools:' "$f" || { echo "tools: allowlist present: $f"; false; }
  done < <(agents)
}

@test "agents only use vbw commands that exist" {
  local cmd n=0
  while IFS= read -r cmd; do
    n=$((n + 1))
    "$VBW" help | grep -qE "^  $cmd( |$)" || { echo "agents use unknown command: vbw $cmd"; false; }
  done < <(agents | while IFS= read -r f; do grep -oE '`vbw [a-z]+' "$f" || true; done | sed 's/^`vbw //' | sort -u)
  [ "$n" -ge 5 ] || { echo "only $n commands found: the scan is broken"; false; }
}

@test "agents that plan or judge the plan load the user's recorded decisions" {
  local role
  for role in architect lead qa; do
    grep -q '`vbw show decisions`' "$PLUGIN_ROOT/agents/$role.md" || { echo "$role does not load decisions"; false; }
  done
}

@test "workflow scripts parse as JavaScript (when node is available)" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local f body
  while IFS= read -r f; do
    # The runtime runs the body as an async function with these globals.
    body=$(sed 's/^export const meta/const meta/' "$f")
    printf '(async (agent, parallel, pipeline, phase, log, args, budget, workflow) => {\n%s\n})\n' "$body" \
      > "$TEST_ROOT/check.js"
    node --check "$TEST_ROOT/check.js" || { echo "syntax error: $f"; false; }
  done < <(workflows)
}

@test "workflow schemas are objects whose required keys are all properties" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local f
  while IFS= read -r f; do
    sed 's/^export const meta/const meta/' "$f" | awk '/^const [A-Z_]+ = \{$/,/^}$/' > "$TEST_ROOT/schemas.js"
    printf '%s\n' 'for (const [k, s] of Object.entries({PLAN_RESULT: typeof PLAN_RESULT !== "undefined" && PLAN_RESULT, CRITIQUE: typeof CRITIQUE !== "undefined" && CRITIQUE, BUILD_RESULT: typeof BUILD_RESULT !== "undefined" && BUILD_RESULT, FIX_RESULT: typeof FIX_RESULT !== "undefined" && FIX_RESULT})) {' \
      '  if (!s) continue' \
      '  const walk = (x, where) => { if (x && x.type === "object") { for (const r of x.required || []) if (!(r in (x.properties || {}))) throw new Error(where + ": required " + r + " is not a property"); for (const [p, v] of Object.entries(x.properties || {})) walk(v, where + "." + p) } if (x && x.items) walk(x.items, where + "[]") }' \
      '  if (s.type !== "object") throw new Error(k + " root is not an object")' \
      '  walk(s, k)' \
      '}' >> "$TEST_ROOT/schemas.js"
    node "$TEST_ROOT/schemas.js" || { echo "bad schema in $f"; false; }
  done < <(workflows)
}

# Kernel refusals reach the user as written (docs/workflows.md, "Refusals reach the user").
@test "every agent schema requires refused: the kernel refusals the agent saw, a list of strings copied verbatim" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local f names
  while IFS= read -r f; do
    names=$(grep -oE 'schema: [A-Z_]+' "$f" | sed 's/schema: //' | sort -u | tr '\n' ' ')
    [ -n "$names" ] || { echo "no agent schema in $f"; false; }
    sed 's/^export const meta/const meta/' "$f" | awk '/^const [A-Z_]+ = \{$/,/^}$/' > "$TEST_ROOT/schemas.js"
    printf 'for (const k of "%s".trim().split(" ")) {\n' "$names" >> "$TEST_ROOT/schemas.js"
    printf '%s\n' '  const s = eval(k)' \
      '  const r = s && s.properties && s.properties.refused' \
      '  if (!r || r.type !== "array" || !r.items || r.items.type !== "string") throw new Error(k + ": no refused list of strings")' \
      '  if (!(s.required || []).includes("refused")) throw new Error(k + ": refused is not required")' \
      '  if (!/verbatim/.test(String(r.description)) || !/Next:/.test(String(r.description))) throw new Error(k + ": refused does not say verbatim, through its Next: line")' \
      '}' >> "$TEST_ROOT/schemas.js"
    node "$TEST_ROOT/schemas.js" || { echo "in $f"; false; }
  done < <(workflows)
}

@test "every workflow returns refused, even when it stops before any agent, and carries an agent's refusals verbatim, named by the agent's label" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local f out
  while IFS= read -r f; do
    out=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$f" '{}' '{}') || { echo "$f did not run"; false; }
    printf '%s' "$out" | jq -e '.result.refused == []' > /dev/null || { echo "$f: $out"; false; }
  done < <(workflows)
  local said=$'vbw: apply refused: plan P1.1 is started\nNext: put it back as the record has it (vbw show plan P1.1)'
  out=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$PLUGIN_ROOT/workflows/building.js" '{"plans": ["P1.1", "P1.2"]}' \
    "$(jq -nc --arg t "$said" '{"dev P1.1": {status: "done", summary: "s", notes: [], refused: [$t, "  "]}, "dev P1.2": {status: "done", summary: "s", notes: [], refused: []}}')")
  printf '%s' "$out" | jq -e --arg t "$said" '.result.refused == [{by: "dev P1.1", text: $t}]' > /dev/null || { echo "$out"; false; }
  printf '%s' "$out" | jq -e --arg t "$said" '.logs | any(. == "dev P1.1 was refused: " + $t)' > /dev/null || { echo "$out"; false; }
}

@test "every agent of every workflow is told the project folder (args.root), so a session started in a subfolder works there; without it nothing is added" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local f out base said='The project folder is /r/My Project.'
  base='{"requirements": [{"id": "R1", "proof": "auto", "text": "x"}], "plans": ["P1.1"], "groups": [["F1"]], "phases": ["P1"], "question": "q", "stack": "s", "problem": "p", "summary": {"open": [{"id": "R1", "text": "x"}], "todos": [{"id": "T1", "text": "y"}]}, "session": "s"}'
  local any='{"*": {"findings": ["a"], "map": "m", "picks": [], "hypotheses": [], "answer": "a", "confidence": "high", "root_cause": "r", "evidence": "e", "rejected": [], "fix": "f", "unknowns": [], "status": "done", "summary": "s", "files": [], "commit": "c", "regression_test": "t", "notes": [], "verdict": "pass", "checks": [], "refused": []}}'
  while IFS= read -r f; do
    out=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$f" "$(jq -nc --argjson b "$base" '$b + {root: "/r/My Project"}')" "$any") || { echo "$f did not run: $out"; false; }
    printf '%s' "$out" | jq -e --arg s "$said" '(.calls | length) > 0 and all(.calls[]; .prompt | contains($s))' > /dev/null \
      || { echo "$f: $(printf '%s' "$out" | jq -c --arg s "$said" '[.calls[] | {label: .opts.label, told: (.prompt | contains($s))}]')"; false; }
    out=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$f" "$base" "$any") || { echo "$f did not run: $out"; false; }
    printf '%s' "$out" | jq -e 'all(.calls[]; .prompt | contains("The project folder is") | not)' > /dev/null || { echo "$f added a folder without args.root"; false; }
  done < <(workflows)
}

@test "every skill that starts a workflow passes the project folder as args.root: the router from vbw next --json, the others from vbw root" {
  local f n=0
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    grep -q 'Workflow `vbw:\|`vbw:[a-z]*` workflow' "$f" || continue
    n=$((n + 1))
    grep -q '`root`\|"root"' "$f" || { echo "no root in the workflow args of $f"; false; }
    [ "$(basename "$(dirname "$f")")" = vibe ] || grep -q '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" root 2>&1 || true' "$f" || { echo "$f does not read vbw root"; false; }
  done
  [ "$n" -ge 6 ]
}

@test "no workflow shares its name with a skill (/vbw:NAME would start the workflow)" {
  local f n
  while IFS= read -r f; do
    n=$(basename "$f" .js)
    [ ! -d "$PLUGIN_ROOT/skills/$n" ] || { echo "workflow $n has the name of the skill /vbw:$n"; false; }
  done < <(workflows)
}

@test "#707: the map states a test or lint run as a snapshot with its commit and date, and the merge keeps it so and bases no advice on it" {
  local js="$PLUGIN_ROOT/workflows/mapping.js" scout merge
  # Every angle can run the tests (stack, tests, risks), so the rule is in the prompt all scouts share.
  scout=$(grep 'Map this codebase from one angle' "$js")
  printf '%s\n' "$scout" | grep -q 'snapshot' || { echo "the scouts are not told a run result is a snapshot"; false; }
  printf '%s\n' "$scout" | grep -q 'as of' || { echo "the scouts are not asked for the commit and date"; false; }
  merge=$(grep 'Merge these verified findings' "$js")
  printf '%s\n' "$merge" | grep -q 'as of' || { echo "the merge does not keep the commit and date"; false; }
  printf '%s\n' "$merge" | grep -q 'no recommendation' || { echo "the merge lets advice rest on a run result"; false; }
}
