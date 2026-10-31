#!/usr/bin/env bash
# Running approved checks and commands (docs/proof.md), shared by vbw check and
# vbw prove. Nothing runs unless the current contract is approved; every argv
# is executed directly, never through a shell, with stdin closed and a timeout.

# shellcheck source=reads.sh
. "$VBW_LIB/reads.sh"
# shellcheck source=slots.sh
. "$VBW_LIB/slots.sh"
# shellcheck source=proofsteps.sh
. "$VBW_LIB/proofsteps.sh"
# shellcheck source=prooftime.sh
. "$VBW_LIB/prooftime.sh"

# checks_begin RECORD [strict]: die unless the contract is approved
# (checks_approved), then open this invocation's run (checks_open). Called
# directly, never in $(...).
checks_begin() {
  checks_approved "$@"
  checks_open
}

# checks_approved RECORD [strict]: die unless the contract is approved. Check
# files edited since the approval wait for it (CHECK_WAITING): the checks still
# run and the files are named, but with "strict" (proof) it dies. A check a fix
# added waits too, and never runs before the approval (CHECK_HELD, its ids).
# Sets CHECK_HASH. Called directly, never in $(...).
checks_approved() {
  local waiting
  # shellcheck disable=SC2034 # read by the commands that source this file
  CHECK_HASH=$(contract_hash "$1")
  CHECK_WAITING=$(contract_waiting "$1") \
    || vbw_die "the contract is not approved, or changed since it was approved: review it (vbw show contract), then ask the user with the approval menu (AskUserQuestion)"
  if [ -n "$CHECK_WAITING" ]; then
    waiting=$(printf '%s' "$CHECK_WAITING" | tr '\n' ' ')
    [ "${2:-}" != strict ] || vbw_die "check files changed since it was approved, or added by a fix, are waiting for approval, and nothing runs them before: ${waiting% }
Next: review them, then ask the user to approve them once (vbw next asks), and run vbw prove again"
    printf 'vbw: waiting for approval (new or changed since approved): %s\n' "${waiting% }" >&2
  fi
  CHECK_HELD=$(contract_held "$1")
}

# checks_open: this invocation's run, which needs no approval: CHECK_OUT, a
# fresh output directory (parallel Devs each get their own; it also keeps the
# slot waits), and the computer-wide slot store (slots_open). vbw fix done
# opens it before its planning, which holds vbw:plan, and asks for the approval
# only when a check or test file will run. Called directly, never in $(...).
checks_open() {
  CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$CHECK_OUT"
  slots_open
}

# Removes the output directory (also on error or interrupt, through the guard).
checks_end() {
  slots_total
  vbw_guard_drop "$CHECK_OUT"
}

# checks_kept check|command NAME: the file, relative to the project root, that
# keeps the complete output of the check's or project command's latest failure
# in vbw prove (R118). It lives under the git-ignored runtime folder.
checks_kept() {
  case "$1" in
    check) printf '%s/output/%s.log\n' "${VBW_RUNTIME#"$VBW_ROOT"/}" "$2" ;;
    file) printf '%s/output/file-%s.log\n' "${VBW_RUNTIME#"$VBW_ROOT"/}" "$2" ;;
    *) printf '%s/output/command-%s.log\n' "${VBW_RUNTIME#"$VBW_ROOT"/}" "$2" ;;
  esac
}

