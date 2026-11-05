# shellcheck shell=bash disable=SC2016,SC2154
refuses() {
  local name="$1" pattern="$2"
  sleep 25
  check_host "$name: t3-dev refuses to run" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev 2>/dev/null)" != true ] || ! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
  check_host "$name: the log says why" "docker logs t3-dev 2>&1 | grep -qE '$pattern'"
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
refuses "Docker default seccomp instead of seccomp.json (UI dropped the option)" "seccomp\\.json\\) není"

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

bridge_mode() {
  write_compose "$image"
  mutate 's#^    network_mode: "service:t3-dev-net"#    network_mode: bridge\n    sysctls:\n      net.ipv6.conf.all.disable_ipv6: "1"\n      net.ipv6.conf.default.disable_ipv6: "1"#'
  mutate '/^      t3-dev-net:$/,/^        condition: service_healthy$/d'
}
wait_for_log() {
  local pattern="$1" end=$((SECONDS + 200))
  until docker logs t3-dev 2>&1 | grep -q "$pattern" || [ $SECONDS -ge $end ]; do sleep 5; done
}

section "network_mode dropped: only the namespace record can refuse it (T1)"
bridge_mode
docker compose -f "$compose" up -d --quiet-pull || true
wait_for_log "firewall t3-dev-net nechrání"
check_host "refused by the namespace check, not by another check" 'docker logs t3-dev 2>&1 | grep -q "firewall t3-dev-net nechrání" && ! docker logs t3-dev 2>&1 | grep -q "IPv6 není vypnuté" && ! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
docker compose -f "$compose" down --timeout 30 >/dev/null 2>&1 || true

section "A forged or stale marker is refused even when the probe is answered (N2)"
bridge_mode
sudo iptables -I DOCKER-USER -d 198.18.255.254 -j REJECT --reject-with icmp-admin-prohibited
docker compose -f "$compose" up -d --quiet-pull || true
sleep 8
pid=$(docker inspect -f "{{.State.Pid}}" t3-dev)
sudo sh -c "readlink /proc/$pid/ns/net > '$work/shared/firewall'"
sleep 30
check_host "t3-dev does not start services on a marker in the old inode format" '! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
sudo iptables -D DOCKER-USER -d 198.18.255.254 -j REJECT --reject-with icmp-admin-prohibited
docker compose -f "$compose" down --timeout 30 >/dev/null 2>&1 || true

section "Resource limits must be present (N5)"
write_compose "$image"
mutate '/^    pids_limit: 4096$/d'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "pids limit dropped" "pids_limit"
write_compose "$image"
mutate '/^    mem_limit: 8g$/d; /^    memswap_limit: 8g$/d'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "memory limit dropped" "mem_limit"
write_compose "$image"
mutate '/^    memswap_limit: 8g$/d'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "swap allowed (memswap_limit dropped)" "memswap_limit"
write_compose "$image"
mutate '/^    oom_score_adj: 800$/d'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "OOM priority dropped" "oom_score_adj"

write_compose "$image"
mutate '/:\/var\/lib\/t3-dev\/docker$/d'
docker compose -f "$compose" up -d --quiet-pull || true
refuses "nested Docker data volume missing" "není samostatný svazek"

section "Correct configuration starts"
start "$image"
wait_ready
check_host "log confirms the verified sandbox" 'docker logs t3-dev 2>&1 | grep -q "Sandbox ověřen"'
check_host "marker is boot id + namespace cookie and matches t3-dev" 'm=$(docker exec t3-dev-net cat /etc/t3-dev/shared/firewall); echo "$m"; [ "$m" = "$(docker exec t3-dev /usr/local/libexec/t3-dev/netns-id)" ] && echo "$m" | grep -qE "^[0-9a-f-]{36} [0-9]+$"'
