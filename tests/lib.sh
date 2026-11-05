#!/bin/bash
# Shared helpers for the test suites. A suite starts the container from
# compose.yml with exactly its security options (paths moved to a temp
# directory, environment overridable) and checks it from the inside.
# Commands passed to check/wait_for run inside the container, so they are single-quoted on purpose.
# shellcheck disable=SC2016

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work="${RUNNER_TEMP:-/tmp}/t3-dev-test"
compose="$work/compose.yml"
failures=0

pass() { printf '\033[32m✓ %s\033[0m\n' "$*"; }
skips=0
skip() { printf '\033[33m- %s (skipped)\033[0m\n' "$*"; skips=$((skips + 1)); }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*"; failures=$((failures + 1)); }
section() { printf '\n== %s\n' "$*"; }
DEV_PATH=/home/dev/.local/bin:/home/dev/.opencode/bin:/home/dev/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
dev() { docker exec -u dev -e PATH="$DEV_PATH" -w /workspace t3-dev bash -c "$*"; }

check() {
  local name="$1"; shift
  local output
  if output=$(dev "$@" 2>&1); then pass "$name"; else fail "$name"; printf '%s\n' "$output" | tail -60; fi
}

check_host() {
  local name="$1"; shift
  local output
  if output=$(bash -c "$*" 2>&1); then pass "$name"; else fail "$name"; printf '%s\n' "$output" | tail -60; fi
}

wait_for() {
  local name="$1" seconds="$2"; shift 2
  local end=$((SECONDS + seconds))
  until dev "$@" >/dev/null 2>&1; do
    if [ $SECONDS -ge $end ]; then fail "$name (timeout ${seconds}s)"; return 1; fi
    sleep 3
  done
  pass "$name"
}

# write_compose <image> [KEY=VALUE ...]: compose.yml for the test, environment overrides applied.
write_compose() {
  local image="$1"; shift
  mkdir -p "$work"
  cp "$root/seccomp.json" "$work/seccomp.json"
  sed -e "s#/DATA/AppData/t3-dev#$work#g" \
      -e "s#ghcr.io/bzumik1/t3-dev-container:latest#$image#" \
      -e 's#SERVER_NAME: T3 Dev#SERVER_NAME: CI Test#' \
      -e 's#T3_CONNECT: "true"#T3_CONNECT: "false"#' \
      -e "s#cpus: 10#cpus: $(nproc)#" \
      "$root/compose.yml" > "$compose"
  local pair key value
  for pair in "$@"; do
    key="${pair%%=*}"; value="${pair#*=}"
    if grep -q "^      $key:" "$compose"; then
      sed -i "s#^      $key:.*#      $key: \"$value\"#" "$compose"
    else
      sed -i "s#^    environment:#    environment:\n      $key: \"$value\"#" "$compose"
    fi
  done
}

# mutate <sed expression>: edit the test compose.yml and fail loudly if nothing changed.
mutate() {
  cp "$compose" "$compose.orig"
  sed -i "$1" "$compose"
  if cmp -s "$compose" "$compose.orig"; then fail "compose mutation had no effect: $1"; fi
}

# start <image> [KEY=VALUE ...]: fresh volumes, container up.
start() {
  if [ -f "$compose" ]; then docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true; fi
  sudo rm -rf "$work"
  write_compose "$@"
  docker compose -f "$compose" up -d --quiet-pull || true
}

# restart_with <image> [KEY=VALUE ...]: recreate the container, keep the volumes.
restart_with() {
  docker compose -f "$compose" down --timeout 60
  write_compose "$@"
  docker compose -f "$compose" up -d --quiet-pull || true
}

# copy_in <host dir> <container dir>: copy as dev (root in t3-dev has no CHOWN).
copy_in() {
  dev "mkdir -p $2"
  tar -C "$1" -c . | docker exec -i -u dev t3-dev tar -C "$2" -x
}

wait_ready() {
  wait_for "rootless dockerd answers" 180 'docker info'
}

finish() {
  echo "::group::Container log"
  for c in t3-dev-init t3-dev-net t3-dev; do echo "--- $c"; docker logs "$c" 2>&1 | tail -300 || true; done
  echo "::endgroup::"
  docker compose -f "$compose" down --volumes --timeout 60 >/dev/null 2>&1 || true
  echo
  if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed"
    exit 1
  fi
  echo "All checks passed${skips:+ ($skips skipped)}"
}
