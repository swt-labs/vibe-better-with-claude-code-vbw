# waiting_judge BUDGET MARGIN QUICK SLOW [SLOW2]: judges the waiting case of
# tests/timed-bench-hooks.bats over the bench's printed lines, as the bench judges.
# Prints one line: 'busy S' when any given run's sh-and-jq startup S is above BUDGET;
# else 'ok' when SLOW's guard (git) own cost minus QUICK's is under MARGIN; else 'again'
# when no SLOW2 is given; else 'ok' or 'fail <words>' (exit 1). Bash 3.2, no sleep.

# waiting_own LINES: the guard (git) own cost, in ms.
waiting_own() { printf '%s\n' "$1" | sed -n 's/^guard (git): \([0-9.]*\) ms.*/\1/p' | head -n 1; }

# waiting_startup LINES: the run's sh-and-jq startup, in ms.
waiting_startup() {
  local s
  s=$(printf '%s\n' "$1" | sed -n 's/^guard (git): .*(sh and jq startup \([0-9.]*\) ms).*/\1/p' | head -n 1)
  [ -n "$s" ] || s=$(printf '%s\n' "$1" | sed -n 's/^machine too busy to measure.* takes \([0-9.]*\) ms.*/\1/p' | head -n 1)
  printf '%s\n' "$s"
}

# waiting_under A B MARGIN: true when A - B is under MARGIN.
waiting_under() { perl -e 'exit($ARGV[0] - $ARGV[1] < $ARGV[2] ? 0 : 1)' -- "$1" "$2" "$3"; }

waiting_judge() {
  local budget=$1 margin=$2 quick=$3 slow=$4 slow2=${5-} run s q o1 o2
  for run in "$quick" "$slow" ${slow2:+"$slow2"}; do
    s=$(waiting_startup "$run")
    if [ -n "$s" ] && perl -e 'exit($ARGV[0] > $ARGV[1] ? 0 : 1)' -- "$s" "$budget"; then
      echo "busy $s"
      return 0
    fi
  done
  q=$(waiting_own "$quick"); o1=$(waiting_own "$slow")
  if [ -z "$q" ] || [ -z "$o1" ]; then echo "fail no guard (git) line in the bench output"; return 1; fi
  if waiting_under "$o1" "$q" "$margin"; then echo ok; return 0; fi
  [ -n "$slow2" ] || { echo again; return 0; }
  o2=$(waiting_own "$slow2")
  if [ -z "$o2" ]; then echo "fail no guard (git) line in the second measure"; return 1; fi
  if waiting_under "$o2" "$q" "$margin"; then echo ok; return 0; fi
  echo "fail waiting counted: quick $q ms; first measure $o1 ms with the wait, second measure $o2 ms with the wait; margin $margin ms"
  return 1
}
