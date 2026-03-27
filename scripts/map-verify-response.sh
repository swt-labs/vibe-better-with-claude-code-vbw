#!/usr/bin/env bash
set -u

# map-verify-response.sh
# Deterministic helper for verify.md freeform intent mapping.
# Pure bash — no grep/awk to avoid GNU vs BSD portability issues.
# Output: pass | skip | issue | pass_with_observation | skip_with_observation

input="${*:-}"
if [ -z "$input" ] && [ ! -t 0 ]; then
  input="$(cat)"
fi

if [ -z "$input" ]; then
  echo "issue"
  exit 0
fi

normalized=$(printf '%s' "$input" |  tr '\n' ' ' |  tr '[:upper:]' '[:lower:]' |
  sed -E "s/[’‘]/'/g; s/[–—]/-/g; s/[[:space:]]+/ /g; s/^ //; s/ $//")

skip_re='(^|[^[:alnum:]_])(skip|skipped|next|n/a|na|later|defer)([^[:alnum:]_]|$)'
pass_re="(^|[^[:alnum:]_])(pass|passed|looks good|works|correct|confirmed|yes|good|fine|ok|okay|not bad|can't complain|cant complain|cannot complain)([^[:alnum:]_]|$)"
idiom_positive_re="(^|[^[:alnum:]_])(not bad|can't complain|cant complain|cannot complain)([^[:alnum:]_]|$)"
separator_re=' but | however | although | though | also |[,;.:] | - '
issue_signal_re='(broken|bug|error|wrong|incorrect|missing|not working|doesnt work|fails|fail|failing|crash|exception|regress|problem|glitch|unusable|blocked|still)'
negated_pass_re="(not|no|never|don't|doesn't|didn't|isn't|wasn't|cannot|can't|cant|won't|wont|wouldn't|shouldn't|hardly|barely|neither|nor)( [a-z]+){0,3} (pass|passed|works|work|good|fine|ok|okay|correct|confirmed)"
negated_think_works_re="(don't|doesn't|didn't|cannot|can't|cant) (think|feel|guess|believe|know)( [a-z]+){0,4} (work|works|working)"
# Uncertainty phrases are NOT pass-intent — they indicate the user is unsure.
# If present without a clear pass keyword, the response falls through to issue.
uncertainty_re='(^|[^[:alnum:]_])(i think so|i think|i guess|maybe|not sure|possibly|i believe so|probably|hard to tell|i suppose)([^[:alnum:]_]|$)'
skip_deferral_re="skip( this)?( checkpoint| test)?( for now| right now)?|can't test( right now| now)?|cannot test( right now| now)?|defer( this| for now)?"

# Use bash [[ =~ ]] instead of grep/awk for cross-platform portability.
matches_re() {
  [[ "$1" =~ $2 ]]
}

# Find 1-based position of first regex match, or 0 if no match.
first_pos() {
  local text="$1"
  local re="$2"
  if [[ "$text" =~ $re ]]; then
    local match="${BASH_REMATCH[0]}"
    local before="${text%%"$match"*}"
    echo $(( ${#before} + 1 ))
  else
    echo 0
  fi
}

# Extract text after the first separator match.
tail_text=""
if matches_re "$normalized" "$separator_re"; then
  local_match="${BASH_REMATCH[0]}"
  tail_text="${normalized#*"$local_match"}"
fi

has_skip=0
has_pass=0
idiomatic_positive=0
tail_has_issue=0

matches_re "$normalized" "$skip_re" && has_skip=1 || true
matches_re "$normalized" "$pass_re" && has_pass=1 || true
matches_re "$normalized" "$idiom_positive_re" && idiomatic_positive=1 || true

# Uncertainty guard: if hedging phrases present without a clear pass keyword,
# the response is ambiguous and must be treated as issue.
has_uncertainty=0
matches_re "$normalized" "$uncertainty_re" && has_uncertainty=1 || true
if [ "$has_uncertainty" -eq 1 ] && [ "$has_pass" -eq 0 ]; then
  echo "issue"
  exit 0
fi

if [ -n "${tail_text:-}" ] && matches_re "$tail_text" "$issue_signal_re"; then
  tail_has_issue=1
  # "still" false-positive guard: if the only defect signal is "still" and it's
  # followed by a positive word (works, working, fine, good, correct, properly,
  # functioning, responsive, loads, launches), it's temporal not defective.
  if [[ "$tail_text" =~ still ]] && ! [[ "$tail_text" =~ (broken|bug|error|wrong|incorrect|missing|not\ working|doesnt\ work|fails|fail|failing|crash|exception|regress|problem|glitch|unusable|blocked) ]]; then
    still_positive_re='still (works|working|fine|good|correct|properly|functioning|responsive|loads|launches|runs|ok|okay|passes|functions|operates|running)'
    if matches_re "$tail_text" "$still_positive_re"; then
      tail_has_issue=0
    fi
  fi
fi

# Expanded negation guard, with idiomatic-positive exceptions.
if [ "$has_pass" -eq 1 ] && [ "$idiomatic_positive" -eq 0 ]; then
  if matches_re "$normalized" "$negated_pass_re" || matches_re "$normalized" "$negated_think_works_re"; then
    echo "issue"
    exit 0
  fi
fi

primary="none"

if [ "$has_skip" -eq 1 ] && [ "$has_pass" -eq 1 ]; then
  if matches_re "$normalized" "$skip_deferral_re"; then
    primary="skip"
  else
    pass_pos=$(first_pos "$normalized" "$pass_re")
    skip_pos=$(first_pos "$normalized" "$skip_re")
    if [ "$skip_pos" -gt 0 ] && { [ "$pass_pos" -eq 0 ] || [ "$skip_pos" -le "$pass_pos" ]; }; then
      primary="skip"
    else
      primary="pass"
    fi
  fi
elif [ "$has_skip" -eq 1 ]; then
  primary="skip"
elif [ "$has_pass" -eq 1 ]; then
  primary="pass"
fi

case "$primary" in
  skip)
    if [ "$tail_has_issue" -eq 1 ]; then
      echo "skip_with_observation"
    else
      echo "skip"
    fi
    ;;
  pass)
    if [ "$tail_has_issue" -eq 1 ]; then
      echo "pass_with_observation"
    else
      echo "pass"
    fi
    ;;
  *)
    echo "issue"
    ;;
esac
