# PreToolUse guard for the file tools (docs/guards.md; inputs in common.jq).

include "common" {search: "./"};

input
| ((.tool_input // {}) | .file_path // .notebook_path // .path // "" | tostring) as $path
| (.tool_name | test("^(Write|Edit|MultiEdit|NotebookEdit)$")) as $writes
| if $writes and ($path | consent_path) then consent_reason
  elif in_vbw_project | not then empty
  elif $path | secret_path then $path | secret_reason
  elif $writes and ($path | record_path) then record_reason
  else empty end
| deny
