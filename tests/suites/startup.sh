# shellcheck shell=bash disable=SC2016,SC2154
python3 -m http.server 18999 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server=$!

section "t3-dev waits for the firewall (host or Docker daemon restart, where depends_on does not apply)"
if [ -f "$compose" ]; then docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true; fi
sudo rm -rf "$work"
write_compose "$image"
python3 - "$compose" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
text = text.replace('entrypoint: ["/usr/bin/tini", "--", "/usr/local/libexec/t3-dev/net"]',
                    'entrypoint: ["/usr/bin/tini", "--", "/bin/sh", "-c", "sleep 40; exec /usr/local/libexec/t3-dev/net"]')
text = text.replace('test: ["CMD", "/usr/bin/test", "-e", "/run/t3-dev-net-ready"]', 'test: ["CMD", "true"]')
open(path, "w").write(text)
assert "sleep 40" in text and 'test: ["CMD", "true"]' in text, "compose mutation had no effect"
PY
sudo mkdir -p "$work/home/.local/bin"
printf '#!/bin/sh\necho RAN >> /tmp/canary\ngw=$(/usr/sbin/ip route | /usr/bin/awk "/default/ {print \\$3}")\n/usr/bin/timeout 3 /bin/bash -c "exec 3<>/dev/tcp/$gw/18999" 2>/dev/null && echo REACHED >> /tmp/canary\nexec /usr/bin/git "$@"\n' | sudo tee "$work/home/.local/bin/git" >/dev/null
sudo chmod +x "$work/home/.local/bin/git"
sudo chown -R 1000:1000 "$work/home"
# Something on the path answers the firewall probe with "host unreachable" (F2):
# t3-dev must still wait, because only the namespace record proves the firewall.
sudo iptables -I DOCKER-USER -d 198.18.255.254 -j REJECT --reject-with icmp-admin-prohibited
docker compose -f "$compose" up -d --quiet-pull || true
check_host "control: the REJECT rule is in DOCKER-USER" 'sudo iptables -C DOCKER-USER -d 198.18.255.254 -j REJECT --reject-with icmp-admin-prohibited'
check_host "control: an ordinary container gets host unreachable for the probe address" "docker run --rm --network t3-dev_default --entrypoint python3 $image -I -S -c 'import errno, socket, sys; s = socket.socket(); s.settimeout(3); sys.exit(0 if s.connect_ex((\"198.18.255.254\", 9)) == errno.EHOSTUNREACH else 1)'"
sleep 15
check_host "no service starts while the firewall is missing" '! docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1'
check_host "services are held back: no verified-sandbox message yet" '! docker logs t3-dev 2>&1 | grep -q "Sandbox ověřen"'
sleep 40
wait_ready
check "services start once the firewall is active" 'pgrep -x supervisord'
wait_for "agent wrapper ran (canary had its chance)" 120 '[ -x ~/.local/bin/t3 ] || pgrep -f t3-dev/t3'
check "the canary ran" 'grep -q RAN /tmp/canary'
check "the canary in ~/.local/bin never reached the host" '! grep -q REACHED /tmp/canary'
sudo iptables -D DOCKER-USER -d 198.18.255.254 -j REJECT --reject-with icmp-admin-prohibited

section "Control: the same canary reaches the host when the firewall is off"
restart_with "$image" "FIREWALL=off" "FIREWALL_EXPECTED=off"
wait_ready
dev 'rm -f /tmp/canary; "$HOME"/.local/bin/git --version >/dev/null'
check "control: canary reached the host without the firewall" 'grep -q REACHED /tmp/canary'

section "Docker daemon restart"
start "$image"
wait_ready
gateway=$(dev "ip route | awk '/default/ {print \$3}'")
sudo systemctl restart docker
end=$((SECONDS + 180))
until [ "$(docker inspect -f '{{.State.Running}}' t3-dev 2>/dev/null)" = true ] && docker exec t3-dev pgrep -x supervisord >/dev/null 2>&1; do
  [ $SECONDS -ge $end ] && break
  sleep 5
done
check_host "t3-dev-net and t3-dev came back after the daemon restart" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev-net)" = true ] && [ "$(docker inspect -f "{{.State.Running}}" t3-dev)" = true ]'
wait_ready
check_host "control: an ordinary container still reaches the host after the restart" "docker run --rm --network t3-dev_default curlimages/curl -fsS -o /dev/null --max-time 10 http://$gateway:18999/"
check "Docker host still blocked after the daemon restart" "! curl -sS -o /dev/null --max-time 5 http://$gateway:18999/"
check "internet still reachable after the daemon restart" 'curl -fsS -o /dev/null --max-time 15 https://github.com'

kill "$host_server"

section "T3 Connect: a successful sign-in starts the server (no endless sign-in loop)"
docker compose -f "$compose" down --volumes --timeout 30 >/dev/null 2>&1 || true
sudo rm -rf "$work"
write_compose "$image" "T3_CONNECT=true"
sudo mkdir -p "$work/home/.local/bin"
sudo tee "$work/home/.local/bin/t3" >/dev/null <<'SH'
#!/bin/sh
case "$1 $2" in
  "connect status") if [ -e /tmp/fake-t3-linked ]; then echo "Authorization: stored credential"; else echo "Authorization: none"; fi ;;
  "connect link") read -r answer; echo "answer=$answer" >> /tmp/fake-t3-link; touch /tmp/fake-t3-linked; echo "Authorized"; exit 0 ;;
  serve*) echo started > /tmp/fake-t3-served; exec sleep infinity ;;
  *) exit 0 ;;
esac
SH
sudo chmod +x "$work/home/.local/bin/t3"
sudo chown -R 1000:1000 "$work/home"
docker compose -f "$compose" up -d --quiet-pull || true
wait_for "the server starts right after a successful sign-in" 420 '[ -e /tmp/fake-t3-served ]'
check "the sign-in ran exactly once and answered the prompt with y" '[ "$(cat /tmp/fake-t3-link)" = "answer=y" ]'
check_host "no retry message in the log" '! docker logs t3-dev 2>&1 | grep -q "přihlášení se nedokončilo"'
