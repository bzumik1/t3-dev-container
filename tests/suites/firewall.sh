# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

gateway=$(dev "ip route | awk '/default/ {print \$3}'")
python3 -m http.server 18999 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server=$!
sleep 2

section "Firewall (gateway $gateway)"
check_host "control: an ordinary container reaches the host" "docker run --rm --network t3-dev_default curlimages/curl -fsS -o /dev/null --max-time 10 http://$gateway:18999/"
check "internet over HTTPS" 'curl -fsS -o /dev/null --max-time 15 https://github.com'
check "DNS resolves" 'getent hosts github.com'
check "Docker host blocked" "! curl -sS -o /dev/null --max-time 5 http://$gateway:18999/"
check "home LAN 192.168/16 blocked" '! curl -sS -o /dev/null --max-time 5 http://192.168.1.1/'
check "10/8 blocked" '! curl -sS -o /dev/null --max-time 5 http://10.0.0.1/'
check "Tailscale 100.64/10 blocked" '! curl -sS -o /dev/null --max-time 5 http://100.100.100.100/'
check "link-local and cloud metadata blocked" '! curl -sS -o /dev/null --max-time 5 http://169.254.169.254/'
check "rules are rejects, not silent drops" 'out=$(curl -sS -o /dev/null --max-time 5 http://192.168.1.1/ 2>&1); echo "$out"; echo "$out" | grep -qiE "refused|unreachable|prohibited|No route|Couldn.t connect"'
check "IPv6 private ranges rejected when IPv6 is present" 'if ip -6 route 2>/dev/null | grep -q default; then ! curl -sS -o /dev/null --max-time 5 "http://[fd00::1]/"; fi'
check "nested container: internet reachable" 'docker run --rm alpine wget -q -O /dev/null -T 15 https://github.com'
check "nested container: Docker host blocked" "! docker run --rm alpine wget -q -O /dev/null -T 5 http://$gateway:18999/"
check "nested container: home LAN blocked" '! docker run --rm alpine wget -q -O /dev/null -T 5 http://192.168.1.1/'
check "nested host-network container: Docker host blocked" "! docker run --rm --network host alpine wget -q -O /dev/null -T 5 http://$gateway:18999/"

section "Inbound"
dev "nohup python3 -m http.server 18998 --bind 0.0.0.0 >/dev/null 2>&1 &"
sleep 2
ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" t3-dev-net)
check_host "inbound to other ports rejected ($ip:18998)" "! curl -sS -o /dev/null --max-time 5 http://$ip:18998/"
check "the same port answers inside the container" 'curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:18998/'
check_host "inbound SSH allowed" "ssh-keyscan -T 5 -p 2222 $ip 2>/dev/null | grep -q ssh || docker logs t3-dev 2>&1 | grep -q \"SSH je vypnuté\""

section "Firewall rules"
check_host "IPv4 rules present" 'docker exec t3-dev-net iptables-nft -S OUTPUT | grep -q "192.168.0.0/16.*REJECT"'

kill "$host_server"
