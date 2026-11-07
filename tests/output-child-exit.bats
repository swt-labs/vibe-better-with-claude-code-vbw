#!/usr/bin/env bats
# A kernel write that waits for a slow reader survives a child of the writer
# exiting meanwhile. macOS /bin/bash 3.2 catches SIGCHLD without SA_RESTART
# (bash 4.2 added it), so there a builtin printf or echo blocked on a full pipe
# (Claude Code's Bash tool, a terminal, bats) fails with EINTR, "write error:
# Interrupted system call", when a child exits, and its text is lost; under
# set -e the command fails (CI, tests/machine-turns.bats, vbw check). A loop fed
# by a process substitution has its producer as a live child the whole time it
# runs. The rule, tools/check-loop-writes.sh: no builtin write in such a loop's
# own shell, and no call there to a function that writes so (the tool finds the
# writer functions in the repository's shell files, R218); vbw_out (core.sh)
# writes from a child of its own, or the producer is piped into the loop. Each
# run below fills the pipe first, so the write waits, and lets a child of the
# writer exit while it does. L1.

load helper
load fixture-helper

# shop: a project with two approved checks; each marks that it ran.
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'touch "$TEST_ROOT/ran.$1"\n' > tests/ok.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/ok.sh","C1"], files:["tests/ok.sh"]},
                 {id:"C2", req:"R1", run:["sh","tests/ok.sh","C2"], files:["tests/ok.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build shop shop; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# wait_for PATH: wait (up to 30 s) until PATH exists.
wait_for() {
  local i
  for ((i = 0; i < 600; i++)); do
    [ ! -e "$1" ] || return 0
    sleep 0.05
  done
  return 1
}

# full_pipe READY CMD...: CMD with its output into a pipe a filler fills first,
# so CMD's writes wait for the reader, which starts once the function READY has
# returned. The output (the filler's NULs removed) goes to $TEST_ROOT/out,
# CMD's exit code to $TEST_ROOT/code and READY's to $TEST_ROOT/ready.
full_pipe() {
  local ready=$1
  shift
  (
    head -c 300000 /dev/zero &
    code=0
    "$@" < /dev/null 2>&1 || code=$?
    printf '%s\n' "$code" > "$TEST_ROOT/code"
    wait
  ) | {
    r=0
    "$ready" || r=$?
    printf '%s\n' "$r" > "$TEST_ROOT/ready"
    tr -d '\000' > "$TEST_ROOT/out"
  }
}

# producer_gone: the writer marked its write; let the producer exit and wait until it has.
producer_gone() {
  local r=0
  wait_for "$TEST_ROOT/writing" || r=1
  : > "$TEST_ROOT/go"
  wait_for "$TEST_ROOT/gone" || r=1
  return "$r"
}

# checks_done: both checks ran and vbw check removed its run folder: it is printing.
checks_done() {
  local i
  wait_for "$TEST_ROOT/ran.C2" || return 1
  for ((i = 0; i < 600; i++)); do
    set -- .vbw/runtime/run.*
    [ -e "$1" ] || return 0
    sleep 0.05
  done
  return 1
}

@test "vbw_out writes all of its text while the producer of the loop it writes in exits" {
  # The producer gives one line, then exits only once the reader says so, while vbw_out waits.
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  full_pipe producer_gone vbw_kernel 'while IFS= read -r l; do
      : > "$TEST_ROOT/writing"
      vbw_out "%s\n" "line $l, whole"
    done < <(printf "1\n"; until [ -e "$TEST_ROOT/go" ]; do sleep 0.05; done; : > "$TEST_ROOT/gone")'
  cat "$TEST_ROOT/out"
  [ "$(cat "$TEST_ROOT/ready")" = 0 ]
  [ "$(cat "$TEST_ROOT/code")" = 0 ]
  grep -qx 'line 1, whole' "$TEST_ROOT/out"
  ! grep -q 'Interrupted system call' "$TEST_ROOT/out"
}

@test "vbw check prints every result and passes when its output waits for a slow reader" {
  full_pipe checks_done "$VBW" check C1 C2
  cat "$TEST_ROOT/out"
  [ "$(cat "$TEST_ROOT/ready")" = 0 ]
  [ "$(cat "$TEST_ROOT/code")" = 0 ]
  grep -q '^C1 pass' "$TEST_ROOT/out"
  grep -q '^C2 pass' "$TEST_ROOT/out"
  ! grep -q 'Interrupted system call' "$TEST_ROOT/out"
}

@test "vbw_die says why and exits with its code even when a child exits while the message waits for the reader" {
  # Under set -e, as the kernel runs: a failed write would end the shell with 1, before the exit code it names.
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  full_pipe producer_gone vbw_kernel 'set -e
    while IFS= read -r l; do
      : > "$TEST_ROOT/writing"
      vbw_die "stopped at line $l" 3
    done < <(printf "1\n"; until [ -e "$TEST_ROOT/go" ]; do sleep 0.05; done; : > "$TEST_ROOT/gone")'
  cat "$TEST_ROOT/out"
  [ "$(cat "$TEST_ROOT/ready")" = 0 ]
  [ "$(cat "$TEST_ROOT/code")" = 3 ]
  grep -qx 'vbw: stopped at line 1' "$TEST_ROOT/out"
  ! grep -q 'Interrupted system call' "$TEST_ROOT/out"
}

# The rule.

rule() { bash "$REPO_ROOT/tools/check-loop-writes.sh" "$@"; }

# planted TEXT [NAME TEXT]...: a directory holding one shell file, cmd-plant.sh,
# with TEXT from its line 4 (after a header comment), and one more file NAME
# per further pair, laid out the same; prints the directory.
planted() {
  local d
  d=$(mktemp -d "$TEST_ROOT/plant.XXXXXX")
  plant "$d/cmd-plant.sh" "$1"; shift
  while [ $# -ge 2 ]; do plant "$d/$1" "$2"; shift 2; done
  printf '%s\n' "$d"
}
# plant FILE TEXT: FILE holds TEXT from its line 4, after a header comment.
plant() { printf '#!/usr/bin/env bash\n# A planted file.\n\n%s\n' "$2" > "$1"; }

@test "R218: no shipped shell code writes with a builtin, or calls a function that writes with one, in the shell of a loop fed by a process substitution" {
  run rule "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "self-test: the rule catches each builtin write in a loop fed by a process substitution, naming its line" {
  local case line
  # Each case: the line the write is on, a colon, the planted code.
  for case in \
    "5:while IFS= read -r l; do
  printf '%s\n' \"\$l\"
done < <(jq -r '.[]' \"\$f\")" \
    "4:while IFS= read -r l; do echo \"\$l\"; done < <(printf 'a\n')" \
    "5:while IFS= read -r l; do
  printf 'vbw: %s -> %s\n' \"\$l\" \"\$x\" >&2
done < <(git log --format=%H)" \
    "4:while IFS= read -r -d '' a; do printf '%s\n' \"\$a\"; done \\
  < <(find . -print0)" \
    "6:  while IFS= read -r l; do
    for r in \$l; do
      [ \"\$r\" = x ] && { printf '  %s\n' \"\$r\"; break; }
    done
  done < <(git log --format=%s)" \
    "5:while IFS= read -r l; do
  printf '%s\n' \"\$l\" 2> /dev/null
done < <(jq -r '.[]' \"\$f\")" \
    "5:while IFS= read -r l; do
  if [ -f \"\$l\" ]; then printf 'x\n'; fi
done < <(jq -r '.[]' \"\$f\")" \
    "6:while IFS= read -r l; do
  out=\$(jq -r . \"\$l\")
  printf '%s\n' \"\${out}\"
done < <(jq -r '.[]' \"\$f\")"; do
    line=${case%%:*}
    run rule "$(planted "${case#*:}")"
    [ "$status" -ne 0 ] || { echo "not caught: ${case#*:}"; false; }
    [[ "$output" == *"cmd-plant.sh:$line:"* ]] || { echo "not named at line $line: ${case#*:}"; echo "$output"; false; }
  done
}

@test "self-test: the rule passes writes in a child of their own or into a file, and loops fed by a pipe" {
  local code
  for code in \
    "while IFS= read -r l; do
  vbw_out '%s\n' \"\$l\"
  vbw_out 'vbw: %s -> %s\n' \"\$l\" \"\$x\" >&2
done < <(jq -r '.[]' \"\$f\")" \
    "while IFS= read -r l; do
  printf '%s\n' \"\$l\" > \"\$dir/one\"
  printf '%s\n' \"\$l\" >> \"\$dir/all\"
  printf '%s\n' \"\$l\" &> \"\$dir/both\"
  [ -z \"\$l\" ] || printf '%s\0' \${a[@]+\"\${a[@]}\"} > \"\$dir/u/\$n\"
done < <(jq -r '.[]' \"\$f\")" \
    "while IFS= read -r l; do
  x=\$(printf '%s' \"\$l\" | jq .)
  t=\$(cd \"\$l\" 2> /dev/null && printf '%s/%s' \"\$(pwd -P)\" x)
  printf '%s' \"\$l\" | jq -e . > /dev/null
  ( printf 'in a subshell\n' )
done < <(jq -r '.[]' \"\$f\")" \
    "jq -r '.[]' \"\$f\" | while IFS= read -r l; do printf '%s\n' \"\$l\"; done" \
    "while IFS= read -r -d '' plan; do
  awk '{ print }' \"\$plan\" | while IFS= read -r p; do
    printf 'N\t%s\n' \"\$p\"
  done
done < <(find . -print0)" \
    "while IFS= read -r l; do
  command -v printf > /dev/null
  vbw_die \"use printf; echo it\"
  cat << 'EOF'
printf 'a heredoc line, not code'
EOF
done < <(jq -r '.[]' \"\$f\")"; do
    run rule "$(planted "$code")"
    [ "$status" -eq 0 ] || { echo "refused: $code"; echo "$output"; false; }
  done
}

# R218 (T189): a call to a function that writes with a builtin in the same shell
# is that write, wherever among the files given the function is defined; the
# tool finds the writers itself (a body writing in its own shell, or calling a
# writer so), to a fixed point.

@test "R218: the rule refuses a call to a writer function at the calling line, then names the writer and where it writes" {
  local case call name wfile wline rest code
  # Each case: the calling line, the writer's name, the file and line of its
  # write, then the planted code (from line 4).
  for case in \
    "6:say:cmd-plant.sh:4:say() { printf '%s\n' \"\$1\"; }
while IFS= read -r l; do
  say \"\$l\"
done < <(jq -r '.[]' \"\$f\")" \
    "8:tell:cmd-plant.sh:5:tell() {
  printf 'vbw: %s\n' \"\$1\" >&2
}
while IFS= read -r l; do
  tell \"\$l\"
done < <(git log --format=%H)" \
    "9:outer:cmd-plant.sh:6:outer() { inner \"\$1\"; }
inner() {
  echo \"\$1\" >&2
}
while IFS= read -r l; do
  [ -z \"\$l\" ] || outer \"\$l\"
done < <(find . -print0)"; do
    call=${case%%:*}; rest=${case#*:}
    name=${rest%%:*}; rest=${rest#*:}
    wfile=${rest%%:*}; rest=${rest#*:}
    wline=${rest%%:*}; code=${rest#*:}
    run rule "$(planted "$code")"
    [ "$status" -ne 0 ] || { echo "not refused: $code"; false; }
    [[ "$output" == *"cmd-plant.sh:$call:"*"$wfile:$wline"* ]] \
      || { echo "the call at line $call is not named before the write at $wfile:$wline: $code"; echo "$output"; false; }
    printf '%s\n' "$output" | grep -E "(^|[^A-Za-z0-9_])$name([^A-Za-z0-9_]|$)" | grep -q "$wfile:$wline" \
      || { echo "no line names the writer $name with its write at $wfile:$wline: $code"; echo "$output"; false; }
  done
}

@test "R218: a writer defined in another file, in the same directory or under another DIR given in either order, is known" {
  local caller writer d1 d2 order
  caller="while IFS= read -r l; do
  tell \"\$l\"
done < <(jq -r '.[]' \"\$f\")"
  writer="tell() {
  printf '%s\n' \"\$1\"
}"
  run rule "$(planted "$caller" lib-tell.sh "$writer")"
  [ "$status" -ne 0 ] || { echo "not refused: the writer is in a second file of the same directory"; false; }
  [[ "$output" == *"cmd-plant.sh:5:"*"tell"*"lib-tell.sh:5"* ]] || { echo "the call at cmd-plant.sh:5 is not named with the writer tell at lib-tell.sh:5"; echo "$output"; false; }
  d1=$(planted "$caller")
  d2=$(planted 'true' lib-tell.sh "$writer")
  for order in "$d1 $d2" "$d2 $d1"; do
    # shellcheck disable=SC2086 # two directories, no spaces in TEST_ROOT
    run rule $order
    [ "$status" -ne 0 ] || { echo "not refused: the writer is under another DIR ($order)"; false; }
    [[ "$output" == *"cmd-plant.sh:5:"*"tell"*"lib-tell.sh:5"* ]] || { echo "the call at cmd-plant.sh:5 is not named with the writer tell at lib-tell.sh:5 ($order)"; echo "$output"; false; }
  done
}

@test "R218: a function writing through vbw_out, a subshell, a pipeline or into a file is no writer, and a writer called in a child of its own, into a file or in a pipe-fed loop passes" {
  local code
  for code in \
    "quiet() { vbw_out '%s\n' \"\$1\"; }
sub() { ( printf '%s\n' \"\$1\" ); }
piped() { printf '%s\n' \"\$1\" | cat; }
filed() { printf '%s\n' \"\$1\" > \"\$f\"; }
while IFS= read -r l; do
  quiet \"\$l\"; sub \"\$l\"
  piped \"\$l\"
  filed \"\$l\"
done < <(jq -r '.[]' \"\$f\")" \
    "say() { printf '%s\n' \"\$1\"; }
while IFS= read -r l; do
  x=\$(say \"\$l\")
  say \"\$l\" > \"\$dir/one\"
  say \"\$l\" >> \"\$dir/all\"
  say \"\$l\" | cat
  ( say \"\$l\" )
  say \"\$l\" &
done < <(jq -r '.[]' \"\$f\")" \
    "say() { echo \"\$1\"; }
jq -r '.[]' \"\$f\" | while IFS= read -r l; do say \"\$l\"; done
while IFS= read -r -d '' plan; do
  awk '{ print }' \"\$plan\" | while IFS= read -r p; do
    say \"\$p\"
  done
done < <(find . -print0)"; do
    run rule "$(planted "$code")"
    [ "$status" -eq 0 ] || { echo "refused: $code"; echo "$output"; false; }
  done
}

@test "R218: the tool's header states the writer-function rule, AGENTS.md's live-child line counts a call to a function that writes as the write, this file's header names the widened rule, and the tool stays bash 3.2 and awk" {
  local tool head
  tool="$REPO_ROOT/tools/check-loop-writes.sh"
  head=$(sed -n '2,/^set -e/p' "$tool" | grep '^#')
  printf '%s\n' "$head" | grep -i 'function' | grep -qi 'call' || { echo "the tool's header does not state the rule on a call to a function that writes"; false; }
  ! printf '%s\n' "$head" | grep -q "reviewer's to judge" || { echo "the tool's header still leaves a function call to the reviewer"; false; }
  grep -F -- '- **No builtin write while the shell has a live child:**' "$REPO_ROOT/AGENTS.md" | grep -i 'function' | grep -qi 'call' \
    || { echo "AGENTS.md's live-child line does not count a call to a function that writes as the write"; false; }
  sed -n '1,/^load helper/p' "$BATS_TEST_FILENAME" | grep '^#' | grep -i 'function' | grep -qi 'call' || { echo "this file's header does not name the widened rule"; false; }
  ! grep -Eq 'mapfile|readarray|declare -A|local -A' "$tool" || { echo "the tool uses a bash 4 feature"; false; }
  /bin/bash -n "$tool"
}

# R274: a kernel function that captures large text (a command substitution) and
# hands it out through a builtin printf or echo as its last command writes while
# the substitution's child may still be exiting: macOS bash 3.2 does not restart
# that write (spec_parse, cmd-spec.sh, lost the parsed spec). The rule
# tools/check-captured-writes.sh refuses such an ending in plugin/lib unless the
# write goes through vbw_out, with an allow-list by function name, each with its
# reason (--allowed lists them); tests/standards.bats runs it.

captured() { bash "$REPO_ROOT/tools/check-captured-writes.sh" "$@"; }

@test "R274: no function in plugin/lib ends by handing captured text out through a builtin printf or echo, unless allow-listed with a reason" {
  run captured "$PLUGIN_ROOT/lib"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R274: spec_parse hands the parsed spec out through vbw_out" {
  local body
  body=$(sed -n '/^spec_parse() {/,/^}/p' "$PLUGIN_ROOT/lib/cmd-spec.sh")
  [ -n "$body" ] || { echo "no spec_parse in cmd-spec.sh"; false; }
  ! grep -q "printf '%s\\\\n' \"\$parsed\"" <<< "$body" || { echo "spec_parse still writes with a builtin printf"; false; }
  grep -q 'vbw_out' <<< "$body" || { echo "spec_parse does not write through vbw_out"; false; }
}

@test "self-test: the captured-write rule refuses a function ending in a builtin printf or echo of text captured in that function, naming the line" {
  local case line
  for case in \
    "7:spec_parse() {
  local parsed
  parsed=\$(jq -Rs -f \"\$VBW_LIB/spec.jq\" \"\$1\")
  printf '%s\n' \"\$parsed\"
}" \
    "6:loop_spend() {
  out=\$(jq -c '.spend' \"\$1\")
  echo \"\$out\"
}" \
    "8:qa_digests() {
  local out='{}'
  while read -r id; do
    out=\$(printf '%s' \"\$out\" | jq -c --arg id \"\$id\" '. + {(\$id): 1}')
  done < <(jq -r '.[]' \"\$1\")
  printf '%s\n' \"\$out\"
}" \
    "8:step_expect() {
  local out
  [ -f \"\$1\" ] || return 0
  out=\$(jq -n -r -f \"\$1\" 2> /dev/null) || return 0
  printf '%s' \"\$out\"
}"; do
    line=${case%%:*}
    run captured "$(planted "${case#*:}")"
    [ "$status" -ne 0 ] || { echo "not caught: ${case#*:}"; false; }
    [[ "$output" == *"cmd-plant.sh:$line:"* ]] || { echo "not named at line $line: ${case#*:}"; echo "$output"; false; }
  done
}

@test "self-test: the captured-write rule passes vbw_out, a literal or an argument, a write into a pipe or a file, and a function that ends otherwise" {
  local code
  for code in \
    "spec_parse() {
  local parsed
  parsed=\$(jq -Rs -f \"\$VBW_LIB/spec.jq\" \"\$1\")
  vbw_out '%s\n' \"\$parsed\"
}" \
    "say() {
  printf '%s\n' \"\$1\"
}
word() { local w=paid; printf '%s\n' \"\$w\"; }
hello() { echo \"hello \$1\"; }" \
    "piped() {
  out=\$(jq -c . \"\$1\")
  printf '%s\n' \"\$out\" | cat
}
filed() {
  out=\$(jq -c . \"\$1\")
  printf '%s\n' \"\$out\" > \"\$2\"
}
errd() {
  out=\$(jq -c . \"\$1\")
  printf '%s\n' \"\$out\" >&2
}" \
    "middle() {
  out=\$(jq -c . \"\$1\")
  printf '%s\n' \"\$out\"
  jq -e . \"\$1\" > /dev/null
}"; do
    run captured "$(planted "$code")"
    [ "$status" -eq 0 ] || { echo "refused: $code"; echo "$output"; false; }
  done
}

@test "R274: --allowed lists each allow-listed function with its reason, and each one is a function of plugin/lib" {
  run captured --allowed
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local l name
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    [[ "$l" =~ ^[a-z_][a-z0-9_]*:\ .+$ ]] || { echo "not 'name: reason': $l"; false; }
    name=${l%%:*}
    grep -qE "^$name\(\) \{" "$PLUGIN_ROOT"/lib/*.sh || { echo "allow-listed but no such function in plugin/lib: $name"; false; }
  done <<< "$output"
}
