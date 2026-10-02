#!/usr/bin/env bash
# Consent store (build plan K16): $(git-common-dir)/vbw/consent.json. A
# repository can never ship it (clones do not carry .git contents), it is
# writable under the Claude Code sandbox, and linked worktrees share it.
# Entries: {kind: "contract"|"command", hash, detail, at}.

consent_file() {
  local common
  common=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || vbw_die "not a git repository"
  printf '%s/vbw/consent.json\n' "$common"
}

# SHA-256 of an argv, NUL-separated so "a b" c and a "b c" never collide.
vbw_sha256_argv() {
  printf '%s\0' "$@" | vbw_sha256
}

consent_has() {
  local file
  file=$(consent_file)
  [ -f "$file" ] || return 1
  jq -e --arg k "$1" --arg h "$2" 'any(.granted[]?; .kind == $k and .hash == $h)' "$file" > /dev/null 2>&1
}

# consent_grant KIND HASH DETAIL_JSON: record consent (idempotent, atomic). The
# read-modify-write, file creation included, runs under a lock beside the file,
# so grants from parallel worktrees of one clone are never lost.
consent_grant() {
  local file dir tmp lock
  file=$(consent_file)
  dir=$(dirname "$file")
  mkdir -p "$dir"
  lock="$dir/consent.lock"
  vbw_lock_take "$lock" "consent"
  if ! consent_has "$1" "$2"; then
    [ -f "$file" ] || printf '{"granted":[]}\n' > "$file"
    tmp=$(mktemp "$dir/consent.XXXXXX") || vbw_die "cannot write $dir"
    vbw_guard_add file "$tmp"
    jq --arg k "$1" --arg h "$2" --argjson d "$3" --arg at "$(vbw_now)" \
      '.granted += [{kind: $k, hash: $h, detail: $d, at: $at}]' "$file" > "$tmp" \
      || vbw_die "cannot update $file"
    mv "$tmp" "$file"
    vbw_guard_drop "$tmp"
  fi
  vbw_guard_drop "$lock"
}
