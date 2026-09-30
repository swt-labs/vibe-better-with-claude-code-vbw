#!/usr/bin/env bash
# Baseline runner: measures v1 VBW and plain Claude Code on the same tasks.
#
#   run.sh v1    <repo> <ref> <out.json> [eval options...]
#   run.sh plain <out.json> [eval options...]
#
# Arm "v1" assembles <ref> of the VBW repo as the plugin under test and
# prefixes each request with the case's v1 slash command. Arm "plain" loads an
# empty plugin and sends the bare request. Both arms use the same fixtures and
# graders, and run with --ablation none (a v1 slash command means nothing
# without the plugin, so the built-in no-plugin arm would not be a fair
# baseline). Extra options (e.g. --runs 1 --model sonnet --max-cost-usd 5
# --case fix-oneshot) are passed to `claude plugin eval`.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
arm="${1:-}"
case "$arm" in
  v1)
    [ $# -ge 4 ] || { echo "usage: run.sh v1 <repo> <ref> <out.json> [eval options...]" >&2; exit 2; }
    repo="$2"; ref="$3"; out="$4"; shift 4 ;;
  plain)
    [ $# -ge 2 ] || { echo "usage: run.sh plain <out.json> [eval options...]" >&2; exit 2; }
    out="$2"; shift 2 ;;
  *) echo "usage: run.sh v1|plain ..." >&2; exit 2 ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/vbw-baseline.XXXXXX")"
plugin="$work/plugin"
mkdir -p "$plugin"

if [ "$arm" = "v1" ]; then
  git -C "$repo" archive "$ref" | tar -x -C "$plugin"
else
  mkdir -p "$plugin/.claude-plugin"
  printf '%s\n' '{"name":"plain-baseline","version":"0.0.0","description":"Empty plugin: plain Claude Code baseline"}' \
    > "$plugin/.claude-plugin/plugin.json"
fi

meta() { sed -n "s/^$2=//p" "$1/case.meta"; }

rm -rf "$plugin/evals"
for case_dir in "$HERE"/cases/*/; do
  name="$(basename "$case_dir")"
  dest="$plugin/evals/$name"
  mkdir -p "$dest"
  cp -R "$case_dir/graders" "$dest/graders"
  fixture="$(meta "$case_dir" fixture)"
  cp "$HERE/fixtures/$fixture/fixture.sh" "$dest/fixture.sh"
  request="$(cat "$case_dir/request.txt")"
  if [ "$arm" = "v1" ]; then
    cp "$plugin/config/defaults.json" "$dest/v1-defaults.json"
    request="$(meta "$case_dir" v1_command) $request"
  fi
  {
    printf -- '---\n'
    printf 'max_turns: %s\n' "$(meta "$case_dir" max_turns)"
    printf 'timeout_seconds: %s\n' "$(meta "$case_dir" timeout_seconds)"
    printf 'allowed_tools: [Read, Glob, Grep, Skill, Agent]\n'
    printf -- '---\n'
    printf '%s\n' "$request"
  } > "$dest/prompt.md"
  printf 'schema_version: "1.1"\nname: %s\ncontext:\n  scaffold_script: fixture.sh\n' "$name" > "$dest/case.yaml"
done

echo "assembled: $plugin" >&2
(cd "$plugin" && claude plugin eval . --ablation none --scaffold --trust-plugin --no-publish \
  --allow-tools Write Edit Bash --json "$out" "$@")
