#!/usr/bin/env bats
# R233 (T204, L1): tools/test-linux.sh, the maintainer's Linux run in a container shaped
# like CI's Linux jobs, takes the image to shape it after (--image, default ubuntu:24.04,
# the ubuntu-latest of CI with jq 1.7.1; ubuntu:26.04 with jq 1.8.1 accepted) and what to
# run inside: the release run by default, only the hook bench with --bench, or a command
# of its own after --, so one guard call can be measured step by step in either image.
# Docker is stood in for by a script that records the Dockerfile it was given and the
# command it was asked to run, and runs nothing.

load helper

setup() {
  vbw_setup
  mkdir -p "$TEST_ROOT/bin"
  cat > "$TEST_ROOT/bin/docker" <<'SH'
#!/bin/sh
# A docker that records: the Dockerfile of a build, the arguments of a run; it runs nothing.
log="$FAKE_DOCKER_LOG"
case "$1" in
  build) cat > "$log.dockerfile"; echo sha256:fake ;;
  run) cat > /dev/null; printf '%s\n' "$@" > "$log.run" ;;
  *) printf '%s\n' "$@" >> "$log.other" ;;
esac
SH
  chmod +x "$TEST_ROOT/bin/docker"
  export FAKE_DOCKER_LOG="$TEST_ROOT/docker"
  SCRIPT="$REPO_ROOT/tools/test-linux.sh"
}
teardown() { vbw_teardown; }

linux() { PATH="$TEST_ROOT/bin:$PATH" bash "$SCRIPT" "$@"; }

@test "R233: without arguments the container is ubuntu:24.04 and runs the release run, as before" {
  run linux
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^FROM ubuntu:24.04$' "$FAKE_DOCKER_LOG.dockerfile" || { cat "$FAKE_DOCKER_LOG.dockerfile"; false; }
  grep -q 'bash tools/test.sh --release' "$FAKE_DOCKER_LOG.run" || { cat "$FAKE_DOCKER_LOG.run"; false; }
}

@test "R233: --image ubuntu:26.04 shapes the container after that image and --bench runs only the hook bench" {
  run linux --image ubuntu:26.04 --bench
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^FROM ubuntu:26.04$' "$FAKE_DOCKER_LOG.dockerfile" || { cat "$FAKE_DOCKER_LOG.dockerfile"; false; }
  grep -q 'bash tools/bench-hooks.sh' "$FAKE_DOCKER_LOG.run" || { cat "$FAKE_DOCKER_LOG.run"; false; }
  ! grep -q 'test.sh --release' "$FAKE_DOCKER_LOG.run" || { echo "the release run still runs with --bench"; cat "$FAKE_DOCKER_LOG.run"; false; }
}

@test "R233: a command after -- runs inside the container in place of the release run, its words kept" {
  run linux --image ubuntu:26.04 -- env VBW_BENCH_STEPS=1 VBW_BENCH_RUNS=20 bash tools/bench-hooks.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q 'VBW_BENCH_STEPS=1' "$FAKE_DOCKER_LOG.run" && grep -q 'VBW_BENCH_RUNS=20' "$FAKE_DOCKER_LOG.run" && grep -q 'bash tools/bench-hooks.sh' "$FAKE_DOCKER_LOG.run" \
    || { cat "$FAKE_DOCKER_LOG.run"; false; }
  ! grep -q 'test.sh --release' "$FAKE_DOCKER_LOG.run" || { cat "$FAKE_DOCKER_LOG.run"; false; }
  # The image name is the one asked for, so two images never share one tag.
  grep -q '^FROM ubuntu:26.04$' "$FAKE_DOCKER_LOG.dockerfile"
}

@test "R233: an unknown option or an image the script does not know exits 2 with the usage and builds nothing" {
  run linux --imag ubuntu:26.04
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *usage* ]] || { echo "$output"; false; }
  [ ! -e "$FAKE_DOCKER_LOG.dockerfile" ] || { echo "a build ran"; false; }
  run linux --image debian:12
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [ ! -e "$FAKE_DOCKER_LOG.dockerfile" ] || { echo "a build ran"; false; }
}
