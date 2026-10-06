#!/usr/bin/env bats
# R71 (F41, F42, D144): documentation is defined once, in rigor-defs.jq
# (is_doc: .md, .markdown, .rst; plain .txt is data and keeps its check), and
# every reader uses that definition: the early tier's count of code files in
# vbw next, and the Lead's instructions. L1: the texts.

load helper

@test "R71: the early tier counts code with the shared definition, not a list of its own" {
  grep -q 'is_doc' "$PLUGIN_ROOT/lib/cmd-next.sh"
  ! grep -nE '\(md\|markdown(\|txt|\|rst)' "$PLUGIN_ROOT/lib/cmd-next.sh"
}

@test "R71: the Lead is told documentation is markdown and rst, and plain text keeps its check" {
  grep -q 'markdown, rst' "$PLUGIN_ROOT/agents/lead.md"
  ! grep -q 'markdown, text, rst' "$PLUGIN_ROOT/agents/lead.md"
}

@test "R71: the one definition is markdown and reStructuredText only" {
  grep -qF 'def is_doc: test("\\.(md|markdown|rst)$"; "i");' "$PLUGIN_ROOT/lib/rigor-defs.jq"
}
