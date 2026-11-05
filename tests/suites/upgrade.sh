# shellcheck shell=bash disable=SC2016,SC2154
previous=ghcr.io/bzumik1/t3-dev-container:latest

section "New image with an outdated compose.yml refuses to start and says why (U1)"
start "$image"
docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true
sudo rm -rf "$work"
write_compose "$image"
mutate 's/T3_DEV_COMPOSE: "[0-9]*"/T3_DEV_COMPOSE: "1"/'
docker compose -f "$compose" up -d --quiet-pull || true
sleep 20
check_host "t3-dev-net refuses with an outdated compose.yml" 'docker logs t3-dev-net 2>&1 | grep -q "compose.yml je zastaralý"'
check_host "t3-dev does not run services" '! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true

section "Each service checks the compose version itself (T11)"
sudo rm -rf "$work"
write_compose "$image"
mutate '/^  t3-dev:$/,$ s/T3_DEV_COMPOSE: "[0-9]*"/T3_DEV_COMPOSE: "1"/'
docker compose -f "$compose" up -d --quiet-pull || true
sleep 20
check_host "t3-dev itself refuses an outdated compose.yml" 'docker logs t3-dev 2>&1 | grep -q "compose.yml je zastaralý" && ! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true
write_compose "$image"
mutate '/^  t3-dev-init:$/,/^  t3-dev-net:$/ s/T3_DEV_COMPOSE: "[0-9]*"/T3_DEV_COMPOSE: "1"/'
check_host "t3-dev-init itself refuses an outdated compose.yml" '! docker compose -f "$compose" run --rm t3-dev-init 2>&1 | tee /dev/stderr | grep -q "Svazky připravené"'
docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true

section "Upgrade from the published image"
if ! docker pull -q "$previous" >/dev/null 2>&1; then
  skip "no published image yet, nothing to upgrade from"
  return 0
fi
previous_required=$(docker run --rm --entrypoint sed "$previous" -n 's/^required=\([0-9]*\).*/\1/p' /usr/local/libexec/t3-dev/compose-version 2>/dev/null)
[ -n "$previous_required" ] || previous_required=$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$previous" | sed -n 's/^T3_DEV_COMPOSE_REQUIRED=//p')
if [ "$previous_required" != "$(sed -n 's/^required=\([0-9]*\).*/\1/p' "$root/rootfs/usr/local/libexec/t3-dev/compose-version")" ]; then
  skip "published image needs another compose.yml version; upgrading means importing the new compose.yml"
  return 0
fi
start "$previous" "GITHUB_USER=bzumik1"
wait_ready
wait_for "agents installed by the previous image" 300 '[ -x ~/.local/bin/t3 ] && [ -x ~/.local/bin/claude ]'
check "state before upgrade" 'echo keep > /workspace/marker && docker pull -q alpine'

restart_with "$image" "GITHUB_USER=bzumik1"
wait_ready
check "workspace, agents and nested images survive the upgrade" '[ -f /workspace/marker ] && [ -x ~/.local/bin/t3 ] && docker image inspect alpine >/dev/null'
wait_for "t3 server answers after the upgrade" 240 'curl -fsS -o /dev/null http://127.0.0.1:3773/'
wait_for "sshd answers after the upgrade" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
