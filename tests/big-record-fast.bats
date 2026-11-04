#!/usr/bin/env bats
# R249 (T229; docs/record.md): the kernel stays fast on a large record because it
# does less, not because it waits less: the validator runs once per record content
# (.vbw/runtime/validated.json keeps the digest of the last validated bytes beside
# the digest of the validator's own text, record.jq, record-schema.jq and
# interview.json; a record whose bytes match is not validated again, any other
# content is), the chat list is read and matched in one jq pass whatever its
# size, and vbw next --json and vbw status compute their fields in one jq pass
# over the record instead of one parse per field. The budgets themselves are the
# release run's (tests/timed-big-record.bats); here the shape of the work is
# pinned: how many times jq is started on the record. L1: the kernel on the R149
# twins (tests/big-record-helper.bash) with a jq on PATH that counts its calls.

load helper
load big-record-helper
load fixture-helper

setup_file() { fixture_build twins twin_fixture; }
setup() {
  twin_copy twins
  DIGEST="$BIG/.vbw/runtime/validated.json"
}
teardown() {
  chmod -R u+w "$TEST_ROOT" 2> /dev/null || true
  vbw_teardown
}
teardown_file() { fixture_teardown; }

# A jq on PATH that logs each call before running the real one. Every call goes
# to calls.log. A call that reads a record-sized input (1 MB or more: the large
# twin's record is over 2 MB; nothing else in the project comes near) goes to
# big.log, a call that runs the validator (an argument naming record.jq) to
# validator.log. An input is sized without being read twice: a file argument by
# its size; a file argument that is a pipe (a process substitution) is drained
# into a file of the test, which the real jq then reads in its place; stdin is
# drained the same way only when jq would read it (no -n and no input file named,
# or - named), since a jq given a file never touches the stdin it inherits.
shim() {
  local real
  real=$(command -v jq)
  mkdir -p "$TEST_ROOT/shim" "$TEST_ROOT/shim-in"
  cat > "$TEST_ROOT/shim/jq" << SH
#!/bin/bash
real='$real'; log='$TEST_ROOT'; big=0; noinput=0; prog=0; files=0; stdin=0; args=()
ORIG=("\$@")
while [ \$# -gt 0 ]; do
  a=\$1; shift
  case "\$a" in
    --args | --jsonargs) break ;;
    --arg | --argjson | --slurpfile | --rawfile) shift 2 ;;
    --from-file) prog=1; shift ;;
    -L | --indent) shift ;;
    --null-input) noinput=1 ;;
    --*) ;;
    -) files=1; stdin=1 ;;
    -*) case "\$a" in *n*) noinput=1 ;; esac; case "\$a" in *f*) prog=1; shift ;; esac ;;
    *) if [ "\$prog" = 0 ]; then prog=1; else files=1; fi ;;
  esac
done
reads=0
if [ "\$noinput" = 0 ] && { [ "\$files" = 0 ] || [ "\$stdin" = 1 ]; }; then reads=1; fi
for a in "\${ORIG[@]}"; do
  if [ -p "\$a" ]; then f=\$(mktemp "\$log/shim-in/fd.XXXXXX"); cat "\$a" > "\$f"; a=\$f; fi
  if [ -f "\$a" ] && [ "\$(wc -c < "\$a")" -ge 1048576 ]; then big=1; fi
  args+=("\$a")
done
line=\$(printf '%s' "\${ORIG[*]}" | tr '\n' ' ' | cut -c1-160)
printf '%s\n' "\$line" >> "\$log/calls.log"
case " \${ORIG[*]} " in *record.jq*) printf '%s\n' "\$line" >> "\$log/validator.log" ;; esac
if [ "\$reads" = 1 ] && [ ! -t 0 ]; then
  f=\$(mktemp "\$log/shim-in/in.XXXXXX"); cat > "\$f"
  [ "\$(wc -c < "\$f")" -lt 1048576 ] || big=1
  [ "\$big" = 0 ] || printf '%s\n' "\$line" >> "\$log/big.log"
  exec "\$real" "\${args[@]}" < "\$f"
fi
[ "\$big" = 0 ] || printf '%s\n' "\$line" >> "\$log/big.log"
exec "\$real" "\${args[@]}"
SH
  chmod +x "$TEST_ROOT/shim/jq"
}

