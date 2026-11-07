#!/usr/bin/env bash
# check-captured-writes.sh DIR...: no shell function ends by handing text it
# captured out through a builtin printf or echo. A function whose last command
# is a bare builtin printf or echo of one variable that the function assigned
# from a command substitution (VAR=$(...)) writes that text (a parsed spec, a
# record: kilobytes) in the shell of the function's caller while the
# substitution's child may still be exiting. macOS /bin/bash 3.2 catches
# SIGCHLD without SA_RESTART, so a write that waits for a slow reader fails
# with EINTR ("write error: Interrupted system call") and loses the text. The
# fix is vbw_out (core.sh), which writes from a subshell of its own.
# On every *.sh file under each DIR it prints 'FILE:LINE: FUNCTION' for each
# such function, with LINE that of the write, and exits 1. A write through
# vbw_out, of a literal or an argument, into a pipe or a file (or any
# redirection), and a function that ends with another command pass. A function
# on the allow-list below never counts. --allowed prints the allow-list, one
# 'name: reason' per line.
set -euo pipefail

# The allow-list: one 'name: reason' per entry; a reason says why the write
# cannot lose the text (a small value, a writer that never races a child).
ALLOWED=(
)

if [ "${1:-}" = "--allowed" ]; then
  for e in ${ALLOWED[@]+"${ALLOWED[@]}"}; do printf '%s\n' "$e"; done
  exit 0
fi
[ $# -ge 1 ] || { printf 'usage: check-captured-writes.sh DIR... | --allowed\n' >&2; exit 2; }
for d in "$@"; do
  [ -d "$d" ] || { printf 'no directory: %s\n' "$d" >&2; exit 2; }
done
files=()
while IFS= read -r -d '' path; do
  files+=("$path")
done < <(for d in "$@"; do find "$d" -type f -name '*.sh' -print0; done)
[ "${#files[@]}" -gt 0 ] || exit 0
skip=""
for e in ${ALLOWED[@]+"${ALLOWED[@]}"}; do skip="$skip ${e%%:*}"; done

hits=0
for f in "${files[@]}"; do
  out=$(awk -v skip="$skip " -v file="$f" '
    function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # check(name, first, last, one): the function body on lines first..last.
    function check(name, first, last, one,    j, cmd, n, a, v, pat, lastj) {
      lastj = 0
      for (j = last; j >= first; j--) {
        if (L[j] ~ /^[ \t]*(#|$)/) continue
        lastj = j; break
      }
      if (!lastj) return
      cmd = L[lastj]
      if (one) { sub(/\}[ \t]*$/, "", cmd); sub(/^[^{]*\{/, "", cmd) }
      # The last command of a line that holds several: the text after the last ;.
      n = split(cmd, a, ";")
      for (j = n; j >= 1; j--) { if (trim(a[j]) != "") { cmd = trim(a[j]); break } }
      if (cmd !~ /^(printf|echo)([ \t]|$)/) return
      if (cmd ~ /^echo/) {
        sub(/^echo[ \t]*/, "", cmd)
        while (cmd ~ /^-[neE]+[ \t]/) sub(/^-[neE]+[ \t]+/, "", cmd)
      } else {
        sub(/^printf[ \t]*/, "", cmd)
        # The format: one quoted or bare word.
        if (cmd ~ /^\047[^\047]*\047/) { match(cmd, /^\047[^\047]*\047/); cmd = substr(cmd, RLENGTH + 1) }
        else if (cmd ~ /^"[^"]*"/) { match(cmd, /^"[^"]*"/); cmd = substr(cmd, RLENGTH + 1) }
        else sub(/^[^ \t]+/, "", cmd)
      }
      cmd = trim(cmd)
      # Exactly one variable: anything after it (a pipe, a redirection) passes.
      if (cmd !~ /^"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?$/) return
      v = cmd; gsub(/["${}]/, "", v)
      if (index(skip, " " name " ")) return
      pat = "(^|[^A-Za-z0-9_])" v "=\\$\\([^(]"
      for (j = first; j <= lastj; j++) {
        if (L[j] ~ /^[ \t]*#/) continue
        if (L[j] ~ pat) { print file ":" lastj ": " name; return }
      }
    }
    { L[FNR] = $0; N = FNR }
    END {
      for (j = 1; j <= N; j++) {
        if (!match(L[j], /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*(\(\))?[ \t]*\{/)) continue
        x = substr(L[j], 1, RLENGTH)
        if (x !~ /\(\)/ && x !~ /^[ \t]*function[ \t]/) continue
        sub(/^[ \t]*(function[ \t]+)?/, "", x)
        match(x, /^[A-Za-z_][A-Za-z0-9_]*/)
        name = substr(x, 1, RLENGTH)
        if (L[j] ~ /\}[ \t]*$/ && L[j] !~ /\{[ \t]*$/) { check(name, j, j, 1); continue }
        for (k = j + 1; k <= N; k++) {
          if (L[k] ~ /^[ \t]*\}/ && indent(L[k]) == indent(L[j])) break
        }
        if (k <= N) check(name, j + 1, k - 1, 0)
      }
    }
  ' "$f")
  if [ -n "$out" ]; then printf '%s\n' "$out"; hits=1; fi
done
[ "$hits" -eq 0 ] || exit 1
