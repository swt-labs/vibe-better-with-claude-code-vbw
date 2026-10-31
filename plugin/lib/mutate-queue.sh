#!/usr/bin/env bash
# Rule breaks side by side (T174, docs/workflows.md). Sourced by cmd-mutate.sh.
#   vbw mutate PLAN Rn.k --queue WHAT FILE...   set one break aside, files back at once, nothing runs
#   vbw mutate PLAN --run                       run every queued break of PLAN, side by side
# A queued break waits in .vbw/runtime/mutate-queue/PLAN/NNNN/: files/ holds its
# broken bytes (a file it deleted is absent), meta.json what it is {target, req,
# rk, check, what, files, broke, head, tree}. The run judges each break as the single
# form does: the rule's check once on the unbroken code (unless a recorded break of
# the same committed code, tree as vbw_head_tree counts it, already ran it), then each break in its own proof copy, as many at
# a time as there are copies (check_jobs, under the computer-wide slots), and each
# result recorded in queue order (mutate_record). A break queued at other committed
# code (another commit of the project or of a submodule) is dropped and named: its bytes belong to older files.
# One --run of a plan at a time (R230): the run holds the marker
# .vbw/runtime/mutate-queue/PLAN/run.pid with its own pid from before it reads any
# entry until it ends, on every end. A second run finds a live pid and is refused;
# a marker of a dead, empty or unreadable pid is taken over (vbw_lock_takeover).

# mutate_queue_dir PLAN: the plan's queue folder.
mutate_queue_dir() {
  printf '%s/mutate-queue/%s\n' "$VBW_RUNTIME" "$1"
}

# mutate_queue_entries PLAN: the queued breaks' folders, in queue order, one per line.
mutate_queue_entries() {
  local d
  for d in "$(mutate_queue_dir "$1")"/[0-9]*; do
    [ -f "$d/meta.json" ] && printf '%s\n' "$d"
  done
  return 0
}