# counted CMD...: run vbw CMD in the large twin through the counting jq, with
# fresh logs. Sets OUT and CODE.
counted() {
  rm -f "$TEST_ROOT/calls.log" "$TEST_ROOT/big.log" "$TEST_ROOT/validator.log"
  CODE=0
  OUT=$(cd "$BIG" && PATH="$TEST_ROOT/shim:$PATH" "$VBW" "$@" < /dev/null 2>&1) || CODE=$?
}
calls() { [ -f "$TEST_ROOT/$1.log" ] && wc -l < "$TEST_ROOT/$1.log" | tr -d ' ' || echo 0; }

@test "R249 digest: a record read leaves .vbw/runtime/validated.json with the record's and the validator's digests; the unchanged record is not validated again; a record whose bytes changed is, and its output is the same" {
  shim
  [ ! -e "$DIGEST" ]
  counted show roadmap
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  [ "$(calls validator)" -ge 1 ] || { echo "the first read did not run the validator"; false; }
  jq -e '(.record | type == "string" and test("^[0-9a-f]{64}$")) and (.validator | type == "string" and test("^[0-9a-f]{64}$"))' "$DIGEST" \
    || { echo "no digest file: $(cat "$DIGEST" 2>&1)"; false; }
  local first="$OUT"
  counted show roadmap
  [ "$CODE" -eq 0 ] && [ "$OUT" = "$first" ] || { echo "$OUT"; false; }
  [ "$(calls validator)" -eq 0 ] || { echo "the unchanged record was validated again: $(cat "$TEST_ROOT/validator.log")"; false; }
  # The same content in other bytes (an older VBW's compact write) is another record.
  jq -c . "$BIG/.vbw/record.json" > "$TEST_ROOT/compact.json" && cp "$TEST_ROOT/compact.json" "$BIG/.vbw/record.json"
  counted show roadmap
  [ "$CODE" -eq 0 ] && [ "$OUT" = "$first" ] || { echo "$OUT"; false; }
  [ "$(calls validator)" -ge 1 ] || { echo "the rewritten record was not validated"; false; }
}

@test "R249 digest: a hand edit after a warm digest is still refused as corrupt, and a newer schema still asks for a newer VBW" {
  (cd "$BIG" && "$VBW" show roadmap > /dev/null)
  [ -f "$DIGEST" ]
  jq '.plans[0].status = "nope"' "$BIG/.vbw/record.json" > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" "$BIG/.vbw/record.json"
  run bash -c 'cd "$1" && "$2" status' _ "$BIG" "$VBW"
  [ "$status" -eq 3 ] && [[ "$output" == *"corrupt"* ]] || { echo "$status: $output"; false; }
  cp "$TEST_ROOT/edit.json" "$TEST_ROOT/base.json"
  jq '.plans[0].status = "done" | .schema = 99' "$TEST_ROOT/base.json" > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" "$BIG/.vbw/record.json"
  run bash -c 'cd "$1" && "$2" status' _ "$BIG" "$VBW"
  [ "$status" -eq 4 ] && [[ "$output" == *"needs a newer VBW"* && "$output" != *"corrupt"* ]] || { echo "$status: $output"; false; }
}

@test "R249 digest: the validator's own text is part of the digest: a changed record.jq, record-schema.jq or interview.json validates the unchanged record again" {
  shim
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  local copy="$TEST_ROOT/plugin/bin/vbw" f
  (cd "$BIG" && "$copy" show roadmap > /dev/null)
  for f in record.jq record-schema.jq interview.json; do
    rm -f "$TEST_ROOT/validator.log"
    (cd "$BIG" && PATH="$TEST_ROOT/shim:$PATH" "$copy" show roadmap > /dev/null)
    [ "$(calls validator)" -eq 0 ] || { echo "validated with nothing changed (before $f)"; false; }
    case "$f" in
      *.jq) printf '\n# changed\n' >> "$TEST_ROOT/plugin/lib/$f" ;;
      *) jq . "$TEST_ROOT/plugin/lib/$f" > "$TEST_ROOT/iv.json" && printf '\n' >> "$TEST_ROOT/iv.json" && cp "$TEST_ROOT/iv.json" "$TEST_ROOT/plugin/lib/$f" ;;
    esac
    rm -f "$TEST_ROOT/validator.log"
    run bash -c 'cd "$1" && PATH="$3:$PATH" "$2" show roadmap' _ "$BIG" "$copy" "$TEST_ROOT/shim"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(calls validator)" -ge 1 ] || { echo "a changed $f did not validate the record again"; false; }
  done
}

