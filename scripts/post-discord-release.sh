#!/usr/bin/env bash
set -euo pipefail

: "${WEBHOOK_URL:?WEBHOOK_URL is required}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${RELEASE_URL:?RELEASE_URL is required}"

JQ_BIN="${JQ_BIN:-jq}"
CURL_BIN="${CURL_BIN:-curl}"
RELEASE_NAME="${RELEASE_NAME:-}"
RELEASE_BODY="${RELEASE_BODY:-}"

readonly MAX_EMBED_TITLE=256
readonly MAX_EMBED_DESCRIPTION=4096
readonly MAX_POST_ATTEMPTS=5
readonly DISCORD_COLOR=5814783

build_execute_url() {
  case "$1" in
    *\?*) printf '%s&wait=true\n' "$1" ;;
    *) printf '%s?wait=true\n' "$1" ;;
  esac
}

build_message_delete_url() {
  local webhook_url="$1" message_id="$2" base query

  base="${webhook_url%%\?*}"
  if [ "$base" = "$webhook_url" ]; then
    printf '%s/messages/%s\n' "$webhook_url" "$message_id"
  else
    query="${webhook_url#*\?}"
    printf '%s/messages/%s?%s\n' "$base" "$message_id" "$query"
  fi
}

truncate_title() {
  "$JQ_BIN" -rn \
    --arg value "$1" \
    --argjson max_len "$MAX_EMBED_TITLE" \
    'if ($value | length) <= $max_len then $value else $value[0:($max_len - 3)] + "..." end'
}

chunk_body() {
  "$JQ_BIN" -cn \
    --arg body "$1" \
    --argjson chunk_size "$MAX_EMBED_DESCRIPTION" \
    'if ($body | length) == 0
     then [""]
     else [range(0; ($body | length); $chunk_size) as $offset | $body[$offset:($offset + $chunk_size)]]
     end'
}

build_payload() {
  "$JQ_BIN" -cn \
    --arg title "$1" \
    --arg url "$2" \
    --argjson chunks "$3" \
    --argjson index "$4" \
    --arg footer "$5" \
    --argjson color "$DISCORD_COLOR" \
    '{
      allowed_mentions: { parse: [] },
      embeds: [
        ({
          title: $title,
          url: $url,
          description: $chunks[$index],
          color: $color
        } + (if $footer == "" then {} else { footer: { text: $footer } } end))
      ]
    }'
}

extract_retry_after_from_headers() {
  tr '[:upper:]' '[:lower:]' < "$1" |
    awk -F ': *' '/^retry-after:/ { gsub("\r", "", $2); print $2; exit }'
}

extract_retry_after_from_body() {
  "$JQ_BIN" -r 'if (.retry_after? // empty) == empty then empty else (.retry_after | tostring) end' "$1" 2>/dev/null || true
}

retry_delay_for() {
  local http_code="$1" headers_file="$2" body_file="$3" attempt="$4" retry_after

  if [ "$http_code" = "429" ]; then
    retry_after=$(extract_retry_after_from_headers "$headers_file")
    if [ -z "$retry_after" ]; then
      retry_after=$(extract_retry_after_from_body "$body_file")
    fi
  fi

  if [ -z "${retry_after:-}" ]; then
    retry_after="$attempt"
  fi

  printf '%s\n' "$retry_after"
}

is_retryable_http_code() {
  case "$1" in
    429|500|502|503|504) return 0 ;;
    *) return 1 ;;
  esac
}

should_retry_request() {
  local method="$1" curl_exit="$2" http_code="$3"

  if [ "$curl_exit" -ne 0 ]; then
    [ "$method" != "POST" ]
    return $?
  fi

  is_retryable_http_code "$http_code"
}

