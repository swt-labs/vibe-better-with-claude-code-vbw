# The expectation ladders (R191, docs/panel.md): one jq program turns the step
# history, the units' last run times and a step's units into its expected seconds.
#
# Interface: jq -n --slurpfile h HISTORY --slurpfile runs RUN_TIMES --arg kind K
#   --slurpfile size SIZE -f steps-expect.jq (a file: a proof's size names every unit)
#   $h[0]    the history {steps: [...]} or null (a missing or damaged file)
#   $runs[0] the run times {runs: {name: {seconds}}} or null: run-times.json, which
#            the save writes beside the run store (never the store itself)
#   $kind    build | fix | plan | qa | proof
#   $size[0] build: [{id, tier, tasks, breaks}] (the wave's plans); fix: {tier};
#            plan: {reqs}; qa: [{id, tier}]; proof: {units: [name]}
# Output: one object {seconds, typical, low, high, runs, rough} (R270, R291): typical the
# median of the kept runs times the step's size (R291), seconds the figure of
# today (a median, a quantile or a ratio), low and high the lowest and the highest
# kept run per unit times the step's size, runs the count of kept runs, rough whether
# the estimate is a rough guess (def rough: the one place of both thresholds). One run
# is enough for a figure; no run keeps seconds, low and high null with runs 0.
# Every list is the latest 10 by the history's order; an even count takes the
# mean of the two middle values. A step
# that took more than 8 times the median seconds per part of its kind (idle time:
# a run left open overnight) is left out first, while 3 steps remain (T173).
#
# A build wave waits for its slowest plan (T174): each plan is timed at the
# quantile 0.75^(1/n) of its unit's seconds (n: the wave's plans), the time 3
# waves in 4 stay within when plans vary on their own: the upper quartile for a
# lone plan, 0.87 for two, 0.91 for three. A plan's unit of work is a task or a
# break (a rule it owes the mutation check), so its work is its tasks plus its
# breaks; the history from before breaks were recorded counts per task.
#
# A proof takes its units' costs times the learned ratio. The latest 10 proofs
# that recorded units give the ratio, their total wall time over their total
# unit time (one proof of two units cannot skew it), and each unit's fastest
# seconds among them; its last run (the run times) joins that minimum, so a busy day's
# slow run never sets the promise (a proof that runs late moves its end, D424).
# A unit never run counts as the median of the known costs.

def median: sort | length as $n
  | if $n == 0 then empty
    elif $n % 2 == 1 then .[($n - 1) / 2 | floor]
    else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
# quantile($q): linear between the two nearest sorted values (0.5 is the median).
def quantile($q): sort | length as $n
  | if $n == 0 then empty
    else (($n - 1) * $q) as $p | ($p | floor) as $lo | ([$lo + 1, $n - 1] | min) as $hi
      | .[$lo] + (.[$hi] - .[$lo]) * ($p - $lo) end;
def latest: .[-10:];
# The estimate is a rough guess (R270): too few kept runs, or a high far above the
# low. These are the only two thresholds; docs/panel.md documents them.
def rough: .runs < 5 or .high > 1.5 * .low;
# est(point; $m): the kept per-unit values (the input list) as an estimate of a step $m
# units big: the figure of the ladder (point) and the lowest and highest run, all times $m.
def est(point; $m): . as $v | if length == 0 then empty
  else {seconds: (($v | point) * $m), typical: (($v | median) * $m), low: (($v | min) * $m), high: (($v | max) * $m), runs: ($v | length)} end;
# Two estimates of parts of one step that run one after the other add up; their runs are the fewer.
def plus($o): {seconds: (.seconds + $o.seconds), typical: (.typical + $o.typical), low: (.low + $o.low), high: (.high + $o.high), runs: ([.runs, $o.runs] | min)};
def num: type == "number" and . >= 0;
def basis: est(median; 1);
# A step's size for the idle test (T173): its parts, else its requirements or phases, else 1.
def span: if (.parts | type) == "number" and .parts > 0 then .parts
  elif (.reqs | type) == "number" and .reqs > 0 then .reqs
  elif (.phases | type) == "array" and (.phases | length) > 0 then (.phases | length)
  else 1 end;
# Idle time is not work (T173): the history keeps only when a step started and ended, so a
# run left open overnight or waiting is recorded at its whole length. A step that took more
# than 8 times the median seconds per unit of size of its kind is left out, when at least
# 3 steps remain; the median itself needs no such care.
def awake: if length < 3 then .
  else (map(.seconds / span) | median) as $m
    | if $m > 0 then (map(select(.seconds / span <= 8 * $m)) as $k | if ($k | length) >= 3 then $k else . end) else . end end;

