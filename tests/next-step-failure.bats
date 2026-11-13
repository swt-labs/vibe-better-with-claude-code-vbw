#!/usr/bin/env bats
# R310 (T297): vbw next never answers on a step it could not finish. When QA's
# fingerprints cannot be made (qa_digests, plugin/lib/qa-inputs.sh) or the answer
# itself cannot be worked out, vbw next exits non-zero with the reason on stderr,
# prints no answer and leaves .vbw/runtime/next.json as it was; vbw status and vbw qa
# stop with the same reason, and qa_state and qa_combined pass the failure on. Only
# the road's inputs turn a failed judgment into '{}', as designed. A hashing step is
# made to fail by a sha256sum (and shasum) on PATH that refuses inside QA's
# temporary folder; the answer step by a jq on PATH that refuses next.jq's program.
# L1: the kernel on a project with two built and proven phases.

load helper
load qa-recheck-helper
load fixture-helper

setup_file() { fixture_build p2 qa_project 2; }
setup() {
  fixture_copy p2
  SHIM="$TEST_ROOT/shim"
  mkdir -p "$SHIM"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# hash_fails: sha256sum and shasum on $SHIM refuse inside QA's temporary folders
# (.vbw/runtime/qa.*) and hash as usual everywhere else.
hash_fails() {
  local p real
  for p in sha256sum shasum; do
    real=$(command -v "$p") || real=''
    {
      printf '#!/bin/sh\ncase "$PWD" in */.vbw/runtime/qa.*) echo "%s: forced failure" >&2; exit 1 ;; esac\n' "$p"
      if [ -n "$real" ]; then
        printf 'exec "%s" "$@"\n' "$real"
      else
        printf 'exec "%s" -a 256 "$@"\n' "$(command -v shasum)"
      fi
    } > "$SHIM/$p"
    chmod +x "$SHIM/$p"
  done
}

# answer_fails: jq on $SHIM refuses the one program that holds next.jq.
answer_fails() {
  printf '#!/bin/sh\nfor a; do case "$a" in *"def next_prog:"*) echo "jq: forced failure of the answer" >&2; exit 5 ;; esac; done\nexec "%s" "$@"\n' "$(command -v jq)" > "$SHIM/jq"
  chmod +x "$SHIM/jq"
}

# next_fails: vbw next --json with $SHIM first on PATH stops: non-zero, nothing on
# stdout, stderr holding $1, next.json unchanged.
next_fails() {
  local before rc=0
  "$VBW" next --json < /dev/null > /dev/null
  [ -f .vbw/runtime/next.json ] || { echo "vbw next wrote no next.json"; return 1; }
  before=$(cksum < .vbw/runtime/next.json)
  PATH="$SHIM:$PATH" "$VBW" next --json < /dev/null > "$TEST_ROOT/out" 2> "$TEST_ROOT/err" || rc=$?
  cat "$TEST_ROOT/err"
  [ "$rc" -ne 0 ] || { echo "vbw next exited 0 with: $(cat "$TEST_ROOT/out")"; return 1; }
  [ ! -s "$TEST_ROOT/out" ] || { echo "vbw next printed an answer: $(cat "$TEST_ROOT/out")"; return 1; }
  grep -qF -- "$1" "$TEST_ROOT/err" || { echo "the reason '$1' is not on stderr"; return 1; }
  [ "$(cksum < .vbw/runtime/next.json)" = "$before" ] || { echo "next.json changed"; return 1; }
}

@test "R310 guard: qa_digests expands no array unguarded, as bash 3.2 under set -u stops on an empty one" {
  local body bad
  body=$(sed -n '/^qa_digests() {/,/^}/p' "$PLUGIN_ROOT/lib/qa-inputs.sh")
  [ -n "$body" ]
  bad=$(printf '%s\n' "$body" | grep -nE '(^|[^+])"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"' || true)
  [ -z "$bad" ] || { echo "unguarded expansions in qa_digests:"; echo "$bad"; false; }
}

@test "R310 hashing: when QA's inputs cannot be hashed, vbw next exits non-zero with the reason, prints no answer and leaves next.json as it was" {
  hash_fails
  next_fails "vbw: cannot hash QA's inputs"
}

@test "R310 answer: when the answer cannot be worked out, vbw next exits non-zero with the reason, prints no answer and leaves next.json as it was" {
  answer_fails
  next_fails "jq: forced failure of the answer"
}

@test "R310 answer error: an answer the judgment itself refuses (next.jq raises an error) stops vbw next with that reason and no answer" {
  # A jq on $SHIM that makes next.jq's program raise its own error, which the program catches.
  {
    printf '#!/bin/bash\nargs=()\nfor a; do args+=("${a/def next_prog:/def next_prog: error(\\"forced judgment error\\") |}"); done\nexec "%s" "${args[@]}"\n' "$(command -v jq)"
  } > "$SHIM/jq"
  chmod +x "$SHIM/jq"
  next_fails "forced judgment error"
}

@test "R310 status: when QA's inputs cannot be hashed, vbw status exits non-zero with the reason instead of a status built on empty fingerprints" {
  hash_fails
  local rc=0
  PATH="$SHIM:$PATH" "$VBW" status < /dev/null > "$TEST_ROOT/out" 2> "$TEST_ROOT/err" || rc=$?
  cat "$TEST_ROOT/out" "$TEST_ROOT/err"
  [ "$rc" -ne 0 ]
  grep -qF "vbw: cannot hash QA's inputs" "$TEST_ROOT/err"
}

@test "R310 qa: when QA's inputs cannot be hashed, vbw qa record stops with that reason, never 'is not a phase of the active milestone', and records nothing" {
  hash_fails
  local rc=0 before
  before=$(cksum < .vbw/record.json)
  PATH="$SHIM:$PATH" "$VBW" qa record P1 pass standard < /dev/null > "$TEST_ROOT/out" 2> "$TEST_ROOT/err" || rc=$?
  cat "$TEST_ROOT/out" "$TEST_ROOT/err"
  [ "$rc" -ne 0 ]
  grep -qF "vbw: cannot hash QA's inputs" "$TEST_ROOT/err"
  [ "$(grep -cF 'is not a phase of the active milestone' "$TEST_ROOT/err")" = 0 ]
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R310 callers: qa_state and qa_combined pass a hashing failure on to their callers" {
  hash_fails
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  PATH="$SHIM:$PATH" run vbw_kernel '. "$VBW_LIB/cmd-next.sh"; r=$(cat "$VBW_RECORD")
    if qa_state "$r" > /dev/null 2>&1; then echo "qa_state answered"; fi
    if qa_combined "$r" > /dev/null 2>&1; then echo "qa_combined answered"; fi
    echo end'
  [ "$output" = end ] || { echo "$output"; false; }
}

@test "R310 road: the road's input still turns a failed judgment into {}, and no other caller of the judgment turns a failure into an answer" {
  hash_fails
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  PATH="$SHIM:$PATH" run vbw_kernel '. "$VBW_LIB/cmd-next.sh"; next_prepare; next_road_input'
  [ "$status" -eq 0 ] && [ "$output" = '{}' ] || { echo "status $status: $output"; false; }
  # Every call of next_decide or next_answer either stops on a failure (exit, return or
  # a kept status) or is one of the road's two inputs.
  run sh -c 'cd "$1" && awk '\''
    /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { f = $1; sub(/\(\).*/, "", f) }
    /^[[:space:]]*#/ { next }
    /(next_decide|next_answer)([^A-Za-z0-9_(]|$)/ && /\|\|/ && !/\|\| *(exit|return|rc=)/ { print f }
  '\'' *.sh | LC_ALL=C sort -u' _ "$PLUGIN_ROOT/lib"
  [ "$output" = "$(printf 'next_road_input\nstep_road_input')" ] || { echo "$output"; false; }
}
