#!/usr/bin/env bats
# R241 (#694, D555, D556, L1): the MCP tool list is a project setting, record.settings.mcp,
# set with `vbw config set mcp VALUE` and shown by `vbw config`. VALUE is entries separated by
# spaces: SERVER (open to the writing agents), SERVER:read-only (a pure server, open to
# every agent) or SERVER:read-only=TOOL,TOOL (a mixed server: these tools open to every
# agent, the rest to the writing agents); names are letters, digits, _ . and -; `default`
# removes the setting. A malformed entry is refused with a usage line naming the accepted
# form and changes nothing. The record carries the setting as schema 7, so an older VBW
# asks for an update instead of calling the record corrupt; the config skill and the
# README's settings table know the key.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

VALUE='github:read-only ctx:read-only=search,get_context playwright'

@test "R241: vbw config set mcp stores each entry with its mark in record.settings.mcp, in the order given, and prints the setting" {
  vbw_run config set mcp "$VALUE"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "mcp = $VALUE" ] || { echo "$output"; false; }
  jq -e '.settings.mcp == [{server: "github", read_only: true}, {server: "ctx", read_only: ["search", "get_context"]}, {server: "playwright", read_only: false}]' .vbw/record.json \
    || { jq .settings .vbw/record.json; false; }
  jq -e '.schema == 7' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json), not 7"; false; }
}

@test "R241: vbw config shows the setting in the form it was set, and 'mcp: none' without one" {
  vbw_run config
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'mcp: none' || { echo "$output"; false; }
  "$VBW" config set mcp "$VALUE" > /dev/null
  vbw_run config
  printf '%s\n' "$output" | grep -qxF "mcp: $VALUE" || { echo "$output"; false; }
}

@test "R241: default removes the setting and the record goes back to schema 4" {
  "$VBW" config set mcp "$VALUE" > /dev/null
  vbw_run config set mcp default
  [ "$status" -eq 0 ] && [ "$output" = "mcp = default" ] || { echo "$output"; false; }
  jq -e '(.settings | has("mcp") | not) and .schema == 4' .vbw/record.json || { jq '{schema, settings}' .vbw/record.json; false; }
}

@test "R241: a malformed server or tool name, mark or list is refused with a usage line naming the accepted form, and nothing changes" {
  "$VBW" config set mcp "github:read-only" > /dev/null
  local bad
  for bad in 'git/hub''github:rw' 'github:read-only=' 'github:read-only=a,,b' ':read-only' '-github' 'github:' 'github:read-only=run!' 'github:read-only=-x' 'github:read-only=ok,.y' 'github github' '' 'github:read-only:x'; do
    vbw_run config set mcp "$bad"
    [ "$status" -eq 2 ] || { echo "accepted: '$bad' -> $output"; false; }
    [[ "$output" == *"SERVER:read-only=TOOL,TOOL"* && "$output" == *"SERVER:read-only"* ]] || { echo "the refusal of '$bad' does not name the accepted form: $output"; false; }
    jq -e '.settings.mcp == [{server: "github", read_only: true}]' .vbw/record.json > /dev/null || { echo "'$bad' changed the setting"; false; }
  done
}

@test "R241: settings.mcp under schema 6 loads and the next write raises the record to 7 (D582); schema 7 without it and a malformed stored entry are refused" {
  "$VBW" config set mcp "$VALUE" > /dev/null
  cp .vbw/record.json "$TEST_ROOT/good.json"
  jq '.schema = 6' "$TEST_ROOT/good.json" > .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$VBW" decide "raise it" > /dev/null
  jq -e '.schema == 7' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json) after the write, not 7"; false; }
  jq '.settings |= del(.mcp)' "$TEST_ROOT/good.json" > .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ] && [[ "$output" == *"schema 7"* ]] || { echo "$output"; false; }
  jq '.settings.mcp[0].read_only = "yes"' "$TEST_ROOT/good.json" > .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ] && [[ "$output" == *"settings.mcp"* ]] || { echo "$output"; false; }
  jq '.settings.mcp += [{server: "github", read_only: false}]' "$TEST_ROOT/good.json" > .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ] && [[ "$output" == *"settings.mcp"* ]] || { echo "a server named twice passed: $output"; false; }
}

@test "R241: a VBW that reads only up to schema 6 says the project needs a newer VBW, never that the record is corrupt" {
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  sed -i.bak 's/^VBW_SCHEMA_MAX=.*$/VBW_SCHEMA_MAX=6/' "$TEST_ROOT/plugin/lib/record.sh"
  grep -qx 'VBW_SCHEMA_MAX=6' "$TEST_ROOT/plugin/lib/record.sh"
  "$VBW" config set mcp "$VALUE" > /dev/null
  run "$TEST_ROOT/plugin/bin/vbw" status < /dev/null
  [ "$status" -eq 4 ] && [[ "$output" == *"needs a newer VBW"* ]] || { echo "$output"; false; }
}

@test "R241: the config skill and the README's settings table know the mcp key, its form and its read-only mark" {
  local s="$PLUGIN_ROOT/skills/config/SKILL.md" line
  grep -q '`mcp`' "$s" || { echo "the config skill has no mcp key"; false; }
  line=$(grep '`mcp`' "$s")
  [[ "$line" == *"read-only"* && "$line" == *"SERVER:read-only=TOOL"* ]] || { echo "the skill's mcp line does not give the form and the mark: $line"; false; }
  grep -qE '^\| `mcp` \|' "$REPO_ROOT/README.md" || { echo "the README's settings table has no mcp row"; false; }
  grep -E '^\| `mcp` \|' "$REPO_ROOT/README.md" | grep -q 'read-only' || { echo "the README's mcp row does not mention the read-only mark"; false; }
}
