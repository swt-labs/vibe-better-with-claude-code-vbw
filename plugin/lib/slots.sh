#!/usr/bin/env bash
# The computer-wide slot store (R181, docs/proof.md). Every unit of vbw prove,
# vbw fix done and vbw check (a check, a project command, a test file) takes one
# slot for as long as its command runs, so all VBW runs on a computer, in every
# project and session, never run more units than vbw_machine_limit together.
#
# The store is <vbw_claude_dir>/vbw/slots.json, one JSON document
# {held: [{run, id}], waiting: [{run, id, order}], next}: "run" is the vbw
# process ($$), "id" the unit, "order" its place in the wait. Every change is
# one step under the short lock file slots.lock (its owner's pid in it, taken
# over by a rename when that process is gone, and when it is empty only after a
# wait): one jq run over the file (a second one only when a run in it is gone),
# then the new store written atomically (a temporary file in the same folder,
# then mv). A step spawns three processes (jq, mv, and the lock's removal) and
# sleeps only while the lock is held (T180: slots sat idle between units while
# steps ran). The file is removed when nothing holds or waits for a slot.
#
# Turns (D339): every step drops the entries of runs whose process is gone,
# makes its change, then hands each free slot to the waiter whose turn it is:
# the waiting run holding the fewest slots, between equals the one that has
# waited longest. A slot is so given in the step that frees it, and a unit that
# waits takes the lock once, to join the wait; after that it only reads the
# store (every write is a rename, so a read sees a whole store) until it finds
# the slot its own. A look that finds a free slot, a run gone, its own entry
# missing, or a store it cannot read or write, or a damaged one, takes one step
# instead. (T175: waiters that each took the lock to look kept it held most of
# the time, so releases queued behind them and freed slots sat idle.)
#
# A unit's command gets VBW_SLOT_STORE, the store it holds a slot in: a vbw run
# started inside it on the same store takes no slot (the unit's covers it, D340).
# When the store cannot be used the run goes on under check_jobs alone.
#
# A store lost in the middle of a run (SLOTS_STATE lost) leaves the entry of the
# unit that lost it behind: it is named in the run's folder (left/ID in
# CHECK_OUT; SLOTS_LEFT once the folder has ended), and the next step of any
# process of the run drops it, as soon as the store can be written again, so no
# other run's step hands it a slot nobody uses. A process that lost the store
# takes no slot, but it takes that step wherever it would have used the store.

SLOTS_STATE=off
SLOTS_LOCKED=
SLOTS_MARK=
SLOTS_UNIT=
SLOTS_SUB=
SLOTS_RESULT=
SLOTS_WAITED=0
SLOTS_LOST=
SLOTS_LEFT=

# The store's jq programs (slots_jq), each over the file's values in an array.
# valid: the one store, or an error when it is damaged; runs: the runs in it;
# me: the entry of unit $id of this run $run (mine: also every entry of the run
# when $id is empty); left: an entry of this run's units that lost the store
# ($left, their ids one per line); kept: an entry neither of a run gone nor
# left; fill: free slots handed out in turn, up to $limit. A step drops the runs found gone ($dead) and the entries left, makes
# its change, fills, and prints three lines: the runs it read, whether the unit
# holds a slot, the new store (null: none left). A look prints the runs, then
# held, waiting (its turn has not come) or step (it needs a step of its own).
SLOTS_JQ='def valid: if length == 1 and (.[0] | type == "object" and (.held | type) == "array" and (.waiting | type) == "array"
      and (.next | type) == "number" and all(.held[], .waiting[]; (.run | type) == "number"))
    then .[0] else error("damaged") end;
  def runs: [.held[], .waiting[] | .run] | unique | map(tostring) | join(" ");
  def me: .run == $run and .id == $id;
  def mine: .run == $run and ($id == "" or .id == $id);
  def left: .run == $run and (.id as $i | any($left | split("\n")[]; . == $i));
  def kept: select(.run as $r | ($dead | index($r)) == null and (left | not));
  def fill: until((.held | length) >= $limit or (.waiting | length) == 0;
    . as $s | ($s.waiting | min_by([(.run as $r | [$s.held[] | select(.run == $r)] | length), .order])) as $p
    | .waiting -= [$p] | .held += [{run: $p.run, id: $p.id}]);
  def step(change): valid | runs, (.held |= map(kept) | .waiting |= map(kept) | change | fill
    | "\(any(.held[]; me))", (if (.held | length) + (.waiting | length) == 0 then null else tojson end));'