# checks_keep CHECKS COMMANDS [FILES [pass-leaves]]: the results ({name: result}) of the checks and
# project commands that just ran, their output still in CHECK_OUT. Each failure
# or timeout moves its complete output to its kept file, replacing the older
# one (renamed from a temporary file in the same folder, so a reader never sees
# half a file); a pass removes it, except with "pass-leaves" (vbw check: a
# passing check never removes the proof's or another Dev's failure). Reused results are not in CHECKS or COMMANDS,
# and a check or command that did not run (skipped) leaves its file as it is.
checks_keep() {
  local kind name status out kept dir tmp files=${3:-} leaves=${4:-}
  [ -n "$files" ] || files='{}'
  dir="$VBW_RUNTIME/output"
  while IFS=$'\x1f' read -r -d '' kind name status; do
    case "$kind" in
      check | file) out="$CHECK_OUT/$name.out" ;;
      *) out="$CHECK_OUT/cmd-$name.out" ;;
    esac
    kept="$VBW_ROOT/$(checks_kept "$kind" "$name")"
    case "$status" in
      fail | timeout)
        [ -f "$out" ] || continue
        mkdir -p "$dir" || vbw_die "cannot create $dir"
        tmp=$(mktemp "$dir/keep.XXXXXX") || vbw_die "cannot create a temporary file in $dir"
        mv -f "$out" "$tmp" && mv -f "$tmp" "$kept" || { rm -f "$tmp"; vbw_die "cannot keep the output of $name in $kept"; }
        ;;
      pass) [ "$leaves" = pass-leaves ] || rm -f "$kept" ;;
    esac
  done < <(jq -n -j --slurpfile cs <(printf '%s' "$1") --slurpfile ms <(printf '%s' "$2") --slurpfile fs <(printf '%s' "$files") \
    '$cs[0] as $c | $ms[0] as $m | ($c | to_entries[] | "check\u001f\(.key)\u001f\(.value.status)\u0000"), ($m | to_entries[] | "command\u001f\(.key)\u001f\(.value.status)\u0000"),
      ($fs[0] | to_entries[] | "file\u001f\(.value.id)\u001f\(.value.status)\u0000")')
}

# checks_timer: what stops a unit's command at its timeout (CHECKS_TIMER): timeout
# where timeout --foreground works, else perl. Found once per process, before the
# runners start (checks_run_units), never inside a unit's slot.
CHECKS_TIMER=
checks_timer() {
  [ -z "$CHECKS_TIMER" ] || return 0
  if command -v timeout > /dev/null 2>&1 && timeout --foreground 5 true > /dev/null 2>&1; then CHECKS_TIMER=timeout; else CHECKS_TIMER=perl; fi
}

