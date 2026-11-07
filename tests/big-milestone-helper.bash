# shellcheck shell=bash
# The big-milestone fixture (R268). Load after helper:
#   load helper
#   load big-milestone-helper
#
# One active milestone shaped like the field report that made vbw next take 59 s:
# 79 phases (P1 to P79, one [auto] requirement and one check each), 258 plans
# (4 in each of P1 to P21, 3 in each of P22 to P79), 568 after-links and 47
# interleaved phases: 22 pairs (P1 and P2, P3 and P4, ... P43 and P44, where
# B.1 comes after A.1 and A.2 after B.1) and one ring of three (P45, P46, P47:
# P46.1 after P45.1, P47.1 after P46.1, P45.2 after P47.1). The plans stay
# acyclic. The other after-links point at earlier plans only: each plan after
# the one before it in its phase, Pn.1 after P(n-1).1, every later plan after
# P(n-2).1, each phase's last plan after P(n-3).2, and P6.1 to P44.1 after
# P(n-5).3. The plans of P1 to P40 are done, with their files committed, and
# P1 to P30 carry a QA pass, so the QA listing, the digests and the settle have
# work to do. The contract is approved. The fixture reproduces the shape only:
# the fix it serves is the general one (one graph walk, one tree read per
# repository), not a tuning for that project.

BIG_PHASES=79
BIG_PLANS=258
BIG_LINKS=568
# shellcheck disable=SC2034 # read by tests/big-milestone.bats
BIG_INTERLEAVED=47

# big_milestone_doc: the vbw apply document of the milestone.
big_milestone_doc() {
  jq -nc --argjson n "$BIG_PHASES" '
    def plans_of($p): if $p <= 21 then 4 else 3 end;
    def pair_a($p): $p <= 44 and ($p % 2 == 1);
    def pair_b($p): $p <= 44 and ($p % 2 == 0);
    def after($p; $k):
      ( [ if $k > 1 then "P\($p).\($k - 1)" else empty end,
          if $k == 1 and $p >= 2 then "P\($p - 1).1" else empty end,
          if $k >= 2 and $p >= 3 then "P\($p - 2).1" else empty end,
          if $k == plans_of($p) and $p >= 4 then "P\($p - 3).2" else empty end,
          if $k == 1 and $p >= 6 and $p <= 44 then "P\($p - 5).3" else empty end,
          if $k == 2 and pair_a($p) then "P\($p + 1).1" else empty end,
          if $k == 2 and $p == 45 then "P47.1" else empty end ]
        | unique );
    [range(1; $n + 1)] as $ps
    | {phases: [$ps[] | {id: "P\(.)", title: "Part \(.)", reqs: ["R\(.)"], goal: "Part \(.) works", criteria: ["src/p\(.)-1.txt says part\(.)"], tier: "standard"}],
       plans: [$ps[] as $p | range(1; plans_of($p) + 1) as $k
               | {id: "P\($p).\($k)", phase: "P\($p)", title: "Write part \($p) piece \($k)", reqs: ["R\($p)"],
                  files: ["src/p\($p)-\($k).txt"], after: after($p; $k), role: "dev",
                  tasks: ["write piece \($k)", "check piece \($k)", "note piece \($k)"]}],
       checks: [$ps[] | {id: "C\(.)", req: "R\(.)", run: ["sh", "tests/c\(.).sh"], files: ["tests/c\(.).sh"]}],
       rules: [$ps[] | {req: "R\(.)", text: "src/p\(.)-1.txt holds part\(.)", check: "C\(.)"}]}'
}

# big_milestone_project: the fixture at $PROJECT (after vbw_setup).
big_milestone_project() {
  local i k
  vbw_git_project
  "$VBW" init > /dev/null || return 1
  mkdir -p src tests
  {
    printf '# Big\n\n## Requirements\n\n'
    for ((i = 1; i <= BIG_PHASES; i++)); do printf -- '- R%d [auto] Part %d works\n' "$i" "$i"; done
  } > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  for ((i = 1; i <= BIG_PHASES; i++)); do printf 'grep -qx part%d src/p%d-1.txt\n' "$i" "$i" > "tests/c$i.sh"; done
  big_milestone_doc > .vbw/runtime/big-doc.json
  jq -e --argjson p "$BIG_PLANS" --argjson l "$BIG_LINKS" '(.plans | length) == $p and ([.plans[].after[]] | length) == $l' .vbw/runtime/big-doc.json > /dev/null \
    || { echo "the big-milestone document has not the field report's shape"; jq -c '{plans: (.plans | length), links: ([.plans[].after[]] | length)}' .vbw/runtime/big-doc.json; return 1; }
  "$VBW" apply < .vbw/runtime/big-doc.json > /dev/null || return 1
  rm -f .vbw/runtime/big-doc.json
  git add -A && git commit -q -m "chore(vbw): plan the big milestone" || return 1
  "$VBW" approve > /dev/null || return 1
  # Built as the twin fixture is: the files committed and the plans marked done by hand, so
  # no build run is needed; P1 to P30 passed QA at a tree no digest matches.
  for ((i = 1; i <= 40; i++)); do
    for k in 1 2 3 4; do
      [ "$i" -le 21 ] || [ "$k" -le 3 ] || continue
      printf 'part%d\n' "$i" > "src/p$i-$k.txt"
    done
  done
  jq '.plans |= map(if (.phase | ltrimstr("P") | tonumber) <= 40 then .status = "done" else . end)
    | .phases |= map(if (.id | ltrimstr("P") | tonumber) <= 30
        then .qa = {result: "pass", tier: "standard", tree: "0000000000000000000000000000000000000000", at: "2026-01-01T00:00:00Z"} else . end)' \
    .vbw/record.json > .vbw/runtime/built.json || return 1
  cat .vbw/runtime/built.json > .vbw/record.json
  rm -f .vbw/runtime/built.json .vbw/runtime/glance.json
  git add -A && git commit -q -m "chore(test): built P1 to P40" || return 1
}

# big_milestone_fixture: a test root holding the fixture, for fixture_build in
# setup_file (fixture-helper.bash).
big_milestone_fixture() {
  vbw_setup
  big_milestone_project
}

# big_norm: stdin with what legitimately differs between two builds of the fixture
# removed: the test root, hashes and commit ids, times and durations.
big_norm() {
  jq -Rr --arg root "$TEST_ROOT" '
    split($root) | join("<root>")
    | gsub("\\b[0-9a-f]{7,64}\\b"; "<hex>")
    | gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"; "<time>")
    | gsub("[0-9]{8}T[0-9]{6}Z"; "<time>")
    | gsub("\\b[0-9]+(\\.[0-9]+)? ?(ms|s|sec|seconds?|min|minutes?)\\b"; "<dur>")'
}