request_with_retry() {
  local method="$1" url="$2" action_label="$3" response_path="$4" payload="${5:-}"
  local headers_file body_file stderr_file
  local attempt curl_exit http_code retry_after error_detail

  headers_file=$(mktemp)
  body_file=$(mktemp)
  stderr_file=$(mktemp)

  attempt=1
  while [ "$attempt" -le "$MAX_POST_ATTEMPTS" ]; do
    : > "$headers_file"
    : > "$body_file"
    : > "$stderr_file"

    set +e
    if [ -n "$payload" ]; then
      http_code=$("$CURL_BIN" -sS \
        -X "$method" \
        -D "$headers_file" \
        -o "$body_file" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -w '%{http_code}' \
        "$url" 2>"$stderr_file")
    else
      http_code=$("$CURL_BIN" -sS \
        -X "$method" \
        -D "$headers_file" \
        -o "$body_file" \
        -w '%{http_code}' \
        "$url" 2>"$stderr_file")
    fi
    curl_exit=$?
    set -e

    if [ "$curl_exit" -eq 0 ] && [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
      if [ -n "$response_path" ]; then
        cp "$body_file" "$response_path"
      fi
      rm -f "$headers_file" "$body_file" "$stderr_file"
      return 0
    fi

    if [ "$attempt" -lt "$MAX_POST_ATTEMPTS" ] && should_retry_request "$method" "$curl_exit" "$http_code"; then
      retry_after=$(retry_delay_for "$http_code" "$headers_file" "$body_file" "$attempt")
      printf 'Retrying %s after %ss (attempt %s/%s)\n' \
        "$action_label" "$retry_after" "$((attempt + 1))" "$MAX_POST_ATTEMPTS" >&2
      sleep "$retry_after"
      attempt=$((attempt + 1))
      continue
    fi

    error_detail=$(tr '\n' ' ' < "$body_file")
    if [ -z "$error_detail" ]; then
      error_detail=$(tr '\n' ' ' < "$stderr_file")
    fi

    if [ "$curl_exit" -ne 0 ]; then
      printf 'Failed to complete %s after %s attempt(s) (curl exit %s): %s\n' \
        "$action_label" "$attempt" "$curl_exit" "$error_detail" >&2
    else
      printf 'Failed to complete %s after %s attempt(s) (HTTP %s): %s\n' \
        "$action_label" "$attempt" "$http_code" "$error_detail" >&2
    fi

    rm -f "$headers_file" "$body_file" "$stderr_file"
    return 1
  done

  rm -f "$headers_file" "$body_file" "$stderr_file"
}

rollback_posted_messages() {
  local idx message_id delete_url rollback_failed=0

  [ "${#posted_message_ids[@]}" -gt 0 ] || return 0

  printf 'Rolling back %s previously posted Discord message(s)\n' "${#posted_message_ids[@]}" >&2
  for ((idx = ${#posted_message_ids[@]} - 1; idx >= 0; idx--)); do
    message_id="${posted_message_ids[$idx]}"
    delete_url=$(build_message_delete_url "$WEBHOOK_URL" "$message_id")
    if ! request_with_retry DELETE "$delete_url" "delete message $message_id during rollback" ""; then
      rollback_failed=1
    fi
  done

  return "$rollback_failed"
}

release_label="$RELEASE_TAG"
if [ -n "$RELEASE_NAME" ]; then
  release_label="$RELEASE_NAME"
fi

display_title=$(truncate_title "Release $release_label")
body_text="$RELEASE_BODY"
if [ -z "$body_text" ]; then
  body_text="_No release notes provided._"
fi

execute_url=$(build_execute_url "$WEBHOOK_URL")
chunks_json=$(chunk_body "$body_text")
chunk_count=$("$JQ_BIN" -rn --argjson chunks "$chunks_json" '$chunks | length')
response_body_file=$(mktemp)
trap 'rm -f "$response_body_file"' EXIT

declare -a posted_message_ids=()

for ((i = 0; i < chunk_count; i++)); do
  local_chunk_label="chunk $((i + 1))/$chunk_count"
  footer=""
  if [ "$chunk_count" -gt 1 ]; then
    footer="Part $((i + 1)) of $chunk_count"
  fi

  payload=$(build_payload "$display_title" "$RELEASE_URL" "$chunks_json" "$i" "$footer")

  if request_with_retry POST "$execute_url" "post $local_chunk_label" "$response_body_file" "$payload"; then
    message_id=$("$JQ_BIN" -r '.id // empty' "$response_body_file")
    if [ -z "$message_id" ]; then
      printf 'Discord did not return a message id for %s; manual cleanup may be required.\n' "$local_chunk_label" >&2
      rollback_posted_messages || printf 'Rollback failed after missing message id.\n' >&2
      exit 1
    fi
    posted_message_ids+=("$message_id")
  else
    rollback_posted_messages || printf 'Rollback failed after a terminal posting error.\n' >&2
    exit 1
  fi
done

printf 'Posted %s Discord message(s) for %s\n' "$chunk_count" "$RELEASE_TAG"