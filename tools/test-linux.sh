#!/usr/bin/env bash
# test-linux.sh: run the release run (tools/test.sh --release: the proof's run
# plus the timed speed checks) on Linux (bash 5, GNU coreutils) in a container
# shaped like one of CI's two Linux jobs, before a push. Maintainer tooling,
# never shipped. Needs Docker. The committed tree (HEAD) is copied into a path
# with a space and tested as a non-root user. Exit status is the command's.
#
# Three forms:
#   bash tools/test-linux.sh [--image IMAGE]              the release run
#   bash tools/test-linux.sh [--image IMAGE] --bench      only bash tools/bench-hooks.sh
#   bash tools/test-linux.sh [--image IMAGE] -- CMD...    CMD in place of the release run
#                                                         (each word kept as given)
# IMAGE names CI's two Linux jobs: ubuntu:24.04 (default; ubuntu-latest, jq 1.7.1)
# and ubuntu:26.04 (Ubuntu 26.04, jq 1.8.1). Any other image, or an unknown
# option, exits 2 with the usage before any docker call.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
usage='usage: tools/test-linux.sh [--image ubuntu:24.04|ubuntu:26.04] [--bench | -- COMMAND...]'
base=ubuntu:24.04
mode=release
while [ $# -gt 0 ]; do
  case "$1" in
    --image)
      [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
      base=$2; shift 2 ;;
    --bench) mode=bench; shift ;;
    --) shift; mode=cmd; break ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
case "$base" in
  ubuntu:24.04|ubuntu:26.04) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
case "$mode" in
  release) inner='bash tools/test.sh --release' ;;
  bench) inner='bash tools/bench-hooks.sh' ;;
  cmd)
    [ $# -gt 0 ] || { echo "$usage" >&2; exit 2; }
    inner=$(printf '%q ' "$@") ;;
esac
image=vbw-test-linux-${base//[^a-zA-Z0-9]/-}
docker build -q -t "$image" - > /dev/null <<DOCKERFILE
FROM $base
RUN apt-get update -qq && apt-get install -y -qq bats shellcheck jq parallel git ca-certificates > /dev/null && rm -rf /var/lib/apt/lists/*
COPY --from=node:22-bookworm /usr/local/bin/node /usr/local/bin/node
USER ubuntu
RUN git config --global user.email ci@example.com && git config --global user.name CI && git config --global init.defaultBranch main
DOCKERFILE
git -C "$root" archive --format=tar HEAD | docker run --rm -i "$image" bash -c '
  mkdir -p "/home/ubuntu/src dir" && cd "/home/ubuntu/src dir" && tar -xf - &&
  git init -q && git add -A && git commit -q -m snapshot &&
  '"$inner"
