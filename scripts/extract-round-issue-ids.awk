# extract-round-issue-ids.awk — Print one issue/test ID per failing UAT entry.
#
# Output format:
#   ID

function tolower_str(s,    i, c, out) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c >= "A" && c <= "Z")
      c = sprintf("%c", index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", c) + 96)
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