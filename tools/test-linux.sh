#!/usr/bin/env bash
# test-linux.sh: run the whole suite on Linux (bash 5, GNU coreutils) in a
# container shaped like CI's Linux job (Ubuntu 24.04, its jq 1.7), before a push. Maintainer tooling, never
# shipped. Needs Docker. The committed tree (HEAD) is copied into a path with a
# space and tested as a non-root user. Exit status is the suite's.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
image=vbw-test-linux
docker build -q -t "$image" - > /dev/null <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update -qq && apt-get install -y -qq bats shellcheck jq parallel git ca-certificates > /dev/null && rm -rf /var/lib/apt/lists/*
COPY --from=node:22-bookworm /usr/local/bin/node /usr/local/bin/node
USER ubuntu
RUN git config --global user.email ci@example.com && git config --global user.name CI && git config --global init.defaultBranch main
DOCKERFILE
git -C "$root" archive --format=tar HEAD | docker run --rm -i "$image" bash -c '
  mkdir -p "/home/ubuntu/src dir" && cd "/home/ubuntu/src dir" && tar -xf - &&
  git init -q && git add -A && git commit -q -m snapshot &&
  bash tools/test.sh'
