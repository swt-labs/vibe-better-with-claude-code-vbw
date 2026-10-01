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

@test "agents have a name matching the file, a single-line description and a tool list" {
  local f name
  while IFS= read -r f; do
    name=$(basename "$f" .md)
    [ "$(sed -n 1p "$f")" = "---" ]
    grep -qx "name: $name" "$f" || { echo "name is not $name: $f"; false; }
    grep -qE '^description: .{20,}$' "$f" || { echo "description missing or empty: $f"; false; }
    grep -qE '^tools: [A-Z]' "$f" || { echo "tools missing: $f"; false; }
  done < <(agents)
}

@test "agents stay within their size budget (about 1.5k tokens)" {
  local f words
  while IFS= read -r f; do
    words=$(wc -w < "$f")
    [ "$words" -le 900 ] || { echo "$f has $words words"; false; }
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

@test "no workflow shares its name with a skill (/vbw:NAME would start the workflow)" {
  local f n
  while IFS= read -r f; do
    n=$(basename "$f" .js)
    [ ! -d "$PLUGIN_ROOT/skills/$n" ] || { echo "workflow $n has the name of the skill /vbw:$n"; false; }
  done < <(workflows)
}
