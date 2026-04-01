#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"

  mkdir -p bin curl-log
  export FAKE_CURL_DIR="$TEST_TEMP_DIR/curl-log"

  cat > bin/curl <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

payload=""
attachment_path=""
url=""
header_file=""
body_file=""
write_out=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--data|--data-raw|--data-binary)
      payload="$2"
      shift 2
      ;;
    -F)
      form_field="$2"
      case "$form_field" in
        payload_json=*)
          payload="${form_field#payload_json=}"
          ;;
        files\[0\]=@*)
          attachment_path="${form_field#*=@}"
          attachment_path="${attachment_path%%;*}"
          ;;
      esac
      shift 2
      ;;
    -H|--header)
      shift 2
      ;;
    -D|-o|-w)
      case "$1" in
        -D) header_file="$2" ;;
        -o) body_file="$2" ;;
        -w) write_out="$2" ;;
      esac
      shift 2
      ;;
    -s|-S|-sS)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

attempt_count=0
if [ -f "$FAKE_CURL_DIR/attempt-count" ]; then
  attempt_count=$(cat "$FAKE_CURL_DIR/attempt-count")
fi
attempt_count=$((attempt_count + 1))
printf '%s' "$attempt_count" > "$FAKE_CURL_DIR/attempt-count"

http_code="${FAKE_CURL_DEFAULT_HTTP:-200}"
if [ -n "${FAKE_CURL_FAIL_ON_ATTEMPT:-}" ] && [ "$attempt_count" -eq "$FAKE_CURL_FAIL_ON_ATTEMPT" ]; then
  http_code="${FAKE_CURL_FAIL_HTTP:-429}"
fi

if [ -n "$header_file" ]; then
  if [ "$http_code" = "429" ]; then
    printf 'HTTP/1.1 429 Too Many Requests\r\nRetry-After: %s\r\nX-RateLimit-Reset-After: %s\r\n\r\n' \
      "${FAKE_CURL_RETRY_AFTER:-0}" "${FAKE_CURL_RETRY_AFTER:-0}" > "$header_file"
  else
    printf 'HTTP/1.1 %s OK\r\n\r\n' "$http_code" > "$header_file"
  fi
fi

if [ -n "${FAKE_CURL_DELIVER_AND_FAIL_ON_ATTEMPT:-}" ] && [ "$attempt_count" -eq "$FAKE_CURL_DELIVER_AND_FAIL_ON_ATTEMPT" ]; then
  posted_count=0
  if [ -f "$FAKE_CURL_DIR/posted-count" ]; then
    posted_count=$(cat "$FAKE_CURL_DIR/posted-count")
  fi
  posted_count=$((posted_count + 1))
  printf '%s' "$posted_count" > "$FAKE_CURL_DIR/posted-count"
  printf '%s' "$payload" > "$FAKE_CURL_DIR/payload-$posted_count.json"
  printf '%s' "$url" > "$FAKE_CURL_DIR/url-$posted_count.txt"
  if [ -n "$attachment_path" ]; then
    cp "$attachment_path" "$FAKE_CURL_DIR/attachment-$posted_count.md"
  fi
  if [ -n "$body_file" ]; then
    : > "$body_file"
  fi
  if [ -n "$write_out" ] && [ "$write_out" = '%{http_code}' ]; then
    printf '000'
  fi
  printf 'simulated network failure after send\n' >&2
  exit "${FAKE_CURL_DELIVER_AND_FAIL_EXIT_CODE:-56}"
fi

if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
  posted_count=0
  if [ -f "$FAKE_CURL_DIR/posted-count" ]; then
    posted_count=$(cat "$FAKE_CURL_DIR/posted-count")
  fi
  posted_count=$((posted_count + 1))
  printf '%s' "$posted_count" > "$FAKE_CURL_DIR/posted-count"
  printf '%s' "$payload" > "$FAKE_CURL_DIR/payload-$posted_count.json"
  printf '%s' "$url" > "$FAKE_CURL_DIR/url-$posted_count.txt"
  if [ -n "$attachment_path" ]; then
    cp "$attachment_path" "$FAKE_CURL_DIR/attachment-$posted_count.md"
  fi
  response_body=$(printf '{"id":"message-%s"}\n' "$posted_count")