# mutate_queue_add PLAN DIR META_JSON: the set-aside folder DIR joins the plan's queue.
mutate_queue_add() {
  local q n=0 d k
  q=$(mutate_queue_dir "$1")
  mkdir -p "$q" || vbw_die "cannot create $q"
  for d in "$q"/[0-9]*; do
    [ -d "$d" ] || continue
    k=${d##*/}
    k=$((10#$k))
    [ "$k" -le "$n" ] || n=$k
  done
  printf '%s\n' "$3" > "$2/meta.json" || vbw_die "cannot write the queued break"
  mv "$2" "$q/$(printf '%04d' $((n + 1)))" || vbw_die "cannot queue the break in $q"
  printf '%s queued (%s waiting): run them all with vbw mutate %s --run\n' \
    "$(printf '%s' "$3" | jq -r .target)" "$(mutate_queue_entries "$1" | wc -l | tr -d ' ')" "$1"
}

# mutate_queue_hold PLAN: take the plan's run marker run.pid, or refuse while a live run holds it.
mutate_queue_hold() {
  local plan="$1" q marker owner i msg next
  q=$(mutate_queue_dir "$plan")
  marker="$q/run.pid"
  next="Next: wait for it to finish (a long run started in the background: read its whole result when it ends), then run vbw mutate $plan --run again only if breaks are still queued; never start a second run of the same plan"
  mkdir -p "$q" || vbw_die "cannot create $q"
  for ((i = 0; i < 50; i++)); do
    if vbw_lock_create "$marker"; then
      vbw_guard_add lock "$marker"
      return 0
    fi
    owner=$(vbw_lock_holder "$marker")
    if [ -n "$owner" ] && vbw_lock_alive "$owner"; then
      msg="another run of $plan's queued breaks is still running (pid $owner, vbw mutate $plan --run)"
      vbw_die "$msg"$'\n'"$next"
    fi
    if vbw_lock_takeover "$marker" "$owner"; then
      vbw_guard_add lock "$marker"
      return 0
    fi
  done
  msg="another run of $plan's queued breaks is still running (vbw mutate $plan --run)"
  vbw_die "$msg"$'\n'"$next"
}

# mutate_queue_release PLAN: give up the run marker, and the folder when nothing is left in it.
mutate_queue_release() {
  local q
  q=$(mutate_queue_dir "$1")
  vbw_guard_drop "$q/run.pid"
  rmdir "$q" 2> /dev/null || true
}

# mutate_queue_run PLAN: vbw mutate PLAN --run.
mutate_queue_run() {
  local plan="$1" record head tree e entries=() keep=() stale=0 surv=0 bad='' checks ids=() cfiles=() f base unb=() n i k
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  record=$(record_read)
  printf '%s' "$record" | jq -e --arg p "$plan" 'any(.plans[]; .id == $p)' > /dev/null || vbw_die "unknown plan $plan: vbw show roadmap lists the plans"
  mutate_queue_hold "$plan"
  while IFS= read -r e; do [ -n "$e" ] && entries+=("$e"); done < <(mutate_queue_entries "$plan")
  if [ ${#entries[@]} -eq 0 ]; then
    mutate_queue_release "$plan"
    vbw_die "no break waits for $plan: make each break and queue it with vbw mutate $plan Rn.k --queue \"what you broke\" FILE..., then run vbw mutate $plan --run"
  fi
  head=$(git rev-parse HEAD) || vbw_die "the project has no commit yet"
  tree=$(vbw_head_tree) || vbw_die "cannot fingerprint the committed code"
  for e in "${entries[@]}"; do
    if [ "$(jq -r '.tree // ""' "$e/meta.json")" = "$tree" ]; then keep+=("$e"); continue; fi
    printf '%s was queued at another commit, so its break is of older files: break it again\n' "$(jq -r .target "$e/meta.json")" >&2
    rm -rf "$e"
    stale=1
  done
  [ ${#keep[@]} -gt 0 ] || { mutate_queue_release "$plan"; return 1; }
  # The checks the breaks need, each once, and their files: those must be the committed ones.
  checks=$(for e in "${keep[@]}"; do jq -r .check "$e/meta.json"; done | jq -R . | jq -sc 'unique')
  while IFS= read -r f; do [ -n "$f" ] && ids+=("$f"); done < <(printf '%s' "$checks" | jq -r '.[]')
  while IFS= read -r -d '' f; do cfiles+=("$f"); done < <(printf '%s' "$record" | jq -j --argjson ids "$checks" '[.checks[] | select(.id as $c | $ids | index($c) != null) | .files // [] | .[]] | unique[] | . + "\u0000"')
  if [ ${#cfiles[@]} -gt 0 ] && [ -n "$(vbw_dirty_files "${cfiles[@]}")" ]; then
    vbw_die "check files differ from the last commit: $(vbw_dirty_files "${cfiles[@]}"): commit them first, so the breaks are run against the approved tests"
  fi
  checks_begin "$record"
  base=$(printf '%s' "$record" | jq -c --arg p "$plan" --arg t "$tree" \
    '[.plans[] | select(.id == $p) | (.mutations // [])[] | select(.tree == $t) | (.checks // {}) | keys[]] | unique')
  for f in "${ids[@]}"; do
    printf '%s' "$base" | jq -e --arg c "$f" 'index($c) != null' > /dev/null || unb+=("$f")
  done
  n=${#keep[@]}
  [ "$n" -ge ${#unb[@]} ] || n=${#unb[@]}
  n=$(proofcopy_slots "$n")
  printf 'running %s breaks of %s, %s at a time\n' "${#keep[@]}" "$plan" "$n"
  mutate_time_begin
  proofcopy_create_slots "$n"
  mutate_tstep copies
  # Each check once on the unbroken code: a check red there makes every break of it prove nothing.
  if [ ${#unb[@]} -gt 0 ]; then
    bad=$(checks_run_all "$record" "${unb[@]}" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')
    mutate_tstep unbroken
    if [ -n "$bad" ]; then
      proofcopy_remove
      checks_end
      rm -rf "$(mutate_queue_dir "$plan")"
      vbw_die "checks do not pass on the unbroken code, so a break proves nothing: $bad; make them pass and commit, then break again (the queued breaks are dropped)"
    fi
  fi
  # The breaks, one per copy, a wave at a time: each copy gets its break, runs its
  # rule's check pinned to it (.slot), and goes back to HEAD before the next wave.
  local units unit res broke=() m names
  for ((i = 0; i < ${#keep[@]}; i += n)); do
    units='[]'
    names=
    for ((k = 0; k < n && i + k < ${#keep[@]}; k++)); do
      e=${keep[$((i + k))]}
      names="$names $(jq -r .target "$e/meta.json")"
      broke=()
      while IFS= read -r -d '' f; do broke+=("$f"); done < <(jq -j '.broke[] + "\u0000"' "$e/meta.json")
      mutate_put "$e" "${PROOF_COPIES[$k]}" "${broke[@]}"
      unit=$(checks_unit "$record" "$(jq -r .check "$e/meta.json")")
      units=$(printf '%s' "$units" | jq -c --argjson u "$unit" --argjson k "$k" \
        '. + [$u + {name: "break\($k)", out: "break\($k).out", slot: $k}]')
    done
    mutate_tstep copies
    res=$(checks_run_units "$units")
    if [ "$k" -gt 1 ]; then mutate_tstep "breaks$names"; else mutate_tstep "break$names"; fi
    for ((k = 0; k < n && i + k < ${#keep[@]}; k++)); do
      e=${keep[$((i + k))]}
      broke=()
      while IFS= read -r -d '' f; do broke+=("$f"); done < <(jq -j '.broke[] + "\u0000"' "$e/meta.json")
      mutate_clean "${PROOF_COPIES[$k]}" "${broke[@]}"
      printf '%s' "$res" | jq -c --arg b "break$k" --arg c "$(jq -r .check "$e/meta.json")" '{($c): .[$b]}' > "$e/result.json"
    done
  done
  mutate_tstep copies
  proofcopy_remove
  mutate_tstep copies
  checks_end
  # The results, recorded in queue order as the single form records one; the
  # computer-wide wait is said once, at the end.
  local waited=$SLOTS_WAITED lost=$SLOTS_LOST ruledoc
  SLOTS_WAITED=0 SLOTS_LOST=
  for e in "${keep[@]}"; do
    m=$(jq -c . "$e/meta.json")
    ruledoc=$(printf '%s' "$record" | jq -c --argjson m "$m" '.requirements[] | select(.id == $m.req) | (.rules // [])[$m.rk - 1] | {req: $m.req, text, check}')
    mutate_record "$plan" "$(printf '%s' "$m" | jq -r .target)" "$(printf '%s' "$m" | jq -r .what)" "$head" "$(cat "$e/result.json")" \
      "$(record_read)" "$ruledoc" "" "$(printf '%s' "$m" | jq -c .files)" "$tree" || surv=1
    rm -rf "$e"
  done
  mutate_queue_release "$plan"
  SLOTS_WAITED=$waited SLOTS_LOST=$lost
  mutate_time_say
  slots_say
  [ "$surv" = 0 ] && [ "$stale" = 0 ]
}
