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
readonly DISCORD_COLOR=5814783

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

for ((i = 0; i < chunk_count; i++)); do
  footer=""
  if [ "$chunk_count" -gt 1 ]; then
    footer="Part $((i + 1)) of $chunk_count"
  fi

  payload=$(build_payload "$display_title" "$RELEASE_URL" "$chunks_json" "$i" "$footer")

  "$CURL_BIN" -fsS \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$execute_url" > /dev/null
done

printf 'Posted %s Discord message(s) for %s\n' "$chunk_count" "$RELEASE_TAG"