$size[0] as $size
| ($h[0] | if type == "object" and (.steps | type) == "array" then [.steps[] | select(type == "object")] else [] end) as $steps
| (if $kind == "build" and ($size | type) == "array" and ($size | length) > 0 then pow(0.75; 1 / ($size | length)) else 0.75 end) as $q
| def of($k): [$steps[] | select(.kind == $k and (.seconds | num))] | awake;
  def withparts: map(select((.parts | type) == "number" and .parts > 0));

  # A plan unit: one finished plan of a build, with its tier, tasks, breaks and seconds.
  # A list VBW never wrote (units or phases that are not arrays, an entry that is not an
  # object) is skipped, never an error: every shape the history has had stays readable.
  def items: if type == "array" then .[] | select(type == "object") else empty end;
  def plan_units: [of("build")[] | .units | items | select(.seconds | num)];
  def counted($f): ($f | type) == "number" and $f >= 0;
  # Per unit of size: the wave's quantile of seconds / size over the latest 10 that recorded it, times this size.
  def per($us; size; $n): $us | latest | map(.seconds / size) | est(quantile($q); $n);
  def build_plan($p; $units):
    ($p.tier // "standard") as $t
    | ($p.tasks // 0) as $tk
    | (if counted($p.breaks) then $p.breaks else 0 end) as $bk
    | [$units[] | select(.tier == $t)] as $tu
    | ( ( if $tk + $bk > 0 then
            per([$tu[] | select(counted(.tasks) and counted(.breaks) and .tasks + .breaks > 0)]; .tasks + .breaks; $tk + $bk)
          else empty end )
        // ( if $tk > 0 then per([$tu[] | select(counted(.tasks) and .tasks > 0)]; .tasks; $tk) else empty end )
        // per($tu; 1; 1)
        // per($units; 1; 1) );
  def build:
    plan_units as $u
    | if ($u | length) >= 1 then
        [ $size[] | build_plan(.; $u) ] as $each
        | if ($each | length) == ($size | length) and ($each | length) > 0
          then {seconds: ($each | map(.seconds) | max), typical: ($each | map(.typical) | max), low: ($each | map(.low) | max), high: ($each | map(.high) | max), runs: ($each | map(.runs) | min)}
          else empty end
      else
        (of("build") | withparts | latest) as $b
        | if ($size | length) > 0 then $b | map(.seconds / .parts) | est(median; $size | length) else empty end
      end;

  def fix:
    ( ( if ($size.tier | type) == "string" then of("fix") | map(select(.tier == $size.tier)) | latest | map(.seconds) | basis else empty end )
      // (of("fix") | latest | map(.seconds) | basis) );

  def planning:
    ( ( if ($size.reqs | type) == "number" and $size.reqs > 0 then
          of("plan") | map(select((.reqs | type) == "number" and .reqs > 0)) | latest
          | map(.seconds / .reqs) | est(median; $size.reqs)
        else empty end )
      // (of("plan") | latest | map(.seconds) | basis) );

  def qa:
    [ of("qa")[] | select((.phases | type) == "array" and (.phases | length) > 0)
      | .seconds as $s | .phases as $ph | $ph | items | {tier: .tier, seconds: ($s / ($ph | length))} ] as $samples
    | if ($samples | length) >= 1 and ($size | length) > 0 then
        [ $size[] | .tier as $t
          | ( ( if ($t | type) == "string" then [$samples[] | select(.tier == $t)] | latest | map(.seconds) | basis else empty end )
              // ($samples | latest | map(.seconds) | basis) ) ] as $each
        | if ($each | length) == ($size | length) then $each | reduce .[1:][] as $e (.[0]; plus($e)) else empty end
      else of("qa") | latest | map(.seconds) | basis end;

  def proof:
    ( [ of("proof")[] | select((.units | type) == "array" and (.units | length) > 0)
        | {seconds, units: [.units[] | select(type == "object" and (.name | type) == "string" and (.seconds | num))]}
        | select(([.units[].seconds] | add // 0) > 0) ] | latest ) as $hist
    | ( if ($hist | length) >= 1 then
          ($runs[0] | if type == "object" and (.runs | type) == "object" then .runs else {} end) as $store
          | (($hist | map(.seconds) | add) / ($hist | map([.units[].seconds] | add) | add)) as $ratio
          | (reduce ($hist[].units[]) as $u ({}; .[$u.name] = ([.[$u.name], $u.seconds] | map(select(. != null)) | min))) as $fast
          | def cost: . as $n | [$fast[$n], ($store[$n] | if type == "object" and (.seconds | num) then .seconds else null end)]
              | map(select(. != null)) | if length > 0 then min else null end;
          ($hist | map(.seconds / ([.units[].seconds] | add))) as $each
          | [ $size.units[]? | cost | select(. != null) ] as $known
          | if ($known | length) == 0 then empty
            else ($known | median) as $m
              | ([ $size.units[]? | cost // $m ] | add) as $base
              | {seconds: ($base * $ratio), typical: ($base * ($each | median)), low: ($base * ($each | min)), high: ($base * ($each | max)), runs: ($hist | length)}
            end
        else empty end )
      // ( of("proof") | withparts | latest
           | if ($size.units | length) > 0
             then map(.seconds / .parts) | est(median; $size.units | length) else empty end );

  ( [ if $kind == "build" then build
    elif $kind == "fix" then fix
    elif $kind == "plan" then planning
    elif $kind == "qa" then qa
    elif $kind == "proof" then proof
    else empty end ] | first )
  | if . == null then {seconds: null, typical: null, low: null, high: null, runs: 0, rough: false}
    else (.rough = rough | .seconds |= round | .typical |= round | .low |= round | .high |= round) end
