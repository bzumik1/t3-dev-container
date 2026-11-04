# shellcheck shell=bash disable=SC2016,SC2154
start "$image"

section "Agents installed into home on first start"
wait_for "t3 installed" 300 '[ -x ~/.local/bin/t3 ]'
wait_for "codex installed" 300 '[ -x ~/.local/bin/codex ]'
wait_for "claude installed" 300 '[ -x ~/.local/bin/claude ]'
wait_for "opencode installed" 300 '[ -x ~/.opencode/bin/opencode ]'
check "agents run" 't3 --version && codex --version && claude --version && opencode --version'

section "T3 server"
wait_for "t3 server answers on loopback" 180 'curl -fsS -o /dev/null http://127.0.0.1:3773/'
check "t3 server not exposed beyond loopback" '! ss -ltnH | awk "{print \$4}" | grep -E ":3773$" | grep -vq "^127.0.0.1:"'
check "only sshd listens on all interfaces" '[ -z "$(ss -ltnH | awk "{print \$4}" | grep -vE "^(127\.|\[::1\]|\[::ffff:127)" | grep -v ":2222$")" ]'
check_host "t3 port not published on the host" '! curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:3773/'
check "nested container cannot reach the t3 server via the host loopback" '! docker run --rm alpine wget -q -O /dev/null -T 5 http://10.0.2.2:3773/'
check "host-network nested container cannot reach the t3 server" '! docker run --rm --network host alpine wget -q -O /dev/null -T 5 http://127.0.0.1:3773/'
check "t3-dev status" 't3-dev status'

section "Healthcheck"
end=$((SECONDS + 240))
until [ "$(docker inspect -f '{{.State.Health.Status}}' t3-dev)" = healthy ]; do
  if [ $SECONDS -ge $end ]; then break; fi
  sleep 5
done
check_host "Docker healthcheck healthy" '[ "$(docker inspect -f "{{.State.Health.Status}}" t3-dev)" = healthy ]'
check "supervisor restarts a crashed t3" 'pkill -f "[t]3 serve" ; sleep 20; for i in $(seq 60); do curl -fsS -o /dev/null http://127.0.0.1:3773/ && exit 0; sleep 3; done; exit 1'