# checks_exec TIMEOUT OUTFILE ARGV...: run ARGV from the project root, output to
# OUTFILE, stopped at TIMEOUT seconds. Sets CHECK_CODE and CHECK_SECONDS, the
# unit's time in tenths of a second as a decimal ("0.4", "12.0"). The shell's own
# timer reads it (the time keyword with TIMEFORMAT %R: milliseconds, bash 3.2, no
# process of its own); a failed read falls back to whole seconds.
checks_exec() {
  local t="$1" out="$2" TIMEFORMAT=%R tf ms cenv=()
  shift 2
  # The unit's share of the cores (CHECKS_UNIT_SHARE, set by checks_unit_run), told to
  # the build tools that read it, unless the user's environment already sets them.
  if [ -n "${CHECKS_UNIT_SHARE:-}" ]; then
    [ -n "${CARGO_BUILD_JOBS+x}" ] || cenv+=("CARGO_BUILD_JOBS=$CHECKS_UNIT_SHARE")
    [ -n "${GOMAXPROCS+x}" ] || cenv+=("GOMAXPROCS=$CHECKS_UNIT_SHARE")
    [ -n "${MAKEFLAGS+x}" ] || cenv+=("MAKEFLAGS=-j$CHECKS_UNIT_SHARE")
  fi
  checks_timer
  SECONDS=0
  CHECK_CODE=0
  tf="$out.time"
  # A signal ignored by the environment stays ignored in its children (some CI
  # runners start everything with SIGALRM/SIGTERM ignored). So timeout escalates
  # to SIGKILL, which cannot be ignored, and perl resets SIGALRM before the alarm.
  # A unit never sees the session that runs the proof (VBW_SESSION_ID): a project's
  # tests must give one result whoever proves them.
  # --foreground keeps the unit in the run's process group, so Ctrl-C reaches it as
  # it does under perl; without it GNU timeout starts a group of its own and an
  # interrupted run waited for its units to end (T148, Linux).
  if [ "$CHECKS_TIMER" = timeout ]; then
    { time env -u VBW_SESSION_ID ${SLOTS_MARK:+"$SLOTS_MARK"} ${cenv[@]+"${cenv[@]}"} timeout --foreground -k 5 "$t" "$@" > "$out" 2>&1 < /dev/null || CHECK_CODE=$?; } 2> "$tf"
  else
    { time env -u VBW_SESSION_ID ${SLOTS_MARK:+"$SLOTS_MARK"} ${cenv[@]+"${cenv[@]}"} perl -e '$SIG{ALRM} = "DEFAULT"; alarm shift @ARGV; exec { $ARGV[0] } @ARGV or do { print STDERR "cannot run $ARGV[0]: $!\n"; exit 127 }' \
      "$t" "$@" > "$out" 2>&1 < /dev/null || CHECK_CODE=$?; } 2> "$tf"
  fi
  CHECK_SECONDS=$SECONDS
  # The reading is "S.mmm"; anything else (an empty file) keeps the whole seconds.
  ms=$(tail -n 1 "$tf" 2> /dev/null)
  rm -f "$tf"
  case "$ms" in
    [0-9]*.[0-9][0-9][0-9]) ms=$((10#${ms%.*} * 1000 + 10#${ms#*.})); ms=$(((ms + 50) / 100)); CHECK_SECONDS="$((ms / 10)).$((ms % 10))" ;;
  esac
}

# checks_result OUTFILE TIMEOUT EXPECT_EXIT [OUTPUT_REGEX]: the result object.
# A run that lasted its whole timeout and failed was stopped by it. A run that
# left no output file (its wrapper died) reads as empty output.
checks_result() {
  local out="$1"
  [ -f "$out" ] || out=/dev/null
  jq -n --rawfile out "$out" --argjson code "$CHECK_CODE" --argjson secs "$CHECK_SECONDS" \
    --argjson t "$2" --argjson want "$3" --arg re "${4:-}" '
    ($out | split("\n") | map(select(length > 0)) | .[-20:] | join("\n") | .[-2000:]) as $tail
    | if $code != 0 and $secs >= $t then {status: "timeout", exit: null, seconds: $secs, tail: $tail}
      else {status: (if $code == $want and ($re == "" or ($out | test($re))) then "pass" else "fail" end),
            exit: $code, seconds: $secs, tail: $tail} end'
}

# The exclusion gate (R45), under .vbw/runtime/gate: every running check is a
# registration file "reg.PID.ID" holding "alone" or "shared". An alone check
# runs when nothing else is registered; a shared check runs when no alone check
# is registered and none is waiting. A short lock file (gate/mutex) makes the
# look and the registration one step. Registrations of a dead process are taken over
# (kill -0 is only a liveness probe), and every hold is released on exit,
# or interrupt through the guard. A shared check also waits while the live
# registrations already number the limit (the limit checks_run_all reads
# once per run and hands on in CHECKS_LIMIT), so separate processes never pass the limit together. The in-process
# runner starts at most the limit at once; the gate holds the same limit across
# processes. A waiting check never fails for having waited.

# checks_gate_live FILE: the process named in the file's name (NAME.PID...) is alive.
checks_gate_live() {
  local pid="${1##*/}"
  pid="${pid#*.}"
  pid="${pid%%.*}"
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null
}

# checks_gate_blocker KIND: print the check blocking KIND ("alone" or "shared")
# and return 0, or return 1 when nothing blocks. Dead registrations are dropped.
# A shared check is also blocked (printing "-") when the live registrations
# number the limit in $2 (empty: no limit).
checks_gate_blocker() {
  local kind="$1" limit="${2:-}" f id n=0 held
  for f in "$VBW_RUNTIME"/gate/reg.* "$VBW_RUNTIME"/gate/want.*; do
    [ -e "$f" ] || continue
    checks_gate_live "$f" || { rm -f "$f"; continue; }
    id="${f##*.}"
    case "${f##*/}" in
      want.*) [ "$kind" = shared ] || continue ;;
      *)
        n=$((n + 1))
        if [ "$kind" = shared ]; then
          # Read by the shell itself, never a process per registration at every entry.
          held=
          { read -r held < "$f"; } 2> /dev/null || true
          [ "$held" = alone ] || continue
        fi
        ;;
    esac
    printf '%s\n' "$id"
    return 0
  done
  if [ "$kind" = shared ] && [ -n "$limit" ] && [ "$n" -ge "$limit" ]; then
    printf -- '-\n'
    return 0
  fi
  return 1
}

# checks_gate_foreign DIR: another process (another vbw command of this project) holds or wants the gate.
checks_gate_foreign() {
  local f
  for f in "$1"/reg.* "$1"/want.*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in "reg.$$."* | "want.$$."*) ;; *) return 0 ;; esac
  done
  return 1
}

