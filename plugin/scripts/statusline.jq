# The VBW status line (docs/statusline.md). $cc: Claude Code's status line
# JSON ({} when it sent none). Inputs, in order: plugin.json; the
# project's .vbw/record.json, or its smaller glance.json when newer, if it exists; the sentinel; .vbw/runtime/next.json
# if it exists (the last `vbw next`); the sentinel; the running step's note
# .vbw/runtime/step.json if it exists (R190, the kernel's; this program works
# no time out); the sentinel; this session's .vbw/runtime/auto.SESSION.json if
# it armed an autonomous run. jq skips missing files, so the sentinels mark which
# optional input is which. Args: $branch, $color ("1" or ""), $sid (this session),
# $registry ([{sessionId: name}] of Claude Code's list of chats, [{}] without one),
# $deadpid (the pid of a proof note whose process is gone, or 0),
# $legacy (a VBW 1 plan, not converted), $agents (the workflow agents working
# now: [{role, label, model}]), $profiles ([lib/profiles.json]). Output: 4
# lines; in a VBW project under Claude Code older than 2.1.287, 5 (the team or
# its working agents on line 2); then, when $cc carries a cost, one last line of
# compact JSON for the cost side file.

include "holder" {search: "../lib"};

def c($code; $s): if $color == "1" then "\u001b[\($code)m\($s)\u001b[0m" else $s end;
def dim: c("2"; .);
def bar($pct): ($pct // 0 | floor | if . < 0 then 0 elif . > 100 then 100 else . end) as $p
  | (($p + 5) / 10 | floor) as $n
  | ([range(0; $n)] | map("▓") | join("")) + ([range(0; 10 - $n)] | map("░") | join(""))
  | c(if $p >= 80 then "31" elif $p >= 50 then "33" else "32" end; .);
def tokens: if . == null then "?" elif . >= 1000000 then "\(. / 100000 | floor / 10)M"
  elif . >= 1000 then "\(. / 100 | floor / 10)K" else "\(.)" end;
def dur: (. // 0) / 1000 | floor
  | if . >= 3600 then "\(. / 3600 | floor)h\(. % 3600 / 60 | floor)m"
    elif . >= 60 then "\(. / 60 | floor)m\(. % 60)s" else "\(.)s" end;
def until_reset($now): if . == null then "" else (. - $now) as $s
  | if $s <= 0 then "" elif $s >= 86400 then " (resets \($s / 86400 | floor)d)"
    elif $s >= 3600 then " (resets \($s / 3600 | floor)h\($s % 3600 / 60 | floor)m)"
    else " (resets \($s / 60 | floor)m)" end end;
def sep: " │ " | dim;
# Each role keeps one colour wherever it appears.
def role_color: {architect: "35", lead: "34", dev: "32", qa: "33", scout: "36", debugger: "31", docs: "95"}[.] // "37";
def roles: ["architect", "lead", "dev", "qa", "scout", "debugger", "docs"];
def agent_dot($role): c($role | role_color; "●");
def progress($done; $total): (if $total > 0 then $done * 100 / $total else 0 end) as $p
  | (($p + 5) / 10 | floor) as $n
  | c("32"; [range(0; $n)] | map("▓") | join("")) + c("2"; [range(0; 10 - $n)] | map("░") | join(""));

[inputs] as $in
| ($in | index("vbw-guard-end")) as $s1
| ($in[0] // {}) as $plugin
| (if $s1 != null and $s1 >= 2 then $in[1] else null end) as $rec
| ($in[($s1 // 0) + 1:]) as $rest
| ($rest | index("vbw-guard-end")) as $s2
| (if $s2 != null and $s2 >= 1 then $rest[0] else null end) as $next
| (if $s2 != null then $rest[$s2 + 1:] else [] end) as $rest2
| ($rest2 | index("vbw-guard-end")) as $s3
| (if $s3 != null and $s3 >= 1 then $rest2[0] else null end) as $stepnote
| (if $s3 != null then $rest2[$s3 + 1] else null end) as $auto
| now as $now
# The step's note counts for a build, fix, plan or QA while its run is the open
# run; a proof's, while its own session's and its process lives (the shell tells
# a dead one by $deadpid). A step is shown only from the note, never worked out.
| (if ($stepnote | type) == "object" and ($rec | type) == "object" then
     if $stepnote.kind == "proof" then
       (if ($stepnote.session // "") == $sid and $sid != "" and $stepnote.pid != $deadpid then $stepnote else null end)
     elif $rec.lease != null and $stepnote.run == $rec.lease.run then $stepnote
     else null end
   else null end) as $step
# A clock time, local 24-hour; another day names the day as the kernel does
# (step_clock in plugin/lib/steps.sh): tomorrow, yesterday, or the weekday.
| def day($e): $e | localtime | mktime / 86400 | floor;
  def clock($t): ($t | fromdateiso8601) as $e
    | ($e | strflocaltime("%H:%M")) as $hm
    | (day($e) - day($now)) as $d
    | if $d == 0 then $hm elif $d == 1 then "tomorrow " + $hm elif $d == -1 then "yesterday " + $hm
      else ($e | strflocaltime("%A ")) + $hm end;
  def mins($t): if $t == null then null else ((($now - ($t | fromdateiso8601)) / 60 | floor) as $m | if $m >= 1 then "\($m) min" else null end) end;
  def step_line($n):
    ($n.parts) as $p
    | (if ($n.proof != null and $n.kind != "proof") then $n.kind + (if ($n.ids | length) > 0 then " " + ($n.ids | join(", ")) else "" end) + " · " + $n.doing
       elif $n.kind == "proof" then $n.doing
       elif $p != null then "\($n.doing) · \($p.done) of \($p.total)" else $n.doing end) as $what
    | (if $n.end == null then null
       else (if ($n.rough == true) and $n.end_low != null and $n.end_high != null
               then (clock($n.end_low) as $lo | clock($n.end_high) as $hi
                 | "until ~" + (if $lo == $hi then $lo else $lo + "-" + $hi end))
               else "until around " + clock($n.end) end)
         + (if $p != null then (if $n.late == true or (($n.end | fromdateiso8601) <= $now) then ", later than usual" else "" end)
            else ((($now - ($n.first_end // $n.end | fromdateiso8601)) / 60 | floor) as $m | if $m >= 1 then ", \($m) min late" else "" end) end)
       end) as $until
    | ([mins($n.started_at), $until] | map(select(. != null)) | join(", ")) as $time
    | [$what, (if $time != "" then $time else null end)] | map(select(. != null)) | join(" · ");
  .
# Claude Code 2.1.287 and later shows the working agents and the team in its own
# panes, so line 2 is left out there; older (or unreported) versions keep it.
| (($cc.version // "") | if type == "string" then [scan("[0-9]+") | tonumber][0:3] >= [2, 1, 287] else false end) as $slim

# A proof's note names its process first: the script checks it lives.
| ( select($step != null and $step.kind == "proof" and ($step.pid | type) == "number") | {step_pid: $step.pid} | tojson ),

# Line 1: VBW
  ( if ($rec | type) != "object" then
      c("36"; "[VBW]") + " " + (if $legacy != "" then "VBW 1 plan here · /vbw:vibe to bring it into VBW 2" else "no project here · /vbw:vibe to start" end | dim)
    else
      [$rec.requirements[]? | select(.milestone == $rec.milestone.id)] as $cur
      | ([$cur[] | select(.status == "proven" or .status == "accepted")] | length) as $done
      | ($cur | length) as $total
      | ($agents | length) as $n_agents
      | (if $n_agents > 0 then " · \($n_agents) agent\(if $n_agents == 1 then "" else "s" end) working" else "" end) as $working
      | (if $rec.lease == null or (($rec.lease.session // "") == "") then ""
         elif $rec.lease.session == $sid then " · leading"
         else " · held by " + (holder_name($rec.lease; $rec.holder.session_name; ($registry[0] // {})[$rec.lease.session]) | cut_name(20)) end) as $lead
      | ($rec.milestone as $m | [$rec.shipped[]? | select(.id == $m.id) | .at][0]) as $shipped_at
      | (if $step != null then c("38;5;141"; "● working: " + step_line($step) + $working + $lead)
         elif $rec.lease != null then
           c("38;5;141"; "● working: " + (if $rec.lease.kind == "build" then "building " + ([$rec.plans[]? | select(.status == "building") | .id] | join(", ")) else $rec.lease.kind end)
             + (mins($rec.lease.started_at) | if . == null then "" else " · " + . end) + $working + $lead)
         elif $n_agents > 0 then c("38;5;141"; "● working: \($n_agents) agent\(if $n_agents == 1 then "" else "s" end)")
         elif $next != null and $next.gate then c("38;5;214"; "⚑ needs you: \($next.action)"
           + (if ($next.since | type) == "string" then " · since " + clock($next.since) else "" end))
         elif $rec.milestone.status == "shipped" then c("38;5;77"; "✓ idle: \($rec.milestone.id) shipped" + (if $shipped_at != null then " " + clock($shipped_at) else "" end))
         elif $next != null then c("38;5;77"; "✓ idle: \($next.action) is next")
         else c("38;5;77"; "✓ idle: /vbw:vibe is next") end) as $state
      | c("36"; "[VBW]") + " " + c("1"; $rec.project.name) + sep
        + "\($rec.milestone.id) \($rec.milestone.title | if length > 40 then (.[0:39] | sub("\\s+$"; "")) + "…" else . end)" + (if $rec.milestone.status == "shipped" then " ✓" else "" end) + sep
        + progress($done; $total) + " \($done)/\($total) done" + sep + $state
        + (if ($auto | type) == "object" then sep + c("35"; "⟳ auto \($auto.steps)/\($auto.cap)") else "" end)
    end ),

# Line 2 (VBW projects, Claude Code before 2.1.287): the agents working now, each
# in its role's colour with its label and model; otherwise the team: each role's
# model, the profile and how much VBW does on its own.
  ( select(($rec | type) == "object" and ($slim | not))
    | if ($agents | length) > 0 then
        "Agents " + ([$agents[0:6][] | agent_dot(.role) + " " + c(.role | role_color; .role)
            + ((.role as $r | .label | ltrimstr($r) | ltrimstr(" ")) as $l | if $l != "" then " " + $l else "" end)
            + (if .model != "" then " " + (.model | dim) else "" end)] | join("  "))
        + (if ($agents | length) > 6 then "  " + ("+\(($agents | length) - 6) more" | dim) else "" end)
      else
        ($rec.settings // {}) as $s
        | ((($profiles[0] // {})[$s.profile // "balanced"] // {}) + ($s.models // {}) | if ((.qa // "") | ascii_downcase | contains("haiku")) then .qa = "sonnet" else . end) as $m
        # Grouped by model, in the team's order: "sonnet ● architect ● lead ...".
        | ([roles[] as $r | {role: $r, model: ($m[$r] // "?")}] | group_by(.model) | sort_by(.[0].role as $r | roles | index($r))) as $groups
        | "Team   " + ([$groups[] | (.[0].model | dim) + " " + ([.[] | agent_dot(.role) + " " + c(.role | role_color; .role)] | join(" "))] | join(sep))
          + sep + "profile \($s.profile // "balanced")" + (" · " | dim) + "autonomy \($s.autonomy // "balanced")"
      end ),

# Line 3: context, tokens, prompt cache and cost
  ( ($cc.context_window // {}) as $w
    | "Context " + bar($w.used_percentage) + " \($w.used_percentage // 0 | floor)% "
      + ((($w.total_input_tokens // 0)) | tokens) + "/" + ($w.context_window_size | tokens)
      + (($w.current_usage // null) as $u | if $u == null then "" else
          (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $all
          | sep + "Tokens \($u.input_tokens // 0 | tokens) in \($u.output_tokens // 0 | tokens) out"
          + sep + "Cache " + (if $all > 0 then (($u.cache_read_input_tokens // 0) * 100 / $all | floor) as $h
                | c(if $h >= 80 then "32" elif $h >= 50 then "33" else "31" end; "\($h)% hit") else "–" end)
          + " \($u.cache_creation_input_tokens // 0 | tokens) write \($u.cache_read_input_tokens // 0 | tokens) read" end)
      + sep + "Cost $\(($cc.cost.total_cost_usd // 0) * 100 | round / 100)"
      + sep + c("32"; "+\($cc.cost.total_lines_added // 0)") + " " + c("31"; "−\($cc.cost.total_lines_removed // 0)") ),

# Line 4: plan limits (subscribers only)
  ( ($cc.rate_limits // {}) as $l
    | if ($l.five_hour == null and $l.seven_day == null) then "Limits " + ("not reported for this account" | dim)
      else "Limits "
        + (if $l.five_hour then "5h " + bar($l.five_hour.used_percentage) + " \($l.five_hour.used_percentage | floor)%"
             + ($l.five_hour.resets_at | until_reset($now)) else "" end)
        + (if $l.five_hour and $l.seven_day then sep else "" end)
        + (if $l.seven_day then "7d " + bar($l.seven_day.used_percentage) + " \($l.seven_day.used_percentage | floor)%"
             + ($l.seven_day.resets_at | until_reset($now)) else "" end)
      end ),

# Line 5: model, time, branch, versions
  ( ($cc.model.display_name // "model ?") + sep
    + "\($cc.cost.total_duration_ms | dur) (API \($cc.cost.total_api_duration_ms | dur))"
    + (if $branch != "" then sep + $branch else "" end)
    + sep + "VBW \($plugin.version // "?")" + sep + "CC \($cc.version // "?")" ),

# Last line, only when Claude Code sent a cost: the side-file record as compact
# JSON ({session, usd, at}); the script splits it off and stores it. Only the
# dollars are stored: cost.total_cost_usd is the session's running total, but the
# context_window token fields describe the last request (the context's size now,
# the last response's output), so they are no spend to diff.
  ( select($cc.cost.total_cost_usd != null)
    | {session: $cc.session_id, usd: $cc.cost.total_cost_usd, at: ($now | strftime("%Y-%m-%dT%H:%M:%SZ"))} | tojson )
