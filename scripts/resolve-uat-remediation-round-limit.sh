#!/usr/bin/env bash
set -u

# resolve-uat-remediation-round-limit.sh — normalize the UAT remediation round cap.
#
# Usage:
#   bash scripts/resolve-uat-remediation-round-limit.sh [path/to/config.json]
#     -> emits a positive integer when the cap is finite, or an empty string
#        when the effective behavior is unlimited.
#
#   bash scripts/resolve-uat-remediation-round-limit.sh --normalize-json <json-literal>
#     -> emits canonical JSON literal: false or positive integer.
#
#   bash scripts/resolve-uat-remediation-round-limit.sh --validate-input <value>
#     -> validates explicit /vbw:config input. Emits canonical JSON literal
#        false or positive integer. Exit 1 on invalid interactive input.
#
#   bash scripts/resolve-uat-remediation-round-limit.sh --read-top-level-literal <config-path> <key>
#     -> emits the exact top-level JSON literal for <key>, preserving oversized
#        integers exactly as written. Emits nothing when the top-level key is absent.
#
#   bash scripts/resolve-uat-remediation-round-limit.sh --next-round-decision <config-path> <current-round>
#     -> emits key=value lines describing whether round N+1 is allowed:
#        current_round, next_round, max_rounds, cap_reached, unlimited
#
# Semantics:
#   - new key max_uat_remediation_rounds wins over legacy max_remediation_rounds
#   - absent key => unlimited
#   - false / 0 => unlimited
#   - positive integer => exact finite cap
#   - malformed persisted values => unlimited

usage() {
  echo "Usage: resolve-uat-remediation-round-limit.sh [config-path] | --normalize-json <json-literal> | --validate-input <value> | --read-top-level-literal <config-path> <key> | --next-round-decision <config-path> <current-round>" >&2
}

canonicalize_decimal_string() {
  local raw="${1:-}"
  local stripped

  stripped=$(printf '%s' "$raw" | sed 's/^0*//')
  if [ -z "$stripped" ]; then
    echo "false"
  else
    echo "$stripped"
  fi
}

normalize_json_literal() {
  local raw="${1:-}"

  case "$raw" in
    ""|null|false|0)
      echo "false"
      return 0
      ;;
    true)
      echo "false"
      return 0
      ;;
  esac

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    canonicalize_decimal_string "$raw"
    return 0
  fi

  echo "false"
}

validate_input_value() {
  local raw="${1:-}"
  local normalized

  normalized=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')

  case "$normalized" in
    false)
      echo "false"
      return 0
      ;;
    0)
      echo "false"
      return 0
      ;;
  esac

  if [[ "$normalized" =~ ^[0-9]+$ ]]; then
    canonicalize_decimal_string "$normalized"
    return 0
  fi

  return 1
}

read_json_literal() {
  local config_path="$1"
  local key="$2"

  awk -v target="$key" '
    function skip_ws(   ch) {
      while (pos <= len) {
        ch = substr(txt, pos, 1)
        if (ch ~ /[ \t\r\n]/) {
          pos++
        } else {
          break
        }
      }
    }

    function parse_string(   ch, out) {
      if (substr(txt, pos, 1) != "\"") {
        parse_failed = 1
        return ""
      }

      pos++
      out = ""
      while (pos <= len) {
        ch = substr(txt, pos, 1)
        if (ch == "\\") {
          out = out ch substr(txt, pos + 1, 1)
          pos += 2
          continue
        }
        if (ch == "\"") {
          pos++
          return out
        }
        out = out ch
        pos++
      }

      parse_failed = 1
      return ""
    }

    function parse_value(   ch, start, nesting, in_string, escaped) {
      start = pos
      ch = substr(txt, pos, 1)

      if (ch == "\"") {
        pos++
        escaped = 0
        while (pos <= len) {
          ch = substr(txt, pos, 1)
          if (escaped) {
            escaped = 0
            pos++
            continue
          }
          if (ch == "\\") {
            escaped = 1
            pos++
            continue
          }
          if (ch == "\"") {
            pos++
            return substr(txt, start, pos - start)
          }
          pos++
        }
        parse_failed = 1
        return substr(txt, start, pos - start)
      }

      if (ch == "{" || ch == "[") {
        nesting = 1
        in_string = 0
        escaped = 0
        pos++
        while (pos <= len && nesting > 0) {
          ch = substr(txt, pos, 1)
          if (in_string) {
            if (escaped) {
              escaped = 0
            } else if (ch == "\\") {
              escaped = 1
            } else if (ch == "\"") {
              in_string = 0
            }
            pos++
            continue
          }

          if (ch == "\"") {
            in_string = 1
            pos++
            continue
          }

          if (ch == "{" || ch == "[") {
            nesting++
          } else if (ch == "}" || ch == "]") {
            nesting--
          }
          pos++
        }

        if (nesting != 0) {
          parse_failed = 1
        }
        return substr(txt, start, pos - start)
      }

      while (pos <= len) {
        ch = substr(txt, pos, 1)
        if (ch ~ /[ \t\r\n,}]/) {
          break
        }
        pos++
      }

      return substr(txt, start, pos - start)
    }

    {
      txt = txt $0 ORS
    }

    END {
      len = length(txt)
      pos = 1
      parse_failed = 0

      skip_ws()
      if (substr(txt, pos, 1) != "{") {
        exit 0
      }

      pos++
      while (pos <= len) {
        skip_ws()
        if (substr(txt, pos, 1) == "}") {
          exit 0
        }

        current_key = parse_string()
        if (parse_failed) {
          exit 0
        }

        skip_ws()
        if (substr(txt, pos, 1) != ":") {
          exit 0
        }

        pos++
        skip_ws()
        current_value = parse_value()
        if (parse_failed) {
          exit 0
        }

        if (current_key == target) {
          print current_value
          exit 0
        }

        skip_ws()
        if (substr(txt, pos, 1) == ",") {
          pos++
          continue
        }
        if (substr(txt, pos, 1) == "}") {
          exit 0
        }
        exit 0
      }
    }
  ' "$config_path"
}

