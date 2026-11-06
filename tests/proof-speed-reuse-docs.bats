#!/usr/bin/env bats
# R202: docs/proof.md ("Reusing results") describes how a file a unit writes
# carries that unit's read list (kept once per run, by name, in the copy's
# written-file store) and what vbw next caches; docs/next.md names the cached
# proof sizing (.vbw/runtime/proof-units.json), its key (the committed tree,
# the record's fingerprint, the run store's digest) and when it is recomputed. L1.

load helper

PROOF="$REPO_ROOT/docs/proof.md"
NEXT="$REPO_ROOT/docs/next.md"

@test "R202: docs/proof.md says how written files carry read lists" {
  grep -qi 'a file a unit writes' "$PROOF" || grep -qi 'files a unit writes' "$PROOF"
  grep -qF 'written.json' "$PROOF"
}

@test "R202: docs/proof.md and docs/next.md name the cached proof sizing and when it is recomputed" {
  grep -qF 'proof-units.json' "$PROOF"
  grep -qF 'proof-units.json' "$NEXT"
  grep -qi 'committed tree' "$NEXT"
  grep -qi 'fingerprint' "$NEXT"
  grep -qi 'digest' "$NEXT"
  grep -qi 'recomputed' "$NEXT"
}

# R260 (T222, #745): docs/proof.md's reuse section says how a moved submodule is judged
# (a diff inside the submodule between the two commits, paths prefixed with its folder,
# the read-list rule) and names the cases that stay unknown (the recorded commit missing,
# a submodule added or removed, a nested submodule moved); the older rule, that any
# commit in a submodule runs everything again, is gone.

# reuse_section: docs/proof.md from "### Reusing results" to the next heading of the same or a higher level.
reuse_section() { awk '/^### Reusing results in/{p=1; print; next} /^##(#)? /{p=0} p' "$PROOF"; }

@test "R260 docs: docs/proof.md's reuse section says a moved submodule is diffed inside the submodule with its folder prefixed and judged by the read lists, and names the four cases that stay unknown" {
  local s
  s=$(reuse_section)
  [ -n "$s" ] || { echo "no section 'Reusing results in vbw prove'"; false; }
  printf '%s\n' "$s" | grep -qi 'submodule' || { echo "the section never mentions a submodule"; false; }
  printf '%s\n' "$s" | grep -qiE 'inside the submodule' || { echo "the section does not say the diff runs inside the submodule"; false; }
  printf '%s\n' "$s" | grep -qiE 'prefix' || { echo "the section does not say the paths are prefixed with the submodule folder"; false; }
  printf '%s\n' "$s" | grep -qiE 'read list' || { echo "the section does not tie a moved submodule to the read-list rule"; false; }
  printf '%s\n' "$s" | grep -qiE 'unknown' || { echo "the section does not name the unknown cases"; false; }
  printf '%s\n' "$s" | grep -qiE 'missing|no longer (in|has)|not (in|have)' || { echo "the section does not name a recorded commit missing from the submodule"; false; }
  printf '%s\n' "$s" | grep -qiE 'added' && printf '%s\n' "$s" | grep -qiE 'removed' || { echo "the section does not name an added or removed submodule"; false; }
  printf '%s\n' "$s" | grep -qiE 'nested' || { echo "the section does not name a moved nested submodule"; false; }
  ! grep -qF 'A commit in a submodule runs every check and command again' "$PROOF" || { echo "the older rule is still in docs/proof.md"; false; }
}
