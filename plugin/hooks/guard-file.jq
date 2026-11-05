# PreToolUse guard for the file tools (docs/guards.md; inputs in common.jq).
# A path outside the hook's project is not judged here: the guard asks read.sh for the
# project it lands in (R254), which judges it by that project's record and lease. The
# answer is nothing, one decision, or that request, and always ends with the line
# vbw-guard-done.

include "holder" {search: "../lib"};
include "common" {search: "./"};

def run:
  guard_context(.tool_name | test("^(Write|Edit|MultiEdit|NotebookEdit)$")) as $g
  | (if $g.foreign == null then null else holder_name($g.foreign; foreign_stored_name($g.foreign); null) end) as $holder
  | $g.hook
  | ((.tool_input // {}) | .file_path // .notebook_path // .path // "" | tostring) as $path
  | (.tool_name | test("^(Write|Edit|MultiEdit|NotebookEdit)$")) as $writes
  | [select($writes) | $path | request_target($g; false)] as $out
  | if $writes and ($path | consent_path) then consent_reason | deny
    elif $g.project | not then empty
    elif $path | secret_path then $path | secret_reason | deny
    elif $writes and ($path | record_path) then record_reason | deny
    else
      ( [ if $writes and $g.foreign != null and ($path | project_path(session_dir($g); $root) | foreign_denial($g.foreign; $holder)) then
          $path | project_path(session_dir($g); $root) | foreign_denial($g.foreign; $holder) | deny
        elif $writes and $g.lease != null then
          $path | run_write_denial($g) | deny
        else empty end ] | .[0]
      ) as $own
      | if $own != null then $own
        elif $out != [] then request($g; $out)
        else empty end
    end;

run, "vbw-guard-done"
