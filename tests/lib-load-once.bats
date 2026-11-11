#!/usr/bin/env bats
# R299 (T280; F441 fixed one case): a kernel library loaded again in the same process keeps
# its state. A vbw command that runs several kernel actions in one process (vbw plan done
# loads checks.sh again; a loop step runs several actions) used to lose what an earlier load
# had counted: slots.sh set SLOTS_WAITED back to 0 at every load, so the 'waited N for other
# VBW runs' line went missing. Every library that keeps state for the life of a process
# (a variable its load sets that one of the kernel's functions changes later) keeps it when
# it is sourced again, under one load-once rule, and nothing saves and restores the waits to
# survive a reload. L1: the libraries sourced into one shell, as bin/vbw sources them.

load helper
load fixture-helper

built() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
setup_file() { fixture_build built built; }
setup() { fixture_copy built; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

@test "R299 slots: slots.sh loaded a second time, through checks.sh, keeps the wait it counted, the lost store and the rest of its state" {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  run vbw_kernel '. "$VBW_LIB/checks.sh"
    unset CHECK_OUT
    slots_waited 9999999999 # a start after now counts the one-second minimum: no clock read here (R152)
    SLOTS_LOST="the store could not be written" SLOTS_STATE=lost SLOTS_LEFT=$'"'"'C3\n'"'"' SLOTS_UNIT=C3 SLOTS_RESULT=true
    before=$(declare -p SLOTS_WAITED SLOTS_LOST SLOTS_STATE SLOTS_LEFT SLOTS_UNIT SLOTS_RESULT SLOTS_LOCKED SLOTS_MARK SLOTS_SUB)
    . "$VBW_LIB/checks.sh"
    after=$(declare -p SLOTS_WAITED SLOTS_LOST SLOTS_STATE SLOTS_LEFT SLOTS_UNIT SLOTS_RESULT SLOTS_LOCKED SLOTS_MARK SLOTS_SUB)
    [ "$before" = "$after" ] || { printf "before the second load:\n%s\nafter it:\n%s\n" "$before" "$after"; exit 1; }
    echo "waited $SLOTS_WAITED"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "waited 1" ] || { echo "$output"; false; }
}

# lib_state LIB: in a fresh shell, the variables LIB's load adds (the base libraries core,
# record, consent and contract loaded first, as bin/vbw loads them, except LIB itself and
# those after it) that some kernel function assigns: the library's state. Then each is set
# to a mark, LIB is sourced again, and every variable that lost its mark is printed as
# "LIB VAR" ("LIB -" when it keeps them all; "LIB state VAR..." lists what was judged).
lib_state() {
  bash -c '
    lib=$1 VBW_LIB="$2/lib"
    base="core record consent contract"
    for l in $base; do
      [ "$l" != "$lib" ] || break
      . "$VBW_LIB/$l.sh"
    done
    case " $base " in *" $lib "*) ;; *) vbw_project ;; esac
    before=$(compgen -v | LC_ALL=C sort)
    . "$VBW_LIB/$lib.sh" > /dev/null 2>&1 || { echo "$lib cannot be loaded"; exit 1; }
    new=$(compgen -v | LC_ALL=C sort | LC_ALL=C comm -13 <(printf "%s\n" "$before") - | grep -E "^[A-Z][A-Z0-9_]*$" || true)
    state=
    for v in $new; do
      hits=$(grep -hE "^[[:space:]]+([^#]*([;&|({]|[[:space:]](then|else|do))[[:space:]]*)?$v(\+)?=" "$VBW_LIB"/*.sh | grep -vE "^[[:space:]]*(local|declare)[[:space:]]" || true)
      [ -z "$hits" ] || state="$state $v"
    done
    echo "$lib state$state"
    for v in $state; do
      case "$(declare -p "$v")" in
        "declare -a"*) read -r -a "$v" <<< "r299-mark" ;;
        *) printf -v "$v" "%s" "r299-mark" ;;
      esac
    done
    . "$VBW_LIB/$lib.sh" > /dev/null 2>&1 || { echo "$lib cannot be loaded again"; exit 1; }
    lost=
    for v in $state; do
      case "$(declare -p "$v" 2> /dev/null)" in *r299-mark*) ;; *) lost="$lost $v" ;; esac
    done
    echo "$lib${lost:- -}"
  ' _ "$1" "$PLUGIN_ROOT"
}

@test "R299 every library: each kernel library that keeps state for the life of a process keeps it when it is sourced again" {
  local f lib out bad='' judged=''
  for f in "$PLUGIN_ROOT"/lib/*.sh; do
    lib=${f##*/}
    lib=${lib%.sh}
    out=$(lib_state "$lib") || { echo "$out"; false; }
    judged="$judged $(printf '%s\n' "$out" | sed -n "s/^$lib state//p")"
    printf '%s\n' "$out" | tail -n 1 | grep -qx "$lib -" || bad="$bad"$'\n'"$(printf '%s\n' "$out" | tail -n 1)"
  done
  # The search for state finds what is known to be state, so it cannot pass by finding none.
  for v in VBW_GUARD_FILES SLOTS_WAITED SLOTS_LOST CHECKS_TIMER PROOFCOPY_CLAIMED PROOFTIME_T0 QA_TREE_REPOS; do
    [[ " $judged " == *" $v "* ]] || { echo "the state search missed $v; it judged:$judged"; false; }
  done
  [ -z "$bad" ] || { echo "libraries that lose their state when sourced again (library, then the variables lost):$bad"; false; }
}

@test "R299: nothing saves and restores SLOTS_WAITED or SLOTS_LOST to survive a reload: mutate-queue.sh leaves them to slots.sh" {
  ! grep -nE '(^|[^A-Z_])SLOTS_(WAITED|LOST)=|=\$SLOTS_(WAITED|LOST)' "$PLUGIN_ROOT/lib/mutate-queue.sh" || false
}
