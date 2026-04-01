# parse-uat-issues.awk — Extract compact issue lines from a UAT markdown file.
#
# Output format:
#   ID|SEVERITY|DESCRIPTION
#
# The caller is responsible for header generation, round counting, recurrence
# tracking, and any consistency guards.

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

function emit_issue() {
  if (description == "" && inline_issue != "") description = inline_issue
  if (description == "") description = "(no description)"
  if (severity == "") {
    ldesc = tolower_str(description)
    if (ldesc ~ /crash|broken|error|doesnt work|fails|exception/)
      severity = "critical"
    else if (ldesc ~ /wrong|incorrect|missing|not working|bug/)
      severity = "major"
    else if (ldesc ~ /minor|cosmetic|nitpick|small|typo|polish/)
      severity = "minor"
    else
      severity = "major"
  }
  gsub(/\|/, "-", description)
  printf "%s|%s|%s\n", id, severity, description
  has_issue = 0
  description = ""
  severity = ""
  inline_issue = ""
}

/^### [PD][0-9]/ {
  if (has_issue) emit_issue()
  id = $2
  sub(/:$/, "", id)
  has_issue = 0
  description = ""
  severity = ""
  inline_issue = ""
  next
}

/^- \*\*Result:\*\*/ {
  val = $0
  sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
  gsub(/[[:space:]]+$/, "", val)
  lval = tolower_str(val)
  if (lval ~ /^(issue|fail|failed|partial)/)
    has_issue = 1
  next
}

has_issue && /^- \*\*Issue:\*\*/ {
  itxt = $0
  sub(/^- \*\*Issue:\*\*[[:space:]]*/, "", itxt)
  gsub(/[[:space:]]+$/, "", itxt)
  if (itxt != "" && itxt != "{if result=issue}") inline_issue = itxt
  next
}

has_issue && /^[[:space:]]*- Description:/ {
  desc = $0
  sub(/^[[:space:]]*- Description:[[:space:]]*/, "", desc)
  gsub(/[[:space:]]+$/, "", desc)
  description = desc
  if (severity != "") emit_issue()
  next
}

has_issue && /^[[:space:]]*- \*\*Description:\*\*/ {
  desc = $0
  sub(/^[[:space:]]*- \*\*Description:\*\*[[:space:]]*/, "", desc)
  gsub(/[[:space:]]+$/, "", desc)
  description = desc
  if (severity != "") emit_issue()
  next
}

has_issue && /^[[:space:]]*- Severity:/ {
  sev = $0
  sub(/^[[:space:]]*- Severity:[[:space:]]*/, "", sev)
  gsub(/[[:space:]]+$/, "", sev)
  severity = tolower_str(sev)
  if (description != "" || inline_issue != "") emit_issue()
  next
}

has_issue && /^[[:space:]]*- \*\*Severity:\*\*/ {
  sev = $0
  sub(/^[[:space:]]*- \*\*Severity:\*\*[[:space:]]*/, "", sev)
  gsub(/[[:space:]]+$/, "", sev)
  severity = tolower_str(sev)
  if (description != "" || inline_issue != "") emit_issue()
  next
}

/^### / || /^## / {
  if (has_issue) emit_issue()
  has_issue = 0
  description = ""
  severity = ""
  inline_issue = ""
}

END {
  if (has_issue) emit_issue()
}