# checks_gate_enter ID ALONE: wait for the gate, then register this check.
checks_gate_enter() {
  local id="$1" kind=shared g="$VBW_RUNTIME/gate" idle=0 want='' owner file limit since='' took=0 lost=''
  [ "$2" != true ] || kind=alone
  limit="${CHECKS_LIMIT:-}"
  [ -n "$limit" ] || limit=$(vbw_check_jobs) || limit=1
  [ -d "$g" ] || mkdir -p "$g" || vbw_die "cannot create $g"
  while :; do
    # The lock is the file mutex holding its owner's pid, made by the exclusive
    # create (no process of its own, and one removal gives it back: T180, its
    # take and release lie between a unit giving its slot back and the next
    # unit taking one). A folder of that name, left by an older VBW with its pid
    # in mutex/pid, excludes just the same, and one taken over is removed whole.
    if [ "$took" = 1 ] || vbw_lock_create "$g/mutex"; then
      took=0
      if [ -d "$g/mutex" ]; then vbw_guard_add dir "$g/mutex"; else vbw_guard_add lock "$g/mutex"; fi
      idle=0 lost=''

      if checks_gate_blocker "$kind" "$limit" > /dev/null; then
        # Only a wait for another VBW command counts; this run's own units queue at the gate silently (R94).
        [ -n "$since" ] || ! checks_gate_foreign "$g" || since=$(date +%s)
        # An alone check that has to wait holds back new shared checks, so it is not starved;
        # the launcher, which waits for that before it starts the next unit, is woken.
        if [ "$kind" = alone ] && [ -z "$want" ]; then
          want="$g/want.$$.$id"
          : > "$want"
          vbw_guard_add file "$want"
          checks_wake
        fi
      else
        [ -z "$want" ] || vbw_guard_drop "$want"
        printf '%s\n' "$kind" > "$g/reg.$$.$id"
        vbw_guard_add file "$g/reg.$$.$id"
        [ "$kind" != alone ] || checks_wake
        vbw_guard_drop "$g/mutex"
        # A wait at the gate is told like a wait for a slot (T149); with the store off it is not told.
        [ "${SLOTS_STATE:-}" != on ] || slots_waited "$since"
        return 0
      fi
      vbw_guard_drop "$g/mutex"
    else
      # A mutex whose owner is gone (or never wrote its pid) is taken over by renaming
      # its owner file (vbw_lock_takeover): of two waiters that find the same dead
      # owner only one wins, and neither removes a lock a third took in between.
      idle=$((idle + 1))
      file=$g/mutex
      [ ! -d "$file" ] || file=$file/pid
      # The owner is read once: empty means a handover in progress, never a dead owner.
      owner=$(vbw_lock_holder "$file")
      if [ -n "$owner" ]; then
        lost=''
        checks_gate_live "x.$owner" || { vbw_lock_takeover "$file" "$owner" && took=1; }
      else
        # No owner for about 5 s: one that died before it wrote its id.
        [ -n "$lost" ] || lost=$(vbw_lock_seconds)
        if [ $(($(vbw_lock_seconds) - lost)) -ge 5 ] && vbw_lock_takeover "$file" ""; then took=1; fi
      fi
    fi
    [ "$took" = 1 ] || slots_nap "$idle"
  done
}

# checks_gate_leave ID: release this check's registration.
checks_gate_leave() {
  vbw_guard_drop "$VBW_RUNTIME/gate/reg.$$.$1"
}

# The runner of units. A unit is one thing to run: a check, a project command
# or a test file. It is a JSON object {name, out, argv, timeout, exit, output,
# alone[, slot]}: name keys its result and its place in the gate, out is the
# file (in CHECK_OUT) that keeps its output, argv is the command, timeout the
# seconds it may take, exit and output (a regex, "" for none) what a pass is,
# alone whether nothing else may run beside it, slot the one copy it runs in.
#
# Without slot copies (PROOF_COPIES empty) a unit runs where the caller is.
# With them (proofcopy_create_slots) each unit takes a free slot copy for its
# run, with that copy's access times reset before it and its read list
# collected after it (reads.sh); the result then carries that list as "reads"
# ({files, dirs, git}, null when it could not be written down). A copy serves
# one unit at a time, so read lists of units running together stay apart.
#
# The runner keeps its places busy (T179): one jq pass reads every unit's
# launch data and one merges the results, never one per unit; a unit's copy
# and place are free as soon as its slot and its gate place are given back,
# and the launcher waits for that on a wake-up, never on a fixed pause.
# Each run of units keeps its files (results, read lists, markers, the wake
# FIFO) in a folder of its own under CHECK_OUT (CU_DIR): a later run in the
# same output folder never reads an earlier run's.

