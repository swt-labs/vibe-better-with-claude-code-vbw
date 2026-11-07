#!/usr/bin/env bats
# R203 (P164): the user documentation and the Dev's instructions state when a
# rule may be recorded --none and how the kernel verifies it. docs/workflows.md
# ('The mutation check') no longer says a rule cannot be recorded this way; it
# says a rule may be --none when its check reads nothing any plan of its
# requirement builds, that the kernel verifies this from the check's recorded
# read list (the run store), and gives the refusal's wording ('break the rule
# in that code instead'). docs/proof.md ('The mutation check') says a rule whose
# check judges only the record (a measurement kept as a decision, for example)
# is recorded --none after the kernel verifies its read list, and that the
# command may run the check once and record that run. docs/record.md documents
# the plans' mutations entries, the rule --none shape {rule, none, at, head}
# included. plugin/agents/dev.md tells the Dev to use the rule form of --none
# only for such a rule and that the kernel verifies it. L1: the text of the
# documents and the prompt.

load helper

DOCS="$REPO_ROOT/docs"
DEV="$PLUGIN_ROOT/agents/dev.md"

# folded FILE: the file's text with line breaks folded to spaces (paragraphs wrap).
folded() { tr '\n' ' ' < "$1"; }
# states FILE REGEX: the folded text matches REGEX (extended, case-insensitive).
states() { folded "$1" | grep -Eiq -- "$2" || { echo "${1##*/} does not state /$2/"; return 1; }; }
# section FILE HEADING: the text of the markdown section HEADING (to the next heading of the same or a higher level), folded.
section() {
  awk -v h="$2" '
    index($0, h) == 1 { on = 1; lvl = match($0, /[^#]/) - 1; next }
    on && /^#/ { l = match($0, /[^#]/) - 1; if (l <= lvl) exit }
    on { print }' "$1" | tr '\n' ' '
}
# section_states FILE HEADING REGEX: the section matches REGEX.
section_states() { section "$1" "$2" | grep -Eiq -- "$3" || { echo "${1##*/} '$2' does not state /$3/:"; section "$1" "$2"; return 1; }; }

@test "R203: docs/workflows.md no longer says a rule cannot be recorded --none" {
  ! states "$DOCS/workflows.md" "a rule cannot be recorded this way" || { echo "docs/workflows.md still says a rule cannot be recorded this way"; false; }
}

@test "R203: docs/workflows.md says when a rule may be --none, how the kernel verifies it, and how a refusal reads" {
  section_states "$DOCS/workflows.md" "## The mutation check" 'vbw mutate P[0-9]+\.[0-9]+ R[0-9]+\.[0-9]+ --none'
  section_states "$DOCS/workflows.md" "## The mutation check" 'rule.*--none.*(reads|read list).*(nothing|none|no file).*plan'
  section_states "$DOCS/workflows.md" "## The mutation check" '(run store|runs\.json|recorded read list|read list it recorded)'
  section_states "$DOCS/workflows.md" "## The mutation check" 'break the rule in that code instead'
  section_states "$DOCS/workflows.md" "## The mutation check" '(reads the project through git|through git)'
}

@test "R203: the docs state the limit beside the rule: a check that only tests whether a plan file exists is not detected" {
  section_states "$DOCS/workflows.md" "## The mutation check" 'only +tests +whether +a +(plan +)?file +exists.*not +detected'
  section_states "$DOCS/proof.md" "### The mutation check" 'only +tests +whether +a +(plan +)?file +exists.*not +detected'
}

@test "R203: docs/proof.md says a rule whose check judges only the record is recorded --none after the kernel verifies its read list, and that the command may run the check once" {
  section_states "$DOCS/proof.md" "### The mutation check" '--none'
  section_states "$DOCS/proof.md" "### The mutation check" '(record|decision).*--none|--none.*(record|decision)'
  section_states "$DOCS/proof.md" "### The mutation check" 'verif.*read list|read list.*verif'
  section_states "$DOCS/proof.md" "### The mutation check" 'runs? (the|that|its) check once'
}

@test "R203: docs/record.md documents the plans' mutations entries, the rule --none shape included" {
  states "$DOCS/record.md" '`mutations`'
  states "$DOCS/record.md" 'mutations.*vbw mutate'
  states "$DOCS/record.md" 'mutations.*`rule`.*`none`.*`at`.*`head`|mutations.*rule.*\{.*req.*text.*\}.*none.*head'
  states "$DOCS/record.md" 'mutations.*`task`.*`none`|mutations.*task.*none'
  states "$DOCS/record.md" 'head.*40'
}

@test "R203: the Dev uses the rule form of --none only for a rule whose check reads nothing the plans build, and knows the kernel verifies it" {
  states "$DEV" 'R[0-9]+\.[0-9]+ --none'
  states "$DEV" '--none.*(only|solely).*(check|test).*(reads|read list).*(nothing|none|no file)|(check|test).*(reads|read list).*(nothing|none|no file).*--none'
  states "$DEV" '--none[^.]*(only|solely)[^.]*(kernel (verifies|checks|proves|judges)|verified by (vbw|the kernel))'
}

# R264 (T246): the docs state the git case beside the rule.
@test "R264 docs: docs/proof.md's mutation check section says a check that reads the project through git is recorded --none on its reason alone, marked git, listed at the next gate, and that a check with a read list never needs it" {
  section_states "$DOCS/proof.md" "### The mutation check" 'through git[^.]*--none|--none[^.]*through git'
  section_states "$DOCS/proof.md" "### The mutation check" '(reason alone|on the reason|its reason)[^.]*(git|vouch)|(git|vouch)[^.]*(reason alone|on the reason|its reason)'
  section_states "$DOCS/proof.md" "### The mutation check" 'git-read excuse|listed[^.]*(show contract|vbw ship|next gate|next approval)'
  section_states "$DOCS/proof.md" "### The mutation check" 'read list[^.]*(never|no) need|(never|no) need[^.]*read list'
}

@test "R264 docs: docs/workflows.md's mutate row and mutation check section name the git case, its mark and its listing" {
  grep -E '^\| *`vbw mutate' "$DOCS/workflows.md" | grep -qi 'git' || { echo "the mutate row does not name the git case"; false; }
  section_states "$DOCS/workflows.md" "## The mutation check" 'git-read excuse'
  section_states "$DOCS/workflows.md" "## The mutation check" 'no break possible'
}
