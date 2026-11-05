# shellcheck shell=bash disable=SC2016,SC2154
refuses() {
  local name="$1" pattern="$2"
  sleep 25
  check_host "$name: t3-dev refuses to run" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev 2>/dev/null)" != true ] || ! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
  check_host "$name: the log says why" "docker logs t3-dev 2>&1 | grep -q '$pattern'"
  docker compose -f "$compose" down --timeout 30 >/dev/null 2>&1 || true
}

section "Sandbox self-check in the entrypoint"
sudo rm -rf "$work"
write_compose "$image"
sed -i 's/^      - SETGID$/      - SETGID\n      - DAC_OVERRIDE/' "$compose"
docker compose -f "$compose" up -d --quiet-pull || true
refuses "extra capability" "CapBnd"

write_compose "$image"
sed -i "s#^      - seccomp=.*#      - seccomp=unconfined#" "$compose"
docker compose -f "$compose" up -d --quiet-pull || true
refuses "seccomp profile missing" "seccomp"

write_compose "$image"
sed -i '/net.ipv6.conf.all.disable_ipv6/d; /net.ipv6.conf.default.disable_ipv6/d; /^    sysctls:$/d' "$compose"
docker compose -f "$compose" up -d --quiet-pull || true
sleep 25
if docker exec t3-dev-net cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null | grep -qx 0; then
  refuses "IPv6 left on" "IPv6"
else
  pass "IPv6 left on: runner has no IPv6, nothing to check"
  docker compose -f "$compose" down --timeout 30 >/dev/null 2>&1 || true
fi

write_compose "$image"
sed -i 's#^    user: "1000:1000"#    user: "0:0"#' "$compose"
docker compose -f "$compose" up -d --quiet-pull || true
refuses "running as root" "uživatel dev"

section "Correct configuration starts"
start "$image"
wait_ready
check_host "log confirms the verified sandbox" 'docker logs t3-dev 2>&1 | grep -q "Sandbox ověřen"'
