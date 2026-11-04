# shellcheck shell=bash disable=SC2016,SC2154
python3 -m http.server 18999 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server=$!

start "$image"
wait_ready
gateway=$(dev "ip route | awk '/default/ {print \$3}'")

section "FIREWALL_ALLOW"
check "host blocked by default" "! curl -sS -o /dev/null --max-time 5 http://$gateway:18999/"
restart_with "$image" "FIREWALL_ALLOW=$gateway"
wait_ready
check "host reachable once allowed" "curl -fsS -o /dev/null --max-time 10 http://$gateway:18999/"
check "rest of LAN still blocked" '! curl -sS -o /dev/null --max-time 5 http://192.168.1.1/'

section "FIREWALL=off"
restart_with "$image" "FIREWALL=off"
wait_ready
check "host reachable with the firewall off" "curl -fsS -o /dev/null --max-time 10 http://$gateway:18999/"
check_host "log warns that the firewall is off" 'docker logs t3-dev 2>&1 | grep -q "firewall je vypnutý"'

section "Fail closed without NET_ADMIN"
docker compose -f "$compose" down --timeout 60
sed -i '/      - NET_ADMIN/d' "$compose"
docker compose -f "$compose" up -d --quiet-pull
sleep 10
check_host "container refuses to start without a working firewall" '[ "$(docker inspect -f "{{.State.Running}} {{.State.Restarting}}" t3-dev)" != "true false" ] || ! docker exec -u dev t3-dev pgrep supervisord'
check_host "log explains why" 'docker logs t3-dev 2>&1 | grep -q "nelze nastavit firewall"'

kill "$host_server"
