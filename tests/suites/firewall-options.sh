# shellcheck shell=bash disable=SC2016,SC2154
python3 -m http.server 18999 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server=$!
python3 -m http.server 18998 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server2=$!

start "$image"
wait_ready
gateway=$(dev "ip route | awk '/default/ {print \$3}'")

section "FIREWALL_ALLOW"
check "host blocked by default" "! curl -sS -o /dev/null --max-time 5 http://$gateway:18999/"
restart_with "$image" "FIREWALL_ALLOW=$gateway:18999/tcp"
wait_ready
check "allowed port on the host reachable" "curl -fsS -o /dev/null --max-time 10 http://$gateway:18999/"
check "other ports on the same host stay blocked" "! curl -sS -o /dev/null --max-time 5 http://$gateway:18998/"
check "rest of the LAN still blocked" '! curl -sS -o /dev/null --max-time 5 http://192.168.1.1/'
restart_with "$image" "FIREWALL_ALLOW=$gateway"
wait_ready
check_host "conntrack table was flushed when the rules loaded" 'docker logs t3-dev-net 2>&1 | grep -q "Starší spojení ukončena"'
check "a whole-host exception opens all its ports" "curl -fsS -o /dev/null --max-time 10 http://$gateway:18998/"

for bad in "0.0.0.0/0" "192.168.0.0/8" "192.168.0.0/16" "10.0.0.0/20" "*" "1.2.3.4;rm" "300.1.1.1" "010.0.0.1" "1.2.3.4:0" "1.2.3.4:65536" "1.2.3.4/33" "fd00::1" "198.18.0.1"; do
  restart_with "$image" "FIREWALL_ALLOW=$bad"
  sleep 15
  check_host "FIREWALL_ALLOW='$bad' is refused and t3-dev does not start" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev 2>/dev/null)" != true ] || ! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
  check_host "log explains the refused FIREWALL_ALLOW='$bad'" 'docker logs t3-dev-net 2>&1 | grep -q FIREWALL_ALLOW'
done

section "A LAN connection opened before the firewall is cut once it loads (F1)"
python3 -c '
import socket, threading
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("0.0.0.0", 18997)); s.listen()
def serve(c):
    while (d := c.recv(64)):
        c.sendall(d)
while True:
    threading.Thread(target=serve, args=(s.accept()[0],), daemon=True).start()
' &
echo_server=$!
restart_with "$image" "FIREWALL=off" "FIREWALL_EXPECTED=off"
wait_ready
check_host "log warns that the firewall is off" 'docker logs t3-dev-net 2>&1 | grep -q "firewall je vypnutý"'
check "host reachable with the firewall off" "curl -fsS -o /dev/null --max-time 10 http://$gateway:18999/"
dev "nohup bash -c 'exec 3<>/dev/tcp/$gateway/18997; while sleep 1; do echo ping >&3 2>/dev/null && read -t 3 l <&3 && echo OK >/tmp/conn || { echo BLOCKED >/tmp/conn; exit; }; done' >/dev/null 2>&1 &"
sleep 4
check "connection to the host is up before the firewall" 'grep -qx OK /tmp/conn'
docker exec -e FIREWALL_ALLOW= t3-dev-net /usr/local/libexec/t3-dev/firewall
sleep 8
check "the established connection is cut after the firewall loads" 'grep -qx BLOCKED /tmp/conn'
kill "$echo_server"

section "Fail closed without NET_ADMIN"
docker compose -f "$compose" down --timeout 60
write_compose "$image"
sed -i "s/      - NET_ADMIN/      - CHOWN/" "$compose"
docker compose -f "$compose" up -d --quiet-pull || true
sleep 15
check_host "t3-dev does not start without a working firewall" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev 2>/dev/null)" != true ] || ! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
check_host "log explains why" 'docker logs t3-dev-net 2>&1 | grep -q "nelze nastavit firewall"'

kill "$host_server" "$host_server2"
