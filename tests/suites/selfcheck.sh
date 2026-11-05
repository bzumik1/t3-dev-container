# shellcheck shell=bash disable=SC2016,SC2154
refuses() {
  local name="$1" pattern="$2"
  sleep 25
  check_host "$name: t3-dev refuses to run" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev 2>/dev/null)" != true ] || ! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
  check_host "$name: the log says why" "docker logs t3-dev 2>&1 | grep -q '$pattern'"
  docker compose -f "$compose" down --timeout 30 >/dev/null 2>&1 || true
}

section "Sandbox self-check in the entrypoint"
if [ -f "$compose" ]; then docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true; fi
sudo rm -rf "$work"
write_compose "$image"
mutate 's/^      - SETGID$/      - SETGID\n      - DAC_OVERRIDE/'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "extra capability" "CapBnd"

write_compose "$image"
mutate "s#^      - seccomp=.*#      - seccomp=unconfined#"
docker compose -f "$compose" up -d --quiet-pull || true
refuses "seccomp off" "seccomp filtr chybí"

write_compose "$image"
mutate "/^      - seccomp=/d"
docker compose -f "$compose" up -d --quiet-pull || true
refuses "Docker default seccomp instead of seccomp.json (UI dropped the option)" "seccomp.json) není"

write_compose "$image"
mutate '/net.ipv6.conf.all.disable_ipv6/d; /net.ipv6.conf.default.disable_ipv6/d; /^    sysctls:$/d'
docker compose -f "$compose" up -d --quiet-pull || true
sleep 25
if docker exec t3-dev-net cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null | grep -qx 0; then
  refuses "IPv6 left on" "IPv6"
else
  skip "IPv6 left on: Docker kept IPv6 disabled on this runner"
  docker compose -f "$compose" down --timeout 30 >/dev/null 2>&1 || true
fi

write_compose "$image"
mutate 's#^    user: "1000:1000"#    user: "0:0"#'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "running as root" "uživatel dev"

write_compose "$image"
mutate 's#^    network_mode: "service:t3-dev-net"#    network_mode: bridge#'
mutate '/^      t3-dev-net:$/,/^        condition: service_healthy$/d'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "network_mode dropped (no shared firewall)" "firewall t3-dev-net nechrání"

write_compose "$image"
mutate '/^      - \/DATA.*\/var\/lib\/t3-dev\/docker$/d'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "nested Docker data volume missing" "není samostatný svazek"

section "Correct configuration starts"
start "$image"
wait_ready
check_host "log confirms the verified sandbox" 'docker logs t3-dev 2>&1 | grep -q "Sandbox ověřen"'
