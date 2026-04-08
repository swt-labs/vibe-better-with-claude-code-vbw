# extract-round-issue-ids.awk — Print one issue/test ID per failing UAT entry.
#
# Output format:
#   ID

function tolower_str(s,    i, c, out, upper, lower, pos) {
  upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  lower = "abcdefghijklmnopqrstuvwxyz"
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    pos = index(upper, c)
    if (pos > 0)
      c = substr(lower, pos, 1)
    out = out c
  }
  return out
}

/^### [PD][0-9]/ {
  id = $2
  sub(/:$/, "", id)
  next
}

/^- \*\*Result:\*\*/ {
  val = $0
  sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
  gsub(/[[:space:]]+$/, "", val)
  lval = tolower_str(val)
  if (lval ~ /^(issue|fail|failed|partial)/)
    print id
}