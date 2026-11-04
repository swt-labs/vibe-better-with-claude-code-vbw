#!/usr/bin/env bash
# check-jq-builtins.sh [FILE...]: jq 1.7.0 is the floor (R223). With no
# argument it scans every tracked plugin/**/*.jq and plugin/**/*.sh; with
# arguments, the files given. It refuses a use of a builtin that arrived after
# jq 1.7.0 (trim, ltrim, rtrim, abs, toarray, trimstr, have_decnum, and add
# with an argument) outside comment lines and outside a "def <name>" line,
# unless the file defines that name itself. Prints
# FILE:LINE: NAME needs jq 1.8; the floor is 1.7, and exits 1 on any hit.
set -euo pipefail

names="trim ltrim rtrim abs toarray trimstr have_decnum add("

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  root=$(cd "$(dirname "$0")/.." && pwd)
  files=()
  while IFS= read -r -d '' f; do
    case "$f" in
      plugin/*.jq | plugin/*.sh) files+=("$root/$f") ;;
    esac
  done < <(git -C "$root" ls-files -z -- plugin)
fi

status=0
for file in ${files[@]+"${files[@]}"}; do
  out=$(awk -v names="$names" -v file="$file" '
    function isword(c) { return c ~ /[A-Za-z0-9_]/ }
    { line[NR] = $0 }
    END {
      n = split(names, nm, " ")
      for (k = 1; k <= n; k++) {
        name = nm[k]; call = 0
        if (name == "add(") { name = "add"; call = 1 }
        defd = 0
        for (i = 1; i <= NR; i++) if (line[i] ~ ("(^|[^A-Za-z0-9_])def[ \t]+" name "([^A-Za-z0-9_]|$)")) defd = 1
        if (defd) continue
        for (i = 1; i <= NR; i++) {
          s = line[i]
          if (s ~ /^[ \t]*#/) continue
          hit = 0; rest = s; off = 0
          while ((p = index(rest, name)) > 0) {
            before = (off + p > 1) ? substr(s, off + p - 1, 1) : ""
            after = substr(s, off + p + length(name), 1)
            ok = !isword(before) && before != "." && before != "$"
            # a variable name given to jq (--arg abs ...) is not a builtin call
            if (ok && substr(s, 1, off + p - 1) ~ /--(arg|argjson|rawfile|slurpfile)[ \t]+$/) ok = 0
            if (call) ok = ok && after == "("
            else ok = ok && !isword(after)
            if (ok) { hit = 1; break }
            off += p; rest = substr(s, off + 1)
          }
          if (hit) printf "%s:%d: %s needs jq 1.8; the floor is 1.7\n", file, i, name (call ? "(" : "")
        }
      }
    }' "$file")
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    status=1
  fi
done
exit "$status"
