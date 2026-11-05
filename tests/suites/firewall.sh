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
install_rejected_probe
check "home LAN 192.168/16 rejected by the firewall (not a timeout)" 'python3 -I /tmp/rejected.py 192.168.1.1 80'
check "10/8 rejected by the firewall (not a timeout)" 'python3 -I /tmp/rejected.py 10.0.0.1 80'
check "172.16/12 (other Docker networks) rejected by the firewall (not a timeout)" 'python3 -I /tmp/rejected.py 172.30.0.1 80'
check "Tailscale 100.64/10 rejected by the firewall (not a timeout)" 'python3 -I /tmp/rejected.py 100.100.100.100 80'
check "link-local and cloud metadata rejected by the firewall (not a timeout)" 'python3 -I /tmp/rejected.py 169.254.169.254 80'
check "control: a public address is not rejected" 'ip=$(getent ahostsv4 github.com | awk "NR==1 {print \$1}"); echo "$ip"; ! python3 -I /tmp/rejected.py "$ip" 443'
check "Docker host blocked" "! curl -sS -o /dev/null --max-time 5 http://$gateway:18999/"
if dev "ip -6 route 2>/dev/null | grep -q default"; then
  check "IPv6 private ranges rejected" '! curl -sS -o /dev/null --max-time 5 "http://[fd00::1]/"'
else
  skip "IPv6 private ranges: the namespace has no IPv6 (disabled by design)"
fi
check "nested container: internet reachable" 'docker run --rm alpine wget -q -O /dev/null -T 15 https://github.com'
check "nested container: Docker host blocked" "! docker run --rm alpine wget -q -O /dev/null -T 5 http://$gateway:18999/"
# slirp4netns hides the local REJECT from the nested container (it just times out),
# so read the packet counter of the 192.168.0.0/16 rule in the shared namespace.
lan_rejects() { docker exec t3-dev-net iptables-nft -L OUTPUT -n -v -x | awk '$9 == "192.168.0.0/16" && $3 == "REJECT" {print $1}'; }
before=$(lan_rejects)
dev 'docker run --rm alpine wget -q -O /dev/null -T 5 http://192.168.1.1/' || true
after=$(lan_rejects)
check_host "nested container: home LAN rejected by the firewall rule (counter $before -> $after)" "[ -n '$before' ] && [ -n '$after' ] && [ '$after' -gt '$before' ]"
check "control: a host-network nested container reaches the internet" 'docker run --rm --network host alpine wget -q -O /dev/null -T 15 https://github.com'
check "nested host-network container: Docker host blocked" "! docker run --rm --network host alpine wget -q -O /dev/null -T 5 http://$gateway:18999/"

section "Inbound"
dev "nohup python3 -m http.server 18998 --bind 0.0.0.0 >/dev/null 2>&1 &"
sleep 2
ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" t3-dev-net)
check_host "inbound to other ports rejected ($ip:18998)" "[ -n '$ip' ] && ! curl -sS -o /dev/null --max-time 5 http://$ip:18998/"
check "the same port answers inside the container" 'curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:18998/'

section "Firewall rules"
check_host "IPv4 rules present" 'docker exec t3-dev-net iptables-nft -S OUTPUT | grep -q "192.168.0.0/16.*REJECT"'

kill "$host_server"

section "Rule order and DNS (F1, N3)"
check_host "the general ESTABLISHED accept comes after every reject" 'r=$(docker exec t3-dev-net iptables-nft -S OUTPUT); echo "$r"; est=$(echo "$r" | grep -n -- "-j ACCEPT" | grep -v -- "--ctdir REPLY" | grep -v -- "-o lo" | head -1 | cut -d: -f1); rej=$(echo "$r" | grep -n -- "-j REJECT" | tail -1 | cut -d: -f1); [ -n "$est" ] && [ -n "$rej" ] && [ "$est" -gt "$rej" ]'
check_host "only replies are accepted before the blocklist" 'docker exec t3-dev-net iptables-nft -S OUTPUT | grep -q -- "--ctstate RELATED,ESTABLISHED --ctdir REPLY -j ACCEPT"'
check_host "t3-dev-net uses explicit public DNS" 'v=$(docker inspect -f "{{json .HostConfig.Dns}}" t3-dev-net); echo "$v"; [ "$v" = "[\"9.9.9.9\",\"149.112.112.112\"]" ]'
check "direct DNS query to the LAN is rejected by the firewall (UDP)" 'python3 -I /tmp/rejected.py 192.168.1.1 53 udp'
