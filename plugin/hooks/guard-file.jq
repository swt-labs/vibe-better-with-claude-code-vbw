# PreToolUse guard for the file tools (docs/guards.md; inputs in common.jq).

include "common" {search: "./"};

guard_context as $g
| $g.hook
| ((.tool_input // {}) | .file_path // .notebook_path // .path // "" | tostring) as $path
| (.tool_name | test("^(Write|Edit|MultiEdit|NotebookEdit)$")) as $writes
| if $writes and ($path | consent_path) then consent_reason
  elif $g.project | not then empty
  elif $path | secret_path then $path | secret_reason
  elif $writes and ($path | record_path) then record_reason
  elif $writes and $g.lease != null then
    $path | project_path($g.hook.cwd // $root; $root) | lease_write_denial($g.lease; $g.record)
  else empty end
| deny