decimal_gt() {
  local left="${1:-0}"
  local right="${2:-0}"
  local greater

  left=$(printf '%s' "$left" | sed 's/^0*//')
  right=$(printf '%s' "$right" | sed 's/^0*//')
  [ -z "$left" ] && left="0"
  [ -z "$right" ] && right="0"

  if [ "${#left}" -gt "${#right}" ]; then
    return 0
  fi

  if [ "${#left}" -lt "${#right}" ]; then
    return 1
  fi

  greater=$(printf '%s\n%s\n' "$left" "$right" | LC_ALL=C sort | tail -1)
  [ "$greater" = "$left" ] && [ "$left" != "$right" ]
}

resolve_from_config() {
  local config_path="${1:-.vbw-planning/config.json}"
  local raw canonical

  if ! command -v jq >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  if [ ! -f "$config_path" ] || ! jq empty "$config_path" >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  raw=$(read_json_literal "$config_path" "max_uat_remediation_rounds" || true)
  if [ -n "$raw" ]; then
    canonical=$(normalize_json_literal "$raw")
    if [ "$canonical" = "false" ]; then
      echo ""
    else
      echo "$canonical"
    fi
    return 0
  fi

  raw=$(read_json_literal "$config_path" "max_remediation_rounds" || true)
  if [ -n "$raw" ]; then
    canonical=$(normalize_json_literal "$raw")
    if [ "$canonical" = "false" ]; then
      echo ""
    else
      echo "$canonical"
    fi
    return 0
  fi

  echo ""
}

next_round_decision() {
  local config_path="$1"
  local current_round_raw="$2"
  local current_round next_round max_rounds cap_reached="false"

  if ! [[ "$current_round_raw" =~ ^[0-9]+$ ]]; then
    echo "Error: current round must be a numeric value" >&2
    return 1
  fi

  current_round=$(printf '%02d' "$((10#$current_round_raw))")
  next_round=$(printf '%02d' "$((10#$current_round_raw + 1))")
  max_rounds=$(resolve_from_config "$config_path")

  if [ -n "$max_rounds" ] && decimal_gt "$next_round" "$max_rounds"; then
    cap_reached="true"
  fi

  printf 'current_round=%s\n' "$current_round"
  printf 'next_round=%s\n' "$next_round"
  printf 'max_rounds=%s\n' "$max_rounds"
  printf 'cap_reached=%s\n' "$cap_reached"
  if [ -n "$max_rounds" ]; then
    echo "unlimited=false"
  else
    echo "unlimited=true"
  fi
}

case "${1:-}" in
  --normalize-json)
    shift
    normalize_json_literal "${1:-}"
    ;;
  --validate-input)
    shift
    validate_input_value "${1:-}" || exit 1
    ;;
  --read-top-level-literal)
    shift
    if [ "$#" -ne 2 ]; then
      usage
      exit 1
    fi
    read_json_literal "$1" "$2"
    ;;
  --next-round-decision)
    shift
    if [ "$#" -ne 2 ]; then
      usage
      exit 1
    fi
    next_round_decision "$1" "$2" || exit 1
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    resolve_from_config "${1:-.vbw-planning/config.json}"
    ;;
esac