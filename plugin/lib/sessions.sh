#!/usr/bin/env bash
# VBW's read-only view of Claude Code's list of chats (R192):
# <claude-config-dir>/sessions/*.json, one file per running session. It is the
# only thing VBW reads outside the project. A name taken from it is kept on this
# computer only (.vbw/runtime/holder.json), never in the record (D442).

# sessions_registry: a JSON array of the list's entries (objects with a string
# sessionId). Malformed files are skipped; [] when the folder is missing or
# unreadable. Exit 0 always.
sessions_registry() {
  local dir f files=()
  dir="$(vbw_claude_dir)/sessions"
  for f in "$dir"/*.json; do
    [ -f "$f" ] && files+=("$f")
  done
  if [ ${#files[@]} -eq 0 ]; then
    printf '[]\n'
    return 0
  fi
  # One jq pass. A marker line before each file keeps files apart even when one
  # has no final newline (jq would join its last line to the next file's first).
  {
    for f in "${files[@]}"; do
      printf '\001VBW-FILE\n'
      cat "$f" 2> /dev/null || true
      printf '\n'
    done
  } | jq -Rn -c '[(reduce inputs as $l ([]; if $l == "\u0001VBW-FILE" then . + [[]] elif length == 0 then . else .[-1] += [$l] end))[]
      | join("\n") | try fromjson catch empty
      | select(type == "object" and (.sessionId | type) == "string")]' 2> /dev/null || printf '[]\n'
  return 0
}

# sessions_record_path SID: the file in which a session that loaded a plugin copy with
# --plugin-dir records that copy's folder (<claude-config-dir>/vbw/sessions/SID, written
# by hooks/session-start.sh, read by the status line and by doctor). Only a plain name
# is an id (letters, digits, _ and -, as in the hook and the status line, which apply
# the same rule to the id Claude Code hands them); anything else prints nothing and
# returns 1, so an id from the environment never names a file outside that folder.
sessions_record_path() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  printf '%s/vbw/sessions/%s\n' "$(vbw_claude_dir)" "$1"
}

# sessions_name SID: the newest updatedAt entry's name, cleaned, or nothing.
sessions_name() {
  [ -n "${1:-}" ] || return 0
  sessions_registry | jq -r --arg s "$1" "$(cat "$VBW_LIB/holder.jq")"'
    [.[] | select(.sessionId == $s)] | sort_by(.updatedAt | if type == "number" then . else 0 end) | last
    | (.name // null) | clean_name | select(length > 0)' 2> /dev/null || true
  return 0
}

# sessions_project_entries ROOT: the entries whose cwd is ROOT or a folder under it.
# Folders are compared by their physical path (symbolic links resolved, as git
# reports the project root), so /var and /private/var on macOS are one folder; a
# folder that no longer exists is resolved through its nearest existing parent.
# One-pass rule: the registry is read by one jq and matched by one jq, whatever
# the number of chats; the shell only resolves each distinct folder (no jq per
# entry), because a 594-plan project's chat list cost one jq start per open chat
# (T229). No function of this file runs jq inside a loop over entries.
sessions_project_entries() {
  local reg root cwd phys map='' up tail
  reg=$(sessions_registry)
  root=$(cd "$1" 2> /dev/null && pwd -P) || root=${1%/}
  while IFS= read -r cwd; do
    [ -n "$cwd" ] || continue
    up=$cwd tail=
    case "$cwd" in /*) ;; *) up=/ ;; esac
    until phys=$(cd "$up" 2> /dev/null && pwd -P); do
      case "$up" in / | . | '') phys=$cwd tail=; break ;; esac
      tail=/${up##*/}$tail
      up=${up%/*}
      [ -n "$up" ] || up=/
    done
    case "$cwd" in /*) phys=${phys%/}$tail ;; *) phys=$cwd ;; esac
    map+=$cwd$'\001'$phys$'\n'
  done < <(printf '%s' "$reg" | jq -r '[.[] | .cwd | select(type == "string")] | unique | .[]' 2> /dev/null)
  # The binding is in parentheses of its own: after "and", jq 1.7 binds only the
  # term and jq 1.8 the whole "A and B" (its binding precedence changed).
  printf '%s' "$reg" | jq -c --arg r "${root%/}" --arg ms "$map" '($ms | split("\n") | map(select(length > 0) | split("\u0001") | {(.[0]): .[1]}) | add // {}) as $m
    | [.[] | select((.cwd | type) == "string"
    and (($m[.cwd] // .cwd | rtrimstr("/")) as $c | $c == $r or ($c | startswith($r + "/"))))]' 2> /dev/null || printf '[]\n'
  return 0
}

holder_file() { printf '%s/holder.json' "$VBW_RUNTIME"; }

# holder_write RUN SID: .vbw/runtime/holder.json {run, session, session_name, head}
# (session_name null when unknown; head, the project's commit when the run starts,
# null when it has none: the Bash guard compares a script file with it, R255), through
# a temporary name and a rename.
holder_write() {
  local name tmp head
  name=$(sessions_name "$2")
  head=$(git -C "$VBW_ROOT" rev-parse --verify --quiet HEAD 2> /dev/null) || head=''
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || return 0
  tmp=$(mktemp "$VBW_RUNTIME/holder.XXXXXX" 2> /dev/null) || return 0
  vbw_guard_add file "$tmp"
  if jq -nc --arg r "$1" --arg s "$2" --arg n "$name" --arg h "$head" \
    '{run: $r, session: $s, session_name: (if $n == "" then null else $n end), head: (if $h == "" then null else $h end)}' > "$tmp" 2> /dev/null; then
    mv "$tmp" "$(holder_file)" 2> /dev/null || true
  fi
  vbw_guard_drop "$tmp"
  rm -f "$tmp" 2> /dev/null || true
  return 0
}

holder_clear() { rm -f "$(holder_file)" 2> /dev/null || true; }

# holder_display SID: the display name of the holder: the list's live name, else
# holder.json's name (only when its session is SID), else 8 characters of the id.
holder_display() {
  local live
  live=$(sessions_name "${1:-}")
  jq -rn --arg s "${1:-}" --arg live "$live" --rawfile h <(cat "$(holder_file)" 2> /dev/null || true) \
    "$(cat "$VBW_LIB/holder.jq")"'
    ($h | try fromjson catch null) as $f
    | holder_name({session: $s}; (if ($f | type) == "object" and $f.session == $s then $f.session_name else null end); $live)'
}

# sessions_rename_hint SID ROOT NAME: the one sentence that suggests /rename
# (D444), printed once per clone: when the list holds two or more chats on ROOT,
# SID's newest entry still has the name Claude Code gave it (nameSource auto or
# derived), and this clone's settings carry no rename_hint. It records
# rename_hint (the time) there under the settings lock, then prints. VBW never
# renames a chat. Prints nothing otherwise; exit 0 always.
sessions_rename_hint() {
  [ -n "${1:-}" ] || return 0
  local file lock tmp ok marked
  ok=$(sessions_project_entries "$2" | jq -r --arg s "$1" 'if length >= 2 then
      ([.[] | select(.sessionId == $s)] | sort_by(.updatedAt | if type == "number" then . else 0 end) | last
        | if . == null then false else (.nameSource // "auto") as $n | $n == "auto" or $n == "derived" end)
    else false end' 2> /dev/null) || ok=false
  [ "$ok" = true ] || return 0
  file=$(vbw_clone_settings_file 2> /dev/null) || return 0
  jq -e 'type == "object" and (has("rename_hint") | not)' "$file" > /dev/null 2>&1 || [ ! -e "$file" ] || return 0
  marked=$(
    mkdir -p "${file%/*}" 2> /dev/null || exit 1
    lock="${file%/*}/settings.lock"
    vbw_lock_take "$lock" "this clone's settings" 2> /dev/null
    [ -f "$file" ] || printf '{}\n' > "$file"
    tmp=$(mktemp "${file%/*}/settings.XXXXXX") || exit 1
    vbw_guard_add file "$tmp"
    # Checked again under the lock: two chats asking at once give the hint once.
    jq -e 'has("rename_hint") | not' "$file" > /dev/null 2>&1 || exit 1
    jq --arg t "$(vbw_now)" '.rename_hint = $t' "$file" > "$tmp" 2> /dev/null || exit 1
    mv "$tmp" "$file"
    vbw_guard_drop "$tmp"
    vbw_guard_drop "$lock"
    printf 'marked'
  ) 2> /dev/null || true
  # The subshell's own exit status is not trusted (its cleanup may fail): only
  # reaching the end, after the mark was written, gives the hint.
  [ "$marked" = marked ] || return 0
  printf 'Another chat is open on this project: /rename vbw · %s gives this chat a name the other chats will see.\n' "$3"
  return 0
}
