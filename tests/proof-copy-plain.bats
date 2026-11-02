#!/usr/bin/env bats
# R206 (docs/proof.md): when a proof or a mutation run copies ignored data by
# plain copy (the file system offers no copy-on-write clone) and the data copied
# exceeds 500 MB, the command prints one line to stderr starting "vbw:" naming
# the up to three largest ignored folders copied with their sizes (MB or GB, one
# decimal) and the way out ("list them under ## Clean copy in .vbw/spec.md, then
# vbw spec sync"); once per command, however many copies it makes. A copy-on-write
# clone, 500 MB or less, or nothing ignored prints nothing, and the line never
# changes the verdict, the evidence, the record or the exit code. The sizes are
# read with du -sk, once per top-level ignored path and command (not per copy
# slot), inside the copies step of VBW's own work. L1: the kernel on a fixture
# project; a cp stand-in on PATH refuses the clone flag (-c, --reflink) or honours
# it, a du stand-in answers from a table (tests/proof-copy-plain.bats makes no
# 500 MB of real data) and a test-only variable, VBW_PROOFCOPY_PLAIN_KB, lowers the
# threshold.

load helper
load fixture-helper

# shop: an approved project with four ignored folders (data/, cache/, logs/,
# tmpd/), two checks of R1 reading src/pay.txt, and one open fix.
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf 'data/\ncache/\nlogs/\ntmpd/\n' > .gitignore
  mkdir -p data cache logs tmpd src tests
  printf 'd\n' > data/a.bin
  printf 'c\n' > cache/c.txt
  printf 'l\n' > logs/l.txt
  printf 't\n' > tmpd/t.txt
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx paid src/pay.txt\n' > tests/pay2.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R1", run: ["sh", "tests/pay2.sh"], files: ["tests/pay2.sh"]}],
    rules: [{req: "R1", text: "paying works", check: "C1"}, {req: "R1", text: "paying works twice", check: "C2"}]}' | "$VBW" apply > /dev/null
  jq '.plans[0].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]' .vbw/record.json > "$TEST_ROOT/edit.json" \
    && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build shop shop; }
setup() {
  fixture_copy shop
  fakes
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# fakes: cp and du stand-ins first on PATH. FAKE_CP=refuse fails every clone (-c
# or --reflink) so the plain copy runs; FAKE_CP=clone drops the flag and copies,
# as a file system that clones would. du answers "du -sk PATH" from $SIZES (lines
# "name kb", by the path's last part), logs each call to $DU_LOG, naps DU_SLEEP
# seconds first when set, and runs the real du for a path the table lacks.
fakes() {
  local bin="$TEST_ROOT/fakebin"
  mkdir -p "$bin"
  cat > "$bin/cp" << SH
#!/bin/sh
for a in "\$@"; do case "\$a" in -c|--reflink|--reflink=*) [ "\${FAKE_CP:-refuse}" != refuse ] || exit 1 ;; esac; done
n=\$#; i=0
while [ \$i -lt \$n ]; do
  a=\$1; shift
  case "\$a" in -c|--reflink|--reflink=*) ;; *) set -- "\$@" "\$a" ;; esac
  i=\$((i + 1))
done
exec $(command -v cp) "\$@"
SH
  cat > "$bin/du" << SH
#!/bin/sh
[ -z "\${DU_SLEEP:-}" ] || sleep "\$DU_SLEEP"
[ -z "\${DU_LOG:-}" ] || printf '%s\n' "\$*" >> "\$DU_LOG"
p=""; for a in "\$@"; do case "\$a" in -*) ;; *) p=\$a ;; esac; done
n=\$(basename "\$p")
kb=""; [ ! -f "\${SIZES:-}" ] || kb=\$(awk -v n="\$n" '\$1 == n {print \$2}' "\$SIZES")
if [ -n "\$kb" ]; then printf '%s\t%s\n' "\$kb" "\$p"; else exec $(command -v du) "\$@"; fi
SH
  chmod +x "$bin/cp" "$bin/du"
  PATH="$bin:$PATH"
  export PATH
  export SIZES="$TEST_ROOT/sizes" DU_LOG="$TEST_ROOT/du.log"
  export FAKE_CP=refuse
  # data 1.5 GB, cache 512.0 MB, logs 100.0 MB, tmpd 1.0 MB: well over 500 MB in all.
  printf 'data 1572864\ncache 524288\nlogs 102400\ntmpd 1024\n' > "$SIZES"
}

LINE_RE="^vbw: .*data/ 1\.5 GB, cache/ 512\.0 MB, logs/ 100\.0 MB.*list them under ## Clean copy in \.vbw/spec\.md, then vbw spec sync"