@test "R249 digest: a runtime folder that cannot be written is never an error: the same output, exit 0, nothing on stderr, and the record is simply validated again" {
  [ "$(id -u)" -ne 0 ] || skip "root writes everywhere"
  shim
  local want
  want=$(cd "$BIG" && "$VBW" show roadmap 2>&1)
  rm -f "$DIGEST"
  chmod a-w "$BIG/.vbw/runtime"
  run bash -c 'cd "$1" && PATH="$3:$PATH" "$2" show roadmap 2> "$4"' _ "$BIG" "$VBW" "$TEST_ROOT/shim" "$TEST_ROOT/err"
  chmod u+w "$BIG/.vbw/runtime"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$want" ] || { echo "the output differs with a read-only runtime folder: $output"; false; }
  [ ! -s "$TEST_ROOT/err" ] || { echo "stderr: $(cat "$TEST_ROOT/err")"; false; }
  [ ! -e "$DIGEST" ]
  [ "$(calls validator)" -ge 1 ]
}

# registry N: Claude Code's list of chats with N entries whose cwd is the project
# at hand, every one still named by Claude Code (nameSource auto), plus three in
# other folders, as the sessions-helper writes them.
registry() {
  local dir="$CLAUDE_CONFIG_DIR/sessions" i
  rm -rf "$dir"
  mkdir -p "$dir"
  for i in $(seq 1 "$1"); do
    printf '{"sessionId": "sess-%s", "cwd": "%s", "name": "Chat %s", "nameSource": "auto", "updatedAt": %s, "status": "idle"}\n' \
      "$i" "$PWD" "$i" "$((1792300000000 + i))" > "$dir/$((1000 + i)).json"
  done
  for i in 1 2 3; do
    printf '{"sessionId": "other-%s", "cwd": "%s/elsewhere %s", "name": "Other %s", "nameSource": "auto", "updatedAt": 1792300000000, "status": "idle"}\n' \
      "$i" "$TEST_ROOT" "$i" "$i" > "$dir/$((2000 + i)).json"
  done
}

# nexts N: a fresh project whose first vbw next, as the chat sess-1, reads a list
# of N entries on the project (the /rename hint, D444, looks at them all); prints
# the number of jq calls that vbw next made.
nexts() {
  mkdir -p "$TEST_ROOT/chats $1"
  (
    cd "$TEST_ROOT/chats $1" || exit 1
    vbw_git_project
    "$VBW" init > /dev/null
    registry "$1"
    rm -f "$TEST_ROOT/calls.log"
    PATH="$TEST_ROOT/shim:$PATH" VBW_SESSION_ID=sess-1 "$VBW" next --json > "$TEST_ROOT/next.out" 2>&1 < /dev/null || { cat "$TEST_ROOT/next.out"; exit 1; }
    jq -e '.rename_hint | type == "string" and test("/rename")' "$TEST_ROOT/next.out" > /dev/null || { echo "no /rename hint with $1 chats on the project:"; cat "$TEST_ROOT/next.out"; exit 1; }
  ) || return 1
  calls calls
}

@test "R249 chat list: the chat list is read and matched in one jq pass: vbw next on a list of 500 chats of the project starts jq as many times as on a list of 5" {
  shim
  local few many
  few=$(nexts 5) || { echo "$few"; false; }
  many=$(nexts 500) || { echo "$many"; false; }
  [ "$few" -gt 0 ]
  [ "$many" -eq "$few" ] || { echo "jq ran $many times for 500 chats and $few times for 5: the lookup runs jq per entry"; false; }
}

@test "R249 one pass: after a warm digest, vbw next --json and vbw status each read the record through at most two record-sized jq calls" {
  shim
  (cd "$BIG" && "$VBW" status > /dev/null)
  counted next --json
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  printf '%s' "$OUT" | jq -e '.action | type == "string"' > /dev/null
  [ "$(calls big)" -le 2 ] || { echo "vbw next --json parsed the record $(calls big) times:"; cat "$TEST_ROOT/big.log"; false; }
  counted status
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  [ "$(calls big)" -le 2 ] || { echo "vbw status parsed the record $(calls big) times:"; cat "$TEST_ROOT/big.log"; false; }
}
