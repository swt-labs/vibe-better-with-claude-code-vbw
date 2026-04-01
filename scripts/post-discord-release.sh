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
readonly ATTACHMENT_FILENAME="release-notes.md"
readonly ATTACHMENT_NOTICE=$'\n\nFull release notes attached as `release-notes.md`.'

build_execute_url() {
  case "$1" in
    *\?*) printf '%s&wait=true\n' "$1" ;;
    *) printf '%s?wait=true\n' "$1" ;;
  esac
}

truncate_title() {
  "$JQ_BIN" -rn \
    --arg value "$1" \
    --argjson max_len "$MAX_EMBED_TITLE" \
    'if ($value | length) <= $max_len then $value else $value[0:($max_len - 3)] + "..." end'
}

build_description_metadata() {
  "$JQ_BIN" -cn \
    --arg body "$1" \
    --arg notice "$ATTACHMENT_NOTICE" \
    --argjson max_len "$MAX_EMBED_DESCRIPTION" \
    'if ($body | length) <= $max_len
     then { description: $body, attach_full_body: false }
     else { description: ($body[0:($max_len - ($notice | length))] + $notice), attach_full_body: true }
     end'
}

build_payload() {
  "$JQ_BIN" -cn \
    --arg title "$1" \
    --arg url "$2" \
    --arg description "$3" \
    --arg filename "$4" \
    --argjson color "$DISCORD_COLOR" \
    '{
      allowed_mentions: { parse: [] },
      embeds: [
        {
          title: $title,
          url: $url,
          description: $description,
          color: $color
        }
      ]
    } + (if $filename == "" then {} else { attachments: [{ id: 0, filename: $filename }] } end)'
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

post_message_with_retry() {
  local payload="$1" response_path="$2" attachment_path="${3:-}" action_label="$4"
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
    if [ -n "$attachment_path" ]; then
      http_code=$("$CURL_BIN" -sS \
        -D "$headers_file" \
        -o "$body_file" \
        -F "payload_json=$payload" \
        -F "files[0]=@$attachment_path;filename=$ATTACHMENT_FILENAME;type=text/markdown" \
        -w '%{http_code}' \
        "$execute_url" 2>"$stderr_file")
    else
      http_code=$("$CURL_BIN" -sS \
        -D "$headers_file" \
        -o "$body_file" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -w '%{http_code}' \
        "$execute_url" 2>"$stderr_file")
    fi
    curl_exit=$?
    set -e

    if [ "$curl_exit" -eq 0 ] && [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
      cp "$body_file" "$response_path"
      rm -f "$headers_file" "$body_file" "$stderr_file"
      return 0
    fi

    if [ "$attempt" -lt "$MAX_POST_ATTEMPTS" ] && [ "$curl_exit" -eq 0 ] && is_retryable_http_code "$http_code"; then
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
description_metadata=$(build_description_metadata "$body_text")
description_text=$("$JQ_BIN" -r '.description' <<< "$description_metadata")
attach_full_body=$("$JQ_BIN" -r '.attach_full_body' <<< "$description_metadata")
attachment_filename=""
attachment_path=""
response_body_file=$(mktemp)
trap 'rm -f "$response_body_file" "${attachment_path:-}"' EXIT

if [ "$attach_full_body" = "true" ]; then
  attachment_filename="$ATTACHMENT_FILENAME"
  attachment_path=$(mktemp)
  printf '%s' "$body_text" > "$attachment_path"
fi

payload=$(build_payload "$display_title" "$RELEASE_URL" "$description_text" "$attachment_filename")
post_message_with_retry "$payload" "$response_body_file" "$attachment_path" "post release notification"

printf 'Posted Discord release notification for %s\n' "$RELEASE_TAG"