# checks_gate_forget NAME: drop the gate places this process holds for a unit
# whose runner is gone (killed, so it could not release them itself).
checks_gate_forget() {
  rm -f "$VBW_RUNTIME/gate/reg.$$.$1" "$VBW_RUNTIME/gate/want.$$.$1"
  slots_give "$1"
}

# checks_lost NAME: the result of a unit whose runner ended without leaving one.
checks_lost() {
  jq -n --arg id "$1" '{status: "skipped", exit: null, seconds: 0,
    tail: "not run: the runner of \($id) ended without a result (it was killed or crashed)"}'
}

# checks_unit RECORD ID: the unit of a check.
checks_unit() {
  printf '%s' "$1" | jq -c --arg id "$2" '.checks[] | select(.id == $id)
    | {name: .id, out: "\(.id).out", argv: .run, timeout: (.timeout // 300), exit: (.exit // 0),
       output: (.output // ""), alone: (.alone // false)}'
}

# checks_units_load UNITS: every unit's launch data, from one jq pass over the
# units (a JSON array): CU_COUNT units; for unit I, CU_NAME, CU_OUT, CU_TIMEOUT,
# CU_EXIT, CU_OUTPUT, CU_ALONE, CU_PIN (the copy it names, or empty) and its
# argv, CU_ARGC[I] words of CU_ARGV from CU_AT[I]. checks_run_units declares them.
checks_units_load() {
  local f=() a k=0 c
  while IFS= read -r -d '' a; do f+=("$a"); done < <(printf '%s' "$1" | jq -j '.[]
    | [.name, .out, (.timeout | tostring), (.exit | tostring), .output, (.alone | tostring), (.slot // "" | tostring),
       (.argv | length | tostring)] + .argv | .[] + "\u0000"')
  CU_COUNT=0
  while [ "$k" -lt ${#f[@]} ]; do
    CU_NAME[CU_COUNT]=${f[k]}
    CU_OUT[CU_COUNT]=${f[k + 1]}
    CU_TIMEOUT[CU_COUNT]=${f[k + 2]}
    CU_EXIT[CU_COUNT]=${f[k + 3]}
    CU_OUTPUT[CU_COUNT]=${f[k + 4]}
    CU_ALONE[CU_COUNT]=${f[k + 5]}
    CU_PIN[CU_COUNT]=${f[k + 6]}
    c=${f[k + 7]}
    CU_AT[CU_COUNT]=${#CU_ARGV[@]}
    CU_ARGC[CU_COUNT]=$c
    [ "$c" -eq 0 ] || CU_ARGV+=("${f[@]:k + 8:c}")
    k=$((k + 8 + c))
    CU_COUNT=$((CU_COUNT + 1))
  done
}

# checks_unit_run I [SLOT]: run unit I (checks_units_load), in slot copy number
# SLOT when given; print its result object. In a runner (CU_RUNNER) the unit's
# copy and place are free once its slot and its gate place are given back
# (checks_unit_free): the next unit starts while this one writes its result.
checks_unit_run() {
  local i=$1 name out t want re alone copy here=$PWD st="" reads=true res t0 collected=false list a c
  name=${CU_NAME[i]} out=$CHECK_OUT/${CU_OUT[i]} t=${CU_TIMEOUT[i]} want=${CU_EXIT[i]} re=${CU_OUTPUT[i]} alone=${CU_ALONE[i]}
  a=${CU_AT[i]} c=${CU_ARGC[i]} list=$CU_DIR/$i.reads
  if [ -n "${2:-}" ]; then
    copy=${PROOF_COPIES[$2]}
    st="${copy%/*}/reads"
    cd "$copy" || return 1
  fi
  checks_gate_enter "$name" "$alone"
  # Its share of the cores (T172): every core alone, else the run's share.
  local CHECKS_UNIT_SHARE=${CHECKS_SHARE:-}
  [ "$alone" != true ] || CHECKS_UNIT_SHARE=${CHECKS_CORES:-}
  # The slot is taken after the gate and before the reset and the command, and kept
  # until the read list is collected: the tracking is the unit's own work, inside
  # its slot. The timeout counts from the command's start, never from the wait.
  slots_take "$name"
  if [ -n "$st" ]; then
    t0=
    [ -z "${PROOFTIME_FILE:-}" ] || t0=$(prooftime_clock)
    reads_reset "$copy" "$st" || reads=false
    [ -z "$t0" ] || prooftime_span tracking "$t0"
  fi
  checks_exec "$t" "$out" ${CU_ARGV[@]+"${CU_ARGV[@]:a:c}"}
  if [ -n "$st" ]; then
    t0=
    [ -z "${PROOFTIME_FILE:-}" ] || t0=$(prooftime_clock)
    if [ "$reads" = true ] && reads_collect "$copy" "$st" "${CU_ARGV[a]:-}" > "$list"; then collected=true; fi
    [ -z "$t0" ] || prooftime_span tracking "$t0"
    # Nothing after this looks into the copy, which the next unit may take at once.
    cd "$here" || return 1
  fi
  slots_give "$name"
  checks_gate_leave "$name"
  checks_unit_free "$i"
  res=$(checks_result "$out" "$t" "$want" "$re")
  # A proof counts the unit as it finishes (vbw check never does).
  proofsteps_unit_done
  if [ -z "$st" ]; then
    printf '%s\n' "$res"
  elif [ "$collected" = true ]; then
    printf '%s' "$res" | jq -c --slurpfile r "$list" '. + {reads: $r[0]}'
  else
    printf '%s' "$res" | jq -c '. + {reads: null}'
  fi
}

# checks_unit_free I: in a runner, unit I needs its copy and its place no more:
# its marker in CU_DIR, then the launcher is woken. Nothing outside a runner.
checks_unit_free() {
  [ -n "${CU_RUNNER:-}" ] || return 0
  { : > "$CU_DIR/$1.free"; } 2> /dev/null || true
  checks_wake
}

# checks_wake: wake the launcher of this run of units through its wake FIFO
# (CU_WAKE), opened for reading and writing, which never blocks: the launcher
# holds it open while it runs, and when it is gone what is written is dropped.
checks_wake() {
  [ -n "${CU_WAKE:-}" ] || return 0
  { printf '\n' 1<> "$CU_DIR/wake"; } 2> /dev/null || true
}

# checks_wake_wait: in the launcher, wait until a runner wakes it, at most a
# second (a runner killed outright wakes no one), or 0.05 s where no FIFO could
# be made. The FIFO is file descriptor 8 while checks_units_parallel runs.
checks_wake_wait() {
  if [ -n "$CU_WAKE" ]; then read -r -t 1 -u 8 _ || true; else sleep 0.05; fi
}

# checks_units_parallel CAP SLOTS: run the units, at most CAP at a time, each in
# a runner (a subshell owning no guard of the parent) that leaves its result in
# CU_DIR; with SLOTS copies each takes a free one (only its own when it names
# one). bash 3.2 cannot wait for any one job: a runner leaves a marker once its
# copy and place are free and wakes the launcher, which starts the next unit then.
checks_units_parallel() {
  local cap=$1 slots=$2 i k r pin slot pid pids=() active=() keep copy_run=() run_copy=()
  for ((i = 0; i < CU_COUNT; i++)); do
    pin=${CU_PIN[i]}
    while :; do
      # The runners whose copy and place are free. One that died before it gave its
      # slot and gate place back (killed outright) has them given back here.
      keep=()
      for r in ${active[@]+"${active[@]}"}; do
        if [ ! -e "$CU_DIR/$r.free" ]; then
          if kill -0 "${pids[r]}" 2> /dev/null; then
            keep+=("$r")
            continue
          fi
          [ -s "$CU_DIR/$r.res" ] || checks_gate_forget "${CU_NAME[r]}"
        fi
        [ -z "${run_copy[r]:-}" ] || copy_run[${run_copy[r]}]=
      done
      active=(${keep[@]+"${keep[@]}"})
      slot=""
      if [ ${#active[@]} -lt "$cap" ]; then
        [ "$slots" -gt 0 ] || break
        for ((k = 0; k < slots; k++)); do
          [ -z "$pin" ] || [ "$k" -eq "$pin" ] || continue
          if [ -z "${copy_run[k]:-}" ]; then
            slot=$k
            break
          fi
        done
        [ -z "$slot" ] || break
      fi
      checks_wake_wait
    done
    (
      # The runner holds no end of the wake FIFO (checks_wake opens it), so the unit's
      # command never inherits it. The unit's own diagnostics go to its log, never to
      # the proof's output: a runner that outlives its slot (killed, its children still
      # running) prints nowhere.
      [ -z "$CU_WAKE" ] || exec 8>&-
      exec 2> "$CU_DIR/$i.err"
      vbw_guard_reset
      # shellcheck disable=SC2034 # read by slots.sh
      SLOTS_SUB=1
      CU_RUNNER=1
      res=$(checks_unit_run "$i" "$slot") || res=
      if [ -z "$res" ]; then
        # The unit's run ended without a result (killed or crashed): its places are given back now.
        checks_gate_forget "${CU_NAME[i]}"
        checks_unit_free "$i"
        res=$(checks_lost "${CU_NAME[i]}")
      fi
      printf '%s\n' "$res" > "$CU_DIR/$i.tmp" && mv -f "$CU_DIR/$i.tmp" "$CU_DIR/$i.res"
    ) &
    pids[i]=$!
    active+=("$i")
    if [ -n "$slot" ]; then
      copy_run[slot]=$i
      run_copy[i]=$slot
    fi
    # An alone unit is at the gate before the next one starts, so a shared
    # unit launched after it never runs first (it wakes the launcher there).
    if [ "${CU_ALONE[i]}" = true ]; then
      while kill -0 "${pids[i]}" 2> /dev/null && [ ! -e "$VBW_RUNTIME/gate/reg.$$.${CU_NAME[i]}" ] \
        && [ ! -e "$VBW_RUNTIME/gate/want.$$.${CU_NAME[i]}" ]; do
        checks_wake_wait
      done
    fi
  done
  # Job notices (Killed, not a child) are the shell's own: silenced here.
  for pid in "${pids[@]}"; do { wait "$pid" || true; } 2> /dev/null; done
  # A runner killed outright left no result: the unit is skipped, its places given back.
  for ((i = 0; i < CU_COUNT; i++)); do
    [ -s "$CU_DIR/$i.res" ] || { checks_lost "${CU_NAME[i]}" > "$CU_DIR/$i.res"; checks_gate_forget "${CU_NAME[i]}"; }
  done
}

# checks_run_units UNITS: {name: result} for the units (a JSON array), at most
# check_jobs at a time and never more than there are slot copies; a unit that
# is alone still runs by itself (the gate). A unit that names its slot copy
# (.slot, an index into PROOF_COPIES) runs only in it, when that copy is free
# (vbw mutate --run: each break is in its own copy). Results are in the units' order.
checks_run_units() {
  local jobs slots cap i slot res CU_DIR CU_WAKE='' CU_RUNNER='' CU_COUNT=0
  local CU_NAME=() CU_OUT=() CU_TIMEOUT=() CU_EXIT=() CU_OUTPUT=() CU_ALONE=() CU_PIN=() CU_AT=() CU_ARGC=() CU_ARGV=()
  checks_units_load "$1"
  [ "$CU_COUNT" -gt 0 ] || { printf '{}\n'; return 0; }
  jobs=$(vbw_check_jobs) || jobs=1
  # A unit only ever waits for other runs: never more runners than the machine limit.
  [ "$SLOTS_STATE" != on ] || [ "$jobs" -le "$SLOTS_LIMIT" ] || jobs=$SLOTS_LIMIT
  [ "$SLOTS_STATE" != on ] || slots_traps
  CHECKS_LIMIT=$jobs
  checks_timer
  slots=0
  [ -z "${PROOF_COPIES+x}" ] || slots=${#PROOF_COPIES[@]}
  cap=$jobs
  [ "$slots" -eq 0 ] || [ "$slots" -ge "$cap" ] || cap=$slots
  # Each unit's share of the cores: the cores over the units side by side, at least 1
  # (T172); an unreadable core count tells the tools nothing.
  local CHECKS_CORES='' CHECKS_SHARE=''
  if CHECKS_CORES=$(vbw_cores); then
    CHECKS_SHARE=$((CHECKS_CORES / cap))
    [ "$CHECKS_SHARE" -ge 1 ] || CHECKS_SHARE=1
  else
    CHECKS_CORES=''
  fi
  CU_DIR=$(mktemp -d "$CHECK_OUT/units.XXXXXX") || vbw_die "cannot create a directory in $CHECK_OUT"
  if [ "$cap" -le 1 ] || [ "$CU_COUNT" -le 1 ]; then
    slot=""
    [ "$slots" -eq 0 ] || slot=0
    for ((i = 0; i < CU_COUNT; i++)); do
      res=$(checks_unit_run "$i" "${CU_PIN[i]:-$slot}") || res=
      [ -n "$res" ] || { res=$(checks_lost "${CU_NAME[i]}"); checks_gate_forget "${CU_NAME[i]}"; }
      printf '%s\n' "$res" > "$CU_DIR/$i.res"
    done
  elif mkfifo "$CU_DIR/wake" 2> /dev/null && { : 8<> "$CU_DIR/wake"; } 2> /dev/null; then
    # The wake FIFO is file descriptor 8 while the units run; the caller's own 8 comes back after.
    CU_WAKE=1
    checks_units_parallel "$cap" "$slots" 8<> "$CU_DIR/wake"
  else
    checks_units_parallel "$cap" "$slots"
  fi
  # One jq pass over every result, in the units' order.
  for ((i = 0; i < CU_COUNT; i++)); do printf '%s\0' "$CU_DIR/$i.res"; done | xargs -0 cat \
    | jq -sc --rawfile n <(printf '%s\0' "${CU_NAME[@]}") '($n | split("\u0000")) as $n | . as $r
      | reduce range(0; $r | length) as $k ({}; . + {($n[$k]): $r[$k]})'
  rm -rf "$CU_DIR"
}

# checks_run_all RECORD [ID...]: {C1: result, ...} for the given checks (all
# when none are given); dies on an unknown id before running anything. The
# units of all of them come from one jq pass over the record.
checks_run_all() {
  local record="$1" plan unknown res all=false
  shift
  [ $# -gt 0 ] || all=true
  # A check a fix added waits for the user's approval: it is reported, never run.
  plan=$(printf '%s' "$record" | jq -c --argjson all "$all" --rawfile given <(printf '%s\0' "$@") --rawfile held <(printf '%s\n' "${CHECK_HELD:-}") '
    .checks as $c
    | (if $all then [$c[].id] else $given | split("\u0000")[:-1] end) as $ids
    | ($held | split("\n") | map(select(length > 0))) as $h
    | {unknown: ([$ids[] | select(. as $i | any($c[]; .id == $i) | not)] | first),
       ids: $ids,
       units: [$ids[] as $i | select(any($h[]; . == $i) | not) | $c[] | select(.id == $i)
         | {name: .id, out: "\(.id).out", argv: .run, timeout: (.timeout // 300), exit: (.exit // 0),
            output: (.output // ""), alone: (.alone // false)}],
       waiting: ([$ids[] | select(. as $i | any($h[]; . == $i))
         | {key: ., value: {status: "waiting", exit: null, seconds: 0, tail: "not run: a check a fix added waits for the user'"'"'s approval"}}]
         | from_entries)}')
  unknown=$(printf '%s' "$plan" | jq -r '.unknown // empty')
  [ -z "$unknown" ] || vbw_die "unknown check $unknown"
  res=$(checks_run_units "$(printf '%s' "$plan" | jq -c '.units')")
  # The checks' own order, the waiting ones among them.
  printf '%s' "$res" | jq -c --slurpfile p <(printf '%s' "$plan") '. + $p[0].waiting | . as $m | reduce $p[0].ids[] as $i ({}; . + {($i): $m[$i]})'
}

# checks_must_pass RECORD WHAT CHECK...: run the checks now and die with
# "WHAT: <the failing checks>" unless every one passes. No checks: nothing runs.
checks_must_pass() {
  local record="$1" what="$2" results
  shift 2
  [ $# -gt 0 ] || return 0
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  checks_begin "$record"
  results=$(checks_run_all "$record" "$@")
  checks_end
  printf '%s' "$results" | jq -e 'all(.[]; .status == "pass")' > /dev/null \
    || vbw_die "$what: $(printf '%s' "$results" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')"
}
