#!/bin/bash
# Commands passed to check/wait_for run inside the container, so they are single-quoted on purpose.
# shellcheck disable=SC2016
# Starts the image from compose.yml with exactly its security options (paths moved
# to a temp directory) and checks the container from the inside.
# Usage: tests/ci.sh <image>
set -euo pipefail

image="${1:?Usage: tests/ci.sh <image>}"
root=$(cd "$(dirname "$0")/.." && pwd)
work="${RUNNER_TEMP:-/tmp}/t3-dev-ci"
compose="$work/compose.yml"

sudo rm -rf "$work"
mkdir -p "$work"
cp "$root/seccomp.json" "$work/seccomp.json"
sed -e "s#/DATA/AppData/t3-dev#$work#g" \
    -e "s#ghcr.io/bzumik1/t3-dev-container:latest#$image#" \
    -e 's#SERVER_NAME: T3 Dev#SERVER_NAME: CI Test#' \
    -e 's#GITHUB_USER: ""#GITHUB_USER: bzumik1#' \
    -e 's#T3_CONNECT: "true"#T3_CONNECT: "false"#' \
    -e "s#cpus: 10#cpus: $(nproc)#" \
    "$root/compose.yml" > "$compose"

failures=0
pass() { printf '\033[32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*"; failures=$((failures + 1)); }
dev() { docker exec -u dev -w /workspace t3-dev bash -c "$*"; }
check() {
  local name="$1"; shift
  local output
  if output=$(dev "$@" 2>&1); then pass "$name"; else fail "$name"; printf '%s\n' "$output" | tail -40; fi
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

cleanup() {
  echo "::group::Container log"
  docker logs t3-dev 2>&1 | tail -300 || true
  echo "::endgroup::"
  docker compose -f "$compose" down --volumes --timeout 60 || true
}
trap cleanup EXIT

docker compose -f "$compose" up -d
sleep 5

echo "== Isolation"
check "services run as uid 1000" '[ "$(ps -o uid= -p "$(pgrep -o supervisord)" | tr -d " ")" = 1000 ]'
check "bounding set holds only SETUID and SETGID" 'grep -q "^CapBnd:\s*00000000000000c0$" /proc/$(pgrep -o supervisord)/status'
check "no effective capabilities" 'grep -q "^CapEff:\s*0000000000000000$" /proc/$(pgrep -o supervisord)/status'
check "no setuid or setgid binaries" '[ -z "$(find / -xdev -type f -perm /6000 2>/dev/null)" ]'
check "newuidmap/newgidmap carry only file capabilities" 'getcap /usr/bin/newuidmap | grep -q "cap_setuid=ep" && getcap /usr/bin/newgidmap | grep -q "cap_setgid=ep"'
check "no sudo" '! command -v sudo'
check "server name from SERVER_NAME" 'grep -qx "PRETTY_HOSTNAME=\"CI Test\"" /etc/machine-info'

echo "== Docker inside"
wait_for "rootless dockerd answers" 120 'docker info'
check "docker info reports rootless" 'docker info --format "{{.SecurityOptions}}" | grep -q rootless'
check "docker run hello-world" 'docker run --rm hello-world'
check "published port reachable on localhost" 'docker run -d --name web -p 18080:80 nginx:alpine && for i in $(seq 30); do curl -fsS localhost:18080 >/dev/null && break; sleep 1; done; curl -fsS localhost:18080 | grep -q nginx; s=$?; docker rm -f web; exit $s'
check "docker compose and buildx" 'docker compose version && docker buildx version'
check "docker build" 'd=$(mktemp -d) && printf "FROM alpine\nRUN echo ok > /ok\n" > $d/Dockerfile && docker build -q -t t3-dev-build-test $d'

echo "== Firewall"
gateway=$(dev "ip route | awk '/default/ {print \$3}'")
python3 -m http.server 18999 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server=$!
sleep 2
if docker run --rm --network t3-dev_default curlimages/curl -fsS -o /dev/null --max-time 10 "http://$gateway:18999/"; then
  pass "control: an ordinary container reaches the host at $gateway:18999"
else
  fail "control: an ordinary container reaches the host at $gateway:18999"
fi
check "internet reachable" 'curl -fsS -o /dev/null --max-time 15 https://github.com'
check "Docker host ($gateway) blocked" "! curl -sS -o /dev/null --max-time 5 http://$gateway:18999/"
check "private network blocked" '! curl -sS -o /dev/null --max-time 5 http://192.168.1.1/'
check "nested container: internet reachable" 'docker run --rm alpine wget -q -O /dev/null -T 15 https://github.com'
check "nested container: Docker host blocked" "! docker run --rm alpine wget -q -O /dev/null -T 5 http://$gateway:18999/"
kill "$host_server"

echo "== SSH"
wait_for "sshd listens on 2222 with GitHub keys" 60 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519 && [ -s ~/.ssh/authorized_keys.github ]'

echo "== Tools"
check "java 25" 'java -version 2>&1 | grep -q "\"25"'
check "node 24" 'node -v | grep -q "^v24\."'
check "npm >= 11.10 with supply-chain settings" 'npm -v && [ "$(npm config get min-release-age)" = 3 ] && [ "$(npm config get ignore-scripts)" = true ]'
check "npm global installs go to ~/.local" '[ "$(npm config get prefix)" = "$HOME/.local" ]'
check "pnpm with minimum release age" 'pnpm -v && [ "$(cd /tmp && pnpm config get minimumReleaseAge)" = 4320 ]'
check "git, gh, mise" 'git --version && gh --version && mise --version'
check "shell tools" 'for t in jq yq rg fd fzf tmux vim htop zsh starship rsync unzip wget; do command -v $t >/dev/null || { echo "missing $t"; exit 1; }; done'
check "mise installs a runtime without root" 'mise exec python@3.13 -- python --version'

echo "== Testcontainers (Java, like nfnn)"
docker cp "$root/tests/testcontainers-java" t3-dev:/workspace/testcontainers-java
docker exec -u 0 t3-dev chown -R 1000:1000 /workspace/testcontainers-java
check "Gradle test with PostgreSQL in Testcontainers" '
  url=$(curl -fsSL https://services.gradle.org/versions/current | jq -r .downloadUrl) &&
  curl -fsSL "$url" -o /tmp/gradle.zip && unzip -q /tmp/gradle.zip -d /tmp/gradle &&
  cd /workspace/testcontainers-java && /tmp/gradle/gradle-*/bin/gradle --no-daemon test'

echo "== Agents (installed into home on first start)"
wait_for "t3 installed" 300 '[ -x ~/.local/bin/t3 ]'
wait_for "codex installed" 300 '[ -x ~/.local/bin/codex ]'
wait_for "claude installed" 300 '[ -x ~/.local/bin/claude ]'
wait_for "opencode installed" 300 '[ -x ~/.opencode/bin/opencode ]'
wait_for "t3 server listens on loopback" 120 'curl -fsS -o /dev/null http://127.0.0.1:3773/'
check "t3 server not exposed beyond loopback" '! ss -ltn | grep -q "0.0.0.0:3773\|\[::\]:3773\|\*:3773"'
check "t3-dev status" 't3-dev status'
end=$((SECONDS + 180))
until [ "$(docker inspect -f '{{.State.Health.Status}}' t3-dev)" = healthy ]; do
  if [ $SECONDS -ge $end ]; then fail "Docker healthcheck healthy"; break; fi
  sleep 5
done
[ "$(docker inspect -f '{{.State.Health.Status}}' t3-dev)" = healthy ] && pass "Docker healthcheck healthy"

echo "== Restart keeps working"
docker restart -t 60 t3-dev >/dev/null
wait_for "dockerd back after restart" 120 'docker info'
check "home survived restart" '[ -x ~/.local/bin/t3 ] && [ -s ~/.ssh/authorized_keys.github ]'

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All checks passed"
