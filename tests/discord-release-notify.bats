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

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--data|--data-raw|--data-binary)
      payload="$2"
      shift 2
      ;;
    -H|--header)
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

count=0
if [ -f "$FAKE_CURL_DIR/count" ]; then
  count=$(cat "$FAKE_CURL_DIR/count")
fi
count=$((count + 1))

printf '%s' "$count" > "$FAKE_CURL_DIR/count"
printf '%s' "$payload" > "$FAKE_CURL_DIR/payload-$count.json"
printf '%s' "$url" > "$FAKE_CURL_DIR/url-$count.txt"
printf '{"id":"message-%s"}\n' "$count"
EOF
  chmod +x bin/curl

  export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

payload_count() {
  if [ -f "$FAKE_CURL_DIR/count" ]; then
    cat "$FAKE_CURL_DIR/count"
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