SLOTS_TAKE='step(if any(.held[], .waiting[]; me) then . else .waiting += [{run: $run, id: $id, order: .next}] | .next += 1 end)'
SLOTS_DROP='step(.held |= map(select(mine | not)) | .waiting |= map(select(mine | not)))'
SLOTS_TIDY='step(.)'
SLOTS_LOOK='valid | runs, (if any(.held[]; me) then "held" elif any(.waiting[]; me) and (.held | length) >= $limit then "waiting" else "step" end)'

# slots_live PID: the process is alive (kill -0 is only a liveness probe).
slots_live() {
  [ -n "$1" ] && kill -0 "$1" 2> /dev/null
}

# slots_nap N: the pause before retry number N (from 1) of a lock:
# 10 ms at first, longer the longer it takes, never over a tenth of a second.
slots_nap() {
  if [ "$1" -le 3 ]; then
    sleep 0.01
  elif [ "$1" -le 10 ]; then
    sleep 0.02
  elif [ "$1" -le 30 ]; then
    sleep 0.05
  else
    sleep 0.1
  fi
}

# slots_lock: take the store's lock; 2 when the folder cannot be written. The
# lock is the file slots.lock holding its owner's pid, made by the exclusive
# create of vbw_lock_create (no process of its own). A folder of that name, left
# by an older VBW with its pid in slots.lock/pid, excludes just the same.
slots_lock() {
  local lock="$SLOTS_DIR/slots.lock" n=0 quiet owner file probe
  quiet=$(vbw_lock_seconds)
  while :; do
    if vbw_lock_create "$lock"; then
      SLOTS_LOCKED=$lock
      return 0
    fi
    if [ ! -e "$lock" ]; then
      # Nobody holds it: the create lost a race with a lock that has since gone,
      # or the folder cannot make a file (a full disk, a sandbox) though it
      # reports writable. A file under a name nobody else uses tells which.
      probe="$SLOTS_DIR/slots.probe.$$.$RANDOM"
      vbw_lock_create "$probe" || return 2
      rm -f "$probe"
    else
      file=$lock
      [ ! -d "$lock" ] || file=$lock/pid
      # The owner is read once: empty means a handover in progress, never a dead owner.
      owner=$(vbw_lock_holder "$file")
      if [ -n "$owner" ] && slots_live "$owner"; then
        # A live owner is not an error: the wait for it has no end.
        quiet=$(vbw_lock_seconds)
      elif [ -n "$owner" ] || [ $(($(vbw_lock_seconds) - quiet)) -ge 5 ]; then
        # An owner that is gone, or none for 5 s: take the lock over (a rename,
        # never a removal). Only a lock that cannot be taken over for 30 s gives up.
        if vbw_lock_takeover "$file" "$owner"; then
          SLOTS_LOCKED=$lock
          return 0
        fi
        [ $(($(vbw_lock_seconds) - quiet)) -lt 30 ] || return 2
      fi
    fi
    n=$((n + 1))
    slots_nap "$n"
  done
}

slots_unlock() {
  [ -z "$SLOTS_LOCKED" ] || rm -rf "$SLOTS_LOCKED" 2> /dev/null
  SLOTS_LOCKED=
}

# slots_jq PROGRAM ID [DEAD [LEFT]]: the lines of PROGRAM (after SLOTS_JQ) over
# the store (a new one when there is none), for the unit ID of this run, with
# DEAD the runs found gone (a JSON array) and LEFT the ids of the entries left
# by this run's units that lost the store (one per line); 2 when the store
# cannot be read, 3 when it is damaged (not JSON, not one value, or not the
# store's shape).
slots_jq() {
  if [ ! -e "$SLOTS_FILE" ]; then
    jq -nr --argjson run "$$" --arg id "$2" --argjson dead "${3:-[]}" --arg left "${4:-}" --argjson limit "$SLOTS_LIMIT" \
      "$SLOTS_JQ [{held: [], waiting: [], next: 1}] | $1"
  elif [ -r "$SLOTS_FILE" ]; then
    jq -sr --argjson run "$$" --arg id "$2" --argjson dead "${3:-[]}" --arg left "${4:-}" --argjson limit "$SLOTS_LIMIT" \
      "$SLOTS_JQ $1" "$SLOTS_FILE" 2> /dev/null || return 3
  else
    return 2
  fi
}

