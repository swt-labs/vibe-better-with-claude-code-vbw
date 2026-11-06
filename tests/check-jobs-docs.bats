#!/usr/bin/env bats
# R147 (docs/proof.md): the user docs state the machine-sized default for
# check_jobs (three quarters of the processor cores, at least 1, at most 64)
# and the command that returns to it; the old default of 4 is gone from docs,
# help and code comments; the config skill lists check_jobs. The shared limit
# (R148) and the single test command run of a fix round are behaviour, pinned
# by check-jobs-shared.bats and fix-suite-once.bats. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"

@test "R147: docs/proof.md describes the machine-sized default of check_jobs" {
  grep -qiE 'three quarters' "$DOC"
  grep -qiE 'processor cores|cores' "$DOC"
  grep -qiE 'at least 1|at least one' "$DOC"
  grep -qiE 'at most 64' "$DOC"
  grep -qF 'vbw config set check_jobs default' "$DOC"
}

@test "R147: the old default of 4 is gone from the docs, the help and the code comments" {
  local f
  for f in "$DOC" "$PLUGIN_ROOT/lib/core.sh" "$PLUGIN_ROOT/lib/cmd-config.sh" "$PLUGIN_ROOT/lib/checks.sh" "$PLUGIN_ROOT/bin/vbw"; do
    run grep -nE 'default 4|default: 4|means 4|defaults? to 4|four at a time' "$f"
    [ "$status" -ne 0 ] || { echo "$f: $output"; false; }
  done
  run "$VBW" help
  [[ "$output" != *"default 4"* ]] || { echo "$output"; false; }
}

@test "B2: the config skill lists check_jobs with its range and default, so /vbw:config can change it" {
  local skill="$PLUGIN_ROOT/skills/config/SKILL.md"
  grep -qE '^- `check_jobs`:' "$skill"
  grep -E '^- `check_jobs`:' "$skill" | grep -qE '1 to 64'
  grep -E '^- `check_jobs`:' "$skill" | grep -qiE 'three quarters'
  grep -E '^- `check_jobs`:' "$skill" | grep -qF '`default`'
}

# R256 and R257 (docs/proof.md, The computer-wide limit): the limit counts units running
# at once, not processor use; one unit may use more than one core (Cores per unit); units
# run at low priority (nice); a proof started inside another proof's unit takes one unit at
# a time by default, and the project's own check_jobs setting overrides it.

# limit_section: the text of "### The computer-wide limit", up to the next heading of the same or a higher level.
limit_section() { awk '/^### The computer-wide limit/{p=1; print; next} /^##(#)? /{p=0} p' "$DOC"; }

@test "R256: docs/proof.md's computer-wide limit section says the limit counts units running at once, not processor use, and that one unit may use more than one core (pointing to Cores per unit)" {
  local s
  s=$(limit_section)
  [ -n "$s" ] || { echo "no section 'The computer-wide limit'"; false; }
  printf '%s\n' "$s" | grep -qiE 'units? (running )?at once|units? at a time' || { echo "the section does not say the limit counts units at once"; false; }
  printf '%s\n' "$s" | grep -qiE 'not (processor|CPU) use|not how much (of the )?processor|not CPU' || { echo "the section does not say the limit is not processor use"; false; }
  printf '%s\n' "$s" | grep -qiE 'more than one core' || { echo "the section does not say one unit may use more than one core"; false; }
  printf '%s\n' "$s" | grep -qF 'Cores per unit' || { echo "the section does not point to Cores per unit"; false; }
}

@test "R256: docs/proof.md says units run at low priority (nice) so the machine stays usable, and what happens when nice is missing" {
  local s
  s=$(limit_section)
  printf '%s\n' "$s" | grep -qiE 'low priority' || { echo "the section does not say units run at low priority"; false; }
  printf '%s\n' "$s" | grep -qE '`nice`|nice' || { echo "the section does not name nice"; false; }
  printf '%s\n' "$s" | grep -qiE 'usable' || { echo "the section does not say the machine stays usable"; false; }
  printf '%s\n' "$s" | grep -qiE 'normal priority' || { echo "the section does not say what happens without nice"; false; }
}

@test "R257: docs/proof.md says a proof started inside another proof's unit takes one unit at a time by default, and that the project's check_jobs setting overrides it" {
  local s
  s=$(limit_section)
  printf '%s\n' "$s" | grep -qiE "inside another proof|inside a proof's unit|inside another proof's unit" || { echo "the section does not describe a proof inside a proof's unit"; false; }
  printf '%s\n' "$s" | grep -qiE 'one unit at a time' || { echo "the section does not say one unit at a time"; false; }
  printf '%s\n' "$s" | grep -qF 'VBW_PROOF_UNIT' || { echo "the section does not name the mark"; false; }
  printf '%s\n' "$s" | grep -qiE 'check_jobs.*(overrides|wins|still)|(overrides|wins).*check_jobs' || { echo "the section does not say the project's check_jobs overrides the nested default"; false; }
}
