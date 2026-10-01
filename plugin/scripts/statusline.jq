# The VBW status line (docs/statusline.md). $cc: Claude Code's status line
# JSON ({} when it sent none). Inputs, in order: plugin.json; the
# project's .vbw/record.json if it exists; the sentinel; .vbw/runtime/next.json
# if it exists (the last `vbw next`); the sentinel; .vbw/runtime/auto.json if an
# autonomous run is armed. jq skips missing files, so the sentinels mark which
# optional input is which. Args: $branch, $color ("1" or ""),
# $legacy (a VBW 1 plan, not converted), $agents (the workflow agents working
# now: [{role, label, model}]), $profiles ([lib/profiles.json]). Output: 5
# lines in a VBW project (the team or its working agents on line 2), else 4.

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
| (if $s2 != null then $rest[$s2 + 1] else null end) as $auto
| now as $now

# Line 1: VBW
| ( if ($rec | type) != "object" then
      c("36"; "[VBW]") + " " + (if $legacy != "" then "VBW 1 plan here · /vbw:vibe to bring it into VBW 2" else "no project here · /vbw:vibe to start" end | dim)
    else
      [$rec.requirements[]? | select(.milestone == $rec.milestone.id)] as $cur
      | ([$cur[] | select(.status == "proven" or .status == "accepted")] | length) as $done
      | ($cur | length) as $total
      | ($agents | length) as $n_agents
      | (if $n_agents > 0 then " · \($n_agents) agent\(if $n_agents == 1 then "" else "s" end) working" else "" end) as $working
      | (if $rec.lease != null then
           c("36"; "▶ \($rec.lease.kind)\(if $rec.lease.kind == "build" then ": " + ([$rec.plans[]? | select(.status == "building") | .id] | join(", ")) else "" end)"
             + (($now - ($rec.lease.started_at | fromdateiso8601? // $now)) * 1000 | " " + dur) + $working)
         elif $n_agents > 0 then c("36"; "▶ \($n_agents) agent\(if $n_agents == 1 then "" else "s" end) working")
         elif $next != null and $next.gate then c("33"; "needs you: \($next.action)")
         elif $next != null then "next: \($next.action)"
         else "next: /vbw:vibe" end) as $state
      | c("36"; "[VBW]") + " " + c("1"; $rec.project.name) + sep
        + "\($rec.milestone.id) \($rec.milestone.title | if length > 40 then (.[0:39] | sub("\\s+$"; "")) + "…" else . end)" + (if $rec.milestone.status == "shipped" then " ✓" else "" end) + sep
        + progress($done; $total) + " \($done)/\($total) done" + sep + $state
        + (if ($auto | type) == "object" then sep + c("35"; "⟳ auto \($auto.steps)/\($auto.cap)") else "" end)
    end ),

# Line 2 (VBW projects): the agents working now, each in its role's colour with
# its label and model; otherwise the team: each role's model, the profile and
# how much VBW does on its own.
  ( select(($rec | type) == "object")
    | if ($agents | length) > 0 then
        "Agents " + ([$agents[0:6][] | agent_dot(.role) + " " + c(.role | role_color; .role)
            + ((.role as $r | .label | ltrimstr($r) | ltrimstr(" ")) as $l | if $l != "" then " " + $l else "" end)
            + (if .model != "" then " " + (.model | dim) else "" end)] | join("  "))
        + (if ($agents | length) > 6 then "  " + ("+\(($agents | length) - 6) more" | dim) else "" end)
      else
        ($rec.settings // {}) as $s
        | ((($profiles[0] // {})[$s.profile // "balanced"] // {}) + ($s.models // {})) as $m
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
    + sep + "VBW \($plugin.version // "?")" + sep + "CC \($cc.version // "?")" )
