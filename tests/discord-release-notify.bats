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
url=""
header_file=""
body_file=""
write_out=""
method="POST"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--data|--data-raw|--data-binary)
      payload="$2"
      shift 2
      ;;
    -H|--header)
      shift 2
      ;;
    -X)
      method="$2"
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
    -f|-s|-S|-fsS|-sf|-fS|-sSf|-fs|-sS)
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

if [ -n "${FAKE_CURL_FAIL_EXIT_ON_ATTEMPT:-}" ] && [ "$attempt_count" -eq "$FAKE_CURL_FAIL_EXIT_ON_ATTEMPT" ]; then
  printf 'simulated network failure\n' >&2
  if [ -n "$write_out" ] && [ "$write_out" = '%{http_code}' ]; then
    printf '000'
  fi
  exit "${FAKE_CURL_FAIL_EXIT_CODE:-7}"
fi

http_code="${FAKE_CURL_DEFAULT_HTTP:-200}"
if [ "$method" = "DELETE" ] && [ -z "${FAKE_CURL_DEFAULT_HTTP:-}" ]; then
  http_code=204
fi
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

if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
  if [ "$method" = "DELETE" ]; then
    deleted_count=0
    if [ -f "$FAKE_CURL_DIR/deleted-count" ]; then
      deleted_count=$(cat "$FAKE_CURL_DIR/deleted-count")
    fi
    deleted_count=$((deleted_count + 1))

    printf '%s' "$deleted_count" > "$FAKE_CURL_DIR/deleted-count"
    printf '%s' "$url" > "$FAKE_CURL_DIR/delete-url-$deleted_count.txt"
    response_body=""
  else
    posted_count=0
    if [ -f "$FAKE_CURL_DIR/posted-count" ]; then
      posted_count=$(cat "$FAKE_CURL_DIR/posted-count")
    fi
    posted_count=$((posted_count + 1))

    printf '%s' "$posted_count" > "$FAKE_CURL_DIR/posted-count"
    printf '%s' "$payload" > "$FAKE_CURL_DIR/payload-$posted_count.json"
    printf '%s' "$url" > "$FAKE_CURL_DIR/url-$posted_count.txt"
    response_body=$(printf '{"id":"message-%s"}\n' "$posted_count")
  fi
else
  response_body=$(printf '{"message":"rate limited","retry_after":%s,"global":false}\n' "${FAKE_CURL_RETRY_AFTER:-0}")
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

delete_count() {
  if [ -f "$FAKE_CURL_DIR/deleted-count" ]; then
    cat "$FAKE_CURL_DIR/deleted-count"
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

@test "splits long release notes across multiple webhook posts without truncation" {
  local long_body
  long_body="$(printf 'section-%04d\n' $(seq 1 700))"

  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME=""
  export RELEASE_TAG="v1.31.1"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.1"
  export RELEASE_BODY="$long_body"

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 0 ]
  [ "$(payload_count)" -gt 1 ]

  run jq -r '.embeds[0].title' "$FAKE_CURL_DIR/payload-1.json"
  [ "$status" -eq 0 ]
  [ "$output" = "Release v1.31.1" ]

  run jq -r -s '[ .[] | .embeds[0].description ] | join("")' "$FAKE_CURL_DIR"/payload-*.json
  [ "$status" -eq 0 ]
  [ "$output" = "$long_body" ]

  run jq -s 'all(.[]; (.embeds[0].description | length) <= 4096)' "$FAKE_CURL_DIR"/payload-*.json
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "retries a rate-limited chunk and still posts the full changelog" {
  local long_body
  long_body="$(printf 'section-%04d\n' $(seq 1 700))"

  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME=""
  export RELEASE_TAG="v1.31.2"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.2"
  export RELEASE_BODY="$long_body"
  export FAKE_CURL_FAIL_ON_ATTEMPT=2
  export FAKE_CURL_FAIL_HTTP=429
  export FAKE_CURL_RETRY_AFTER=0

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 0 ]
  [ "$(payload_count)" -eq 3 ]
  [ "$(attempt_count)" -eq 4 ]

  run jq -r -s '[ .[] | .embeds[0].description ] | join("")' "$FAKE_CURL_DIR"/payload-*.json
  [ "$status" -eq 0 ]
  [ "$output" = "$long_body" ]
}

@test "retries a transient curl failure and still posts the full changelog" {
  local long_body
  long_body="$(printf 'section-%04d\n' $(seq 1 700))"

  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME=""
  export RELEASE_TAG="v1.31.3"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.3"
  export RELEASE_BODY="$long_body"
  export FAKE_CURL_FAIL_EXIT_ON_ATTEMPT=1
  export FAKE_CURL_FAIL_EXIT_CODE=7

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 0 ]
  [ "$(payload_count)" -eq 3 ]
  [ "$(attempt_count)" -eq 4 ]

  run jq -r -s '[ .[] | .embeds[0].description ] | join("")' "$FAKE_CURL_DIR"/payload-*.json
  [ "$status" -eq 0 ]
  [ "$output" = "$long_body" ]
}

@test "rolls back previously posted chunks when a later chunk fails terminally" {
  local long_body
  long_body="$(printf 'section-%04d\n' $(seq 1 700))"

  export WEBHOOK_URL="https://discord.example/webhook"
  export RELEASE_NAME=""
  export RELEASE_TAG="v1.31.4"
  export RELEASE_URL="https://github.com/swt-labs/vibe-better-with-claude-code-vbw/releases/tag/v1.31.4"
  export RELEASE_BODY="$long_body"
  export FAKE_CURL_FAIL_ON_ATTEMPT=2
  export FAKE_CURL_FAIL_HTTP=404

  run bash "$SCRIPTS_DIR/post-discord-release.sh"
  [ "$status" -eq 1 ]
  [ "$(payload_count)" -eq 1 ]
  [ "$(delete_count)" -eq 1 ]

  run cat "$FAKE_CURL_DIR/delete-url-1.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "https://discord.example/webhook/messages/message-1" ]
}