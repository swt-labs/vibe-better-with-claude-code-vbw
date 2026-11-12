#!/usr/bin/env bash
# One kernel run per plan at a time (R293, docs/workflows.md). vbw plan done PLAN and
# vbw mutate PLAN --run each hold a marker file of their own for the whole run: the file
# holds the run's process id (taken by the exclusive create, vbw_lock_create). A second
# run of the same command on the same plan finds a live holder and is refused at once,
# naming the holder's pid, the time it started (the marker's own time, as HH:MM, worded
# as the 'since HH:MM' wait line) and its command, then a Next: line to wait for it and
# never start a second one. A marker whose holder has ended, or that holds no readable
# id, is taken over (vbw_lock_takeover). The marker is registered with the guard, so it
# is given back however the run ends.

# plan_run_hold MARKER WHAT COMMAND NEXT: take MARKER, or refuse while a live run holds it.
# WHAT says what runs ("another run of P's queued breaks"), COMMAND is the holder's command
# line, NEXT the text of the Next: line (after "Next: ").
plan_run_hold() {
  local marker="$1" what="$2" cmd="$3" next="$4" i owner since
  mkdir -p "${marker%/*}" || vbw_die "cannot create ${marker%/*}"
  for ((i = 0; i < 50; i++)); do
    if vbw_lock_create "$marker"; then
      vbw_guard_add lock "$marker"
      return 0
    fi
    owner=$(vbw_lock_holder "$marker")
    if [ -n "$owner" ] && vbw_lock_alive "$owner"; then
      since=$(vbw_hhmm "$(vbw_mtime "$marker")")
      vbw_die "$what is still running (pid $owner, since $since, $cmd)"$'\n'"Next: $next"
    fi
    if vbw_lock_takeover "$marker" "$owner"; then
      vbw_guard_add lock "$marker"
      return 0
    fi
  done
  vbw_die "$what is still running ($cmd)"$'\n'"Next: $next"
}