else
  response_body=$(printf '{"message":"request failed","retry_after":%s,"global":false}\n' "${FAKE_CURL_RETRY_AFTER:-0}")
fi

if [ -n "$body_file" ]; then
  printf '%s' "$response_body" > "$body_file"
else
  printf '%s' "$response_body"
fi

if [ -n "$write_out" ]; then
  if [ "$write_out" = '%{http_code}' ]; then
    printf '%s' "$http_code"
  else
    printf '%s' "$write_out"
  fi
fi
EOF
  chmod +x bin/curl

  export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

payload_count() {
  if [ -f "$FAKE_CURL_DIR/posted-count" ]; then
    cat "$FAKE_CURL_DIR/posted-count"
  else
    echo 0
  fi
}

attempt_count() {
  if [ -f "$FAKE_CURL_DIR/attempt-count" ]; then
    cat "$FAKE_CURL_DIR/attempt-count"
  else
    echo 0
  fi
}

@test "uses release name when present and disables mentions" {
  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME="VBW 1.31.0"
  export RELEASE_TAG="v1.31.0"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.0"
  export RELEASE_BODY=$'Added Discord release notifications.\nNo bare links anymore.'

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 0 ]
  [ "$(payload_count)" -eq 1 ]
  [ ! -e "$FAKE_CURL_DIR/attachment-1.md" ]

  run jq -r '.embeds[0].title' "$FAKE_CURL_DIR/payload-1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "Release VBW 1.31.0" ]

  run jq -r '.embeds[0].url' "$FAKE_CURL_DIR/payload-1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$RELEASE_URL" ]

  run jq -r '.embeds[0].description' "$FAKE_CURL_DIR/payload-1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$RELEASE_BODY" ]

  run jq -c '.allowed_mentions' "$FAKE_CURL_DIR/payload-1.json"
  [ "$status" -eq 0 ]
  [ "$output" = '{"parse":[]}' ]

  run cat "$FAKE_CURL_DIR/url-1.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "https://discord.example/webhook?wait=true" ]
}

@test "attaches the full release notes when the embed description would overflow" {
  local long_body
  long_body="$(printf 'section-%04d\n' $(seq 1 700))"

  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME=""
  export RELEASE_TAG="v1.31.1"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.1"
  export RELEASE_BODY="$long_body"

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 0 ]
  [ "$(payload_count)" -eq 1 ]

  run cat "$FAKE_CURL_DIR/attachment-1.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$long_body" ]

  run jq -r '.attachments[0].filename' "$FAKE_CURL_DIR/payload-1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "release-notes.md" ]

  run jq -r '.embeds[0].description' "$FAKE_CURL_DIR/payload-1.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Full release notes attached as `release-notes.md`.' ]]
  [ ${#output} -le 4096 ]
}

@test "retries a rate-limited request and still posts the notification" {
  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME=""
  export RELEASE_TAG="v1.31.2"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.2"
  export RELEASE_BODY="Release notes"
  export FAKE_CURL_FAIL_ON_ATTEMPT=1
  export FAKE_CURL_FAIL_HTTP=429
  export FAKE_CURL_RETRY_AFTER=0

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 0 ]
  [ "$(payload_count)" -eq 1 ]
  [ "$(attempt_count)" -eq 2 ]
}

@test "does not retry an ambiguously delivered notification request" {
  local long_body
  long_body="$(printf 'section-%04d\n' $(seq 1 700))"

  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME=""
  export RELEASE_TAG="v1.31.3"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.3"
  export RELEASE_BODY="$long_body"
  export FAKE_CURL_DELIVER_AND_FAIL_ON_ATTEMPT=1
  export FAKE_CURL_DELIVER_AND_FAIL_EXIT_CODE=56

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 1 ]
  [ "$(payload_count)" -eq 1 ]
  [ "$(attempt_count)" -eq 1 ]

  run cat "$FAKE_CURL_DIR/attachment-1.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$long_body" ]
}