# slots_write STORE: the new store (a step's last line), atomically; none left
# when it is null (nothing holds or waits).
slots_write() {
  local tmp="$SLOTS_DIR/slots.json.$$"
  if [ "$1" = null ]; then
    [ ! -e "$SLOTS_FILE" ] || rm -f "$SLOTS_FILE" 2> /dev/null || return 2
    return 0
  fi
  # The lock is held, so this run's one temporary file is the only one.
  { printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$SLOTS_FILE"; } 2> /dev/null || { rm -f "$tmp"; return 2; }
}

# slots_left_found: an entry left by a unit of this run that lost the store is
# still to be dropped (slots_lose). Read by the shell alone, never a process.
slots_left_found() {
  local f
  [ -z "$SLOTS_LEFT" ] || return 0
  [ -n "${CHECK_OUT:-}" ] || return 1
  for f in "$CHECK_OUT"/left/*; do [ ! -e "$f" ] || return 0; done
  return 1
}

# slots_apply SLOTS_TAKE|SLOTS_DROP|SLOTS_TIDY ID: one locked step of this run
# for the unit ID (dropping with ID empty: every entry of the run). It also
# drops the entries this run's units left when they lost the store, and once
# the new store is written they are no longer named. SLOTS_RESULT is true when
# the unit holds a slot after it.
slots_apply() {
  local out rest p dead='' rc=0 f left=$SLOTS_LEFT named=()
  slots_lock || return 2
  # Named under the lock: a unit of the same name later in the run joins the
  # wait only in a step after this one, and so is never dropped by it.
  if [ -n "${CHECK_OUT:-}" ]; then
    for f in "$CHECK_OUT"/left/*; do
      [ -e "$f" ] || continue
      named+=("$f")
      left="$left${f##*/}"$'\n'
    done
  fi
  out=$(slots_jq "$1" "$2" "" "$left") || rc=$?
  if [ "$rc" -eq 0 ]; then
    for p in ${out%%$'\n'*}; do slots_live "$p" || dead="$dead,$p"; done
    # A run in the store is gone: the same step again, without its entries.
    [ -z "$dead" ] || out=$(slots_jq "$1" "$2" "[${dead#,}]" "$left") || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    rest=${out#*$'\n'}
    SLOTS_RESULT=${rest%%$'\n'*}
    case "$SLOTS_RESULT" in
      true | false) slots_write "${rest#*$'\n'}" || rc=$? ;;
      *) rc=3 ;;
    esac
  fi
  if [ "$rc" -eq 0 ] && [ -n "$left" ]; then
    SLOTS_LEFT=
    [ ${#named[@]} -eq 0 ] || rm -f "${named[@]}"
  fi
  slots_unlock
  return "$rc"
}

# slots_tidy: in a process that lost the store, the step that drops the entries
# its run's units left, when there are any; it fails quietly while the store
# still cannot be used (the loss is told once already).
slots_tidy() {
  [ "$SLOTS_STATE" = lost ] && slots_left_found || return 0
  slots_apply "$SLOTS_TIDY" "" > /dev/null 2>&1 || true
}

# slots_look ID: a look at the store, without its lock, by the waiting unit ID:
# SLOTS_RESULT true once a step has handed it the slot, false while its turn
# has not come. 1 when it needs a step of its own: a free slot, its entry
# missing, a run in the store gone, an entry a unit of its run left when it
# lost the store, or a store it cannot read or write, or a damaged one (the
# step then says which).
slots_look() {
  local out p
  [ -w "$SLOTS_DIR" ] || return 1
  ! slots_left_found || return 1
  out=$(slots_jq "$SLOTS_LOOK" "$1") || return 1
  for p in ${out%%$'\n'*}; do slots_live "$p" || return 1; done
  case "${out#*$'\n'}" in
    held) SLOTS_RESULT=true ;;
    waiting) SLOTS_RESULT=false ;;
    *) return 1 ;;
  esac
}

# slots_open: once per command (checks_open). The store in force: SLOTS_STATE
# on; a run inside a unit on this same store: nested (no slots of its own); a
# store that cannot be used: off, said once on stderr.
slots_open() {
  local why rc
  SLOTS_STATE=off
  SLOTS_DIR="$(vbw_claude_dir)/vbw"
  SLOTS_FILE="$SLOTS_DIR/slots.json"
  SLOTS_LIMIT=$(vbw_machine_limit)
  if [ "${VBW_SLOT_STORE:-}" = "$SLOTS_FILE" ]; then SLOTS_STATE=nested; return 0; fi
  why="cannot write $SLOTS_FILE"
  if mkdir -p "$SLOTS_DIR" 2> /dev/null && slots_lock; then
    slots_jq 'valid | empty' "" && rc=0 || rc=$?
    slots_unlock
    case "$rc" in
      0)
        SLOTS_STATE=on
        [ "$VBW_GUARD_EXIT" -eq 0 ] || trap 'slots_gone ""; vbw_guard_run' EXIT
        return 0
        ;;
      3) why="$SLOTS_FILE is damaged (delete it to restore the limit)" ;;
    esac
  fi
  printf "vbw: the computer-wide limit was not in force: %s; this run was limited by check_jobs (%s) alone\n" "$why" "$(vbw_check_jobs || printf 1)" >&2
}

# slots_traps: on Ctrl-C, TERM and HUP this run's entries (the unit's own in a
# runner) are removed before the guard's cleanup. The EXIT trap (vbw_die ends
# through it) is set once, by slots_open, never in a subshell.
slots_traps() {
  trap 'slots_gone "$SLOTS_UNIT"; vbw_guard_run; exit 130' INT
  trap 'slots_gone "$SLOTS_UNIT"; vbw_guard_run; exit 143' TERM
  trap 'slots_gone "$SLOTS_UNIT"; vbw_guard_run; exit 129' HUP
}

# slots_gone [UNIT]: remove this run's entries (or the unit's), best effort,
# also those of a process that lost the store, which may work again.
slots_gone() {
  [ "$SLOTS_STATE" = on ] || [ "$SLOTS_STATE" = lost ] || return 0
  slots_unlock
  slots_apply "$SLOTS_DROP" "${1:-}" > /dev/null 2>&1 || true
}

# slots_lose RC NAME: the store failed in the middle of the run (RC of
# slots_apply) in a step for NAME: this process goes on without slots, and the
# run's marker file tells the parent (a runner is a subshell whose stderr is
# hidden), which says it once at the end. The entry NAME may have left in the
# store is named for the run's next step to drop (slots_apply).
slots_lose() {
  local why="cannot write $SLOTS_FILE"
  SLOTS_STATE=lost
  SLOTS_MARK=
  [ "$1" -ne 3 ] || why="$SLOTS_FILE is damaged (delete it to restore the limit)"
  if [ -d "${CHECK_OUT:-}" ]; then
    { [ -f "$CHECK_OUT/lost" ] || printf '%s\n' "$why" > "$CHECK_OUT/lost"; } 2> /dev/null || true
    { mkdir -p "$CHECK_OUT/left" && : > "$CHECK_OUT/left/$2"; } 2> /dev/null || SLOTS_LEFT="$SLOTS_LEFT$2"$'\n'
  else
    # The run's folder has ended (the save at the end of a proof): only the
    # command's own shell is running, and it keeps the reason and the entry itself.
    [ -n "$SLOTS_LOST" ] || SLOTS_LOST=$why
    SLOTS_LEFT="$SLOTS_LEFT$2"$'\n'
  fi
}

# slots_hold NAME: wait for a slot of the store and hold it under NAME, without
# the unit mark (a bookkeeping step of the run, R202: vbw:plan, vbw:copies,
# vbw:save). 1 when no slot is in force (store off, lost on the way, or a nested
# run, which takes none): the step then runs anyway. One step joins the wait
# (or takes a free slot at once); the wait itself only looks (slots_look) until
# a step of another run has handed the slot over.
slots_hold() {
  [ "$SLOTS_STATE" = on ] || { slots_tidy; return 1; }
  slots_traps
  local since="" rc=0
  slots_apply "$SLOTS_TAKE" "$1" || rc=$?
  while [ "$rc" -eq 0 ] && [ "$SLOTS_RESULT" != true ]; do
    [ -n "$since" ] || since=$(date +%s)
    # Every waiter looks at the same pace, however long it has waited: the store gives a
    # freed slot to the waiter whose turn it is, and a newer waiter looking more often
    # would start first (no backoff here; slots_nap is for lock retries).
    sleep 0.1
    slots_look "$1" || slots_apply "$SLOTS_TAKE" "$1" || rc=$?
  done
  if [ "$rc" -ne 0 ]; then slots_lose "$rc" "$1"; return 1; fi
  slots_waited "$since"
}

# slots_release NAME: give a bookkeeping slot back.
slots_release() {
  local rc
  [ "$SLOTS_STATE" = on ] || { slots_tidy; return 0; }
  slots_apply "$SLOTS_DROP" "$1" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || slots_lose "$rc" "$1"
  return 0
}

# slots_take UNIT: wait for a slot of the store, then hold it (the mark names the store for the unit's command).
slots_take() {
  [ "$SLOTS_STATE" = on ] || { slots_tidy; return 0; }
  [ -z "$SLOTS_SUB" ] || SLOTS_UNIT=$1
  slots_hold "$1" || return 0
  SLOTS_MARK="VBW_SLOT_STORE=$SLOTS_FILE"
}

# slots_waited SINCE: note how long a unit waited for its slot (SINCE: the
# second it first found none, empty when it found one at once): whole seconds,
# at least 1, one line in the run's waits file. The wait is told to the user
# only (slots_say): it never reaches evidence, the record or the stored runs.
slots_waited() {
  local n
  [ -n "$1" ] || return 0
  n=$(($(date +%s) - $1))
  [ "$n" -ge 1 ] || n=1
  if [ -d "${CHECK_OUT:-}" ]; then
    printf '%s\n' "$n" >> "$CHECK_OUT/waits" 2> /dev/null || true
  else
    # The run's folder has ended: only the command's own shell is running.
    SLOTS_WAITED=$((SLOTS_WAITED + n))
  fi
}

# slots_total: add what the units of the run waited, and the loss one of them
# told, to the command's totals (SLOTS_WAITED, SLOTS_LOST), taken before
# checks_end removes the run's folder. What the command's own shell found is
# already in the totals.
slots_total() {
  local n
  if [ -z "$SLOTS_LOST" ] && [ -f "$CHECK_OUT/lost" ]; then SLOTS_LOST=$(head -n 1 "$CHECK_OUT/lost"); fi
  if [ -f "$CHECK_OUT/waits" ]; then
    n=$(awk '{ n += $1 } END { print n + 0 }' "$CHECK_OUT/waits")
    SLOTS_WAITED=$((SLOTS_WAITED + n))
  fi
}

# slots_say: the last line of a command whose units waited, nothing otherwise;
# each thing is told once.
slots_say() {
  local cores t
  if [ -n "$SLOTS_LOST" ]; then
    printf "vbw: the computer-wide limit was not in force: %s; this run was limited by check_jobs (%s) alone from then on\n" "$SLOTS_LOST" "$(vbw_check_jobs || printf 1)" >&2
    SLOTS_LOST=
  fi
  [ "${SLOTS_WAITED:-0}" -gt 0 ] || return 0
  if [ "$SLOTS_WAITED" -ge 60 ]; then t="$((SLOTS_WAITED / 60)) min"; else t="$SLOTS_WAITED s"; fi
  SLOTS_WAITED=0
  if cores=$(vbw_cores); then
    printf "waited %s for other VBW runs on this computer (limit %s of %s cores)\n" "$t" "$SLOTS_LIMIT" "$cores"
  else
    printf "waited %s for other VBW runs on this computer (limit %s, as this computer's core count could not be read)\n" "$t" "$SLOTS_LIMIT"
  fi
}

# slots_give UNIT: give the slot back (also the place of a unit still waiting).
slots_give() {
  local rc
  # shellcheck disable=SC2034 # read by checks_exec
  SLOTS_MARK=
  [ "$SLOTS_STATE" = on ] || { slots_tidy; return 0; }
  slots_apply "$SLOTS_DROP" "$1" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || slots_lose "$rc" "$1"
  return 0
}
