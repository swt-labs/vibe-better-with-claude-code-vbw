#!/usr/bin/env bash

# run-all-state-utils.sh — shared run-all suite coordination helpers.
# Source from testing/run-all.sh or test harnesses that need to query the same
# active-peer invariant used by the local auto-throttle path.

initialize_run_all_state() {
  local repo_identity

  repo_identity="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || printf '%s/.git' "$ROOT")"
  case "$repo_identity" in
    /*) ;;
    *) repo_identity="$ROOT/$repo_identity" ;;
  esac
  repo_identity="$(cd "$repo_identity" 2>/dev/null && pwd || printf '%s' "$repo_identity")"
  RUN_ALL_REPO_KEY="$(printf '%s' "$repo_identity" | jq -sRr @uri 2>/dev/null || true)"
  RUN_ALL_STATE_DIR="$RUN_ALL_STATE_ROOT"
  if [ -n "$RUN_ALL_REPO_KEY" ]; then
    RUN_ALL_STATE_DIR="$RUN_ALL_STATE_ROOT/$RUN_ALL_REPO_KEY"
  fi
  RUN_ALL_PROCESS_START="$(ps -o lstart= -p $$ 2>/dev/null || true)"
  RUN_ALL_PROCESS_COMMAND="$(ps -o command= -p $$ 2>/dev/null || true)"
}

run_all_token_is_valid() {
  local entry="$1"
  local pid repo_key process_start process_command current_start current_command

  [ -f "$entry" ] || return 1

  pid="$(jq -r '.pid // empty' "$entry" 2>/dev/null || true)"
  repo_key="$(jq -r '.repo_key // empty' "$entry" 2>/dev/null || true)"
  process_start="$(jq -r '.process_start // empty' "$entry" 2>/dev/null || true)"
  process_command="$(jq -r '.process_command // empty' "$entry" 2>/dev/null || true)"

  case "$pid" in
    ''|*[!0-9]*)
      rm -f "$entry" 2>/dev/null || true
      return 1
      ;;
  esac

  if [ -z "$repo_key" ] || [ -z "$process_start" ] || [ -z "$process_command" ]; then
    rm -f "$entry" 2>/dev/null || true
    return 1
  fi

  if [ "$repo_key" != "$RUN_ALL_REPO_KEY" ]; then
    rm -f "$entry" 2>/dev/null || true
    return 1
  fi

  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$entry" 2>/dev/null || true
    return 1
  fi

  current_start="$(ps -o lstart= -p "$pid" 2>/dev/null || true)"
  current_command="$(ps -o command= -p "$pid" 2>/dev/null || true)"

  if [ -z "$current_start" ] || [ -z "$current_command" ]; then
    rm -f "$entry" 2>/dev/null || true
    return 1
  fi

  if [ "$process_start" != "$current_start" ] || [ "$process_command" != "$current_command" ]; then
    rm -f "$entry" 2>/dev/null || true
    return 1
  fi

  case "$current_command" in
    *"run-all.sh"*)
      return 0
      ;;
  esac

  rm -f "$entry" 2>/dev/null || true
  return 1
}

prune_run_all_tokens() {
  local entry

  [ -d "$RUN_ALL_STATE_DIR" ] || return 0

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    run_all_token_is_valid "$entry" >/dev/null 2>&1 || true
  done < <(find "$RUN_ALL_STATE_DIR" -maxdepth 1 -type f -name 'suite.*.token' -print 2>/dev/null)
}

count_run_all_tokens() {
  local count=0 entry

  [ -d "$RUN_ALL_STATE_DIR" ] || {
    echo 0
    return 0
  }

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if run_all_token_is_valid "$entry"; then
      count=$((count + 1))
    fi
  done < <(find "$RUN_ALL_STATE_DIR" -maxdepth 1 -type f -name 'suite.*.token' -print 2>/dev/null)

  echo "$count"
}

count_run_all_tokens_with_grace() {
  local attempt current_count observed_count=0

  for attempt in 1 2 3 4; do
    current_count="$(count_run_all_tokens)"
    if [ "$current_count" -gt "$observed_count" ]; then
      observed_count="$current_count"
    fi
    if [ "$observed_count" -gt 1 ] || [ "$attempt" -eq 4 ]; then
      break
    fi
    sleep 0.05
  done

  echo "$observed_count"
}

register_run_all_token() {
  local final_token

  [ -n "$RUN_ALL_REPO_KEY" ] || return 1
  [ -n "$RUN_ALL_PROCESS_START" ] || return 1
  [ -n "$RUN_ALL_PROCESS_COMMAND" ] || return 1
  mkdir -p "$RUN_ALL_STATE_DIR" 2>/dev/null || return 1
  prune_run_all_tokens
  RUN_ALL_TOKEN="$(mktemp "$RUN_ALL_STATE_DIR/suite.$$.XXXXXX.token.tmp" 2>/dev/null)" || {
    RUN_ALL_TOKEN=""
    return 1
  }
  if ! jq -n \
    --arg pid "$$" \
    --arg repo_key "$RUN_ALL_REPO_KEY" \
    --arg process_start "$RUN_ALL_PROCESS_START" \
    --arg process_command "$RUN_ALL_PROCESS_COMMAND" \
    '{pid: $pid, repo_key: $repo_key, process_start: $process_start, process_command: $process_command}' > "$RUN_ALL_TOKEN"; then
    rm -f "$RUN_ALL_TOKEN"
    RUN_ALL_TOKEN=""
    return 1
  fi
  final_token="${RUN_ALL_TOKEN%.tmp}"
  if ! mv "$RUN_ALL_TOKEN" "$final_token"; then
    rm -f "$RUN_ALL_TOKEN"
    RUN_ALL_TOKEN=""
    return 1
  fi
  RUN_ALL_TOKEN="$final_token"
}