# said: the one line, in $output, as an exact count.
said() { printf '%s\n' "$output" | grep -c '^vbw: .*Clean copy'; }

# stdout_only CMD...: run CMD with stderr dropped, so $output is stdout alone.
stdout_only() { run sh -c 'cmd=$1; shift; exec "$cmd" "$@" 2> /dev/null' _ "$VBW" "$@"; }

@test "R206: a plain copy of more than 500 MB prints one vbw: line on stderr naming the three largest folders with their sizes and the way out" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E "$LINE_RE" > /dev/null || { echo "$output"; false; }
  [[ "$output" != *"tmpd"* ]] || { echo "$output"; false; }
  jq -e '.evidence.passed == true' .vbw/record.json
  stdout_only prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 0 ] || { echo "the line is not on stderr:"; echo "$output"; false; }
}

@test "R206: the line changes nothing: verdict, evidence, record and exit code are the same with and without it" {
  local with without
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
  with=$(jq -c '.evidence | {passed, full, checks: (.checks | map_values({status, exit})), commands: (.commands | map_values(.status))}' .vbw/record.json)
  fixture_copy shop
  fakes
  VBW_PROOFCOPY_PLAIN_KB=999999999 vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 0 ] || { echo "$output"; false; }
  without=$(jq -c '.evidence | {passed, full, checks: (.checks | map_values({status, exit})), commands: (.commands | map_values(.status))}' .vbw/record.json)
  [ "$with" = "$without" ] || { echo "with: $with"; echo "without: $without"; false; }
}

@test "R206: nothing is printed when every ignored path was cloned copy-on-write, however large" {
  FAKE_CP=clone vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.passed == true' .vbw/record.json
}

@test "R206: nothing is printed at exactly 500 MB of plain-copied data; one byte more prints the line" {
  printf 'data 256000\ncache 256000\nlogs 0\ntmpd 0\n' > "$SIZES"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 0 ] || { echo "$output"; false; }
  printf 'data 256000\ncache 256001\nlogs 0\ntmpd 0\n' > "$SIZES"
  # --full makes the copy again (#738): a claimed kept copy copies no unchanged path.
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^vbw: .*cache/ 250\.0 MB, data/ 250\.0 MB' || { echo "$output"; false; }
}

@test "R206: the test-only threshold variable lowers the limit, so a few kilobytes measured on real files print the line" {
  rm -f "$SIZES"
  printf 'x\n' > data/a.bin
  VBW_PROOFCOPY_PLAIN_KB=1 vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E '^vbw: .*(data|cache|logs|tmpd)/ 0\.[0-9] MB' > /dev/null || { echo "$output"; false; }
}

@test "R206: nothing is printed when nothing ignored exists" {
  rm -rf data cache logs tmpd
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 0 ] || { echo "$output"; false; }
}

@test "R206: with two copies the line prints once, and each ignored path's size is read once per command, not per copy" {
  "$VBW" config set check_jobs 2 > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
  [ -f "$DU_LOG" ] || { echo "du never ran"; false; }
  [ "$(wc -l < "$DU_LOG" | tr -d ' ')" -eq 4 ] || { cat "$DU_LOG"; false; }
  [ "$(grep -c 'data$' "$DU_LOG")" -eq 1 ] || { cat "$DU_LOG"; false; }
}

@test "R206: the size reading counts in the copies step of VBW's own work" {
  DU_SLEEP=1 vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.own.copies >= 4' .vbw/record.json || { jq .evidence.own .vbw/record.json; false; }
}

@test "R206: vbw fix done prints the line once" {
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E "$LINE_RE" > /dev/null || { echo "$output"; false; }
}

@test "R206: vbw mutate's single form prints the line once, and the break's verdict stands" {
  printf 'unpaid\n' > src/pay.txt
  vbw_run mutate P1.1 R1.1 "unpaid" src/pay.txt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 red"* ]] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
}

@test "R206: vbw mutate --run prints the line once" {
  printf 'unpaid\n' > src/pay.txt
  "$VBW" mutate P1.1 R1.1 --queue "unpaid" src/pay.txt > /dev/null
  printf 'nothing\n' > src/pay.txt
  "$VBW" mutate P1.1 R1.2 --queue "nothing" src/pay.txt > /dev/null
  vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
}

@test "R206: the one run of vbw mutate Rn.k --none prints the line once" {
  vbw_run mutate P1.1 R1.1 --none "the check judges the record alone"
  [[ "$output" == *"ran C1 once"* ]] || { echo "$output"; false; }
  [ "$(said)" -eq 1 ] || { echo "$output"; false; }
}
