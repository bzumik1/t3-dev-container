# shellcheck shell=bash disable=SC2016,SC2154
start "$image"

section "Agents installed into home on first start"
wait_for "t3 installed" 300 '[ -x ~/.local/bin/t3 ]'
wait_for "codex installed" 300 '[ -x ~/.local/bin/codex ]'
wait_for "claude installed" 300 '[ -x ~/.local/bin/claude ]'
wait_for "opencode installed" 300 '[ -x ~/.opencode/bin/opencode ]'
check "agents run" 't3 --version && codex --version && claude --version && opencode --version'
# OpenCode 2 prints "opencode v2.2.5", OpenCode 1 prints "1.19.5".
opencode_recent='v=$(~/.opencode/bin/opencode --version); v=${v##* }; v=${v#v}; [ "$(printf "%s\n2.0.18\n" "$v" | sort -V | head -1)" = 2.0.18 ]'
wait_for "OpenCode is at least 2.0.18 (T3 needs it)" 300 "$opencode_recent"
for sh in bash zsh; do
  check_host "agents and the dev environment are on PATH in an interactive $sh from docker exec" "printf 'command -v t3 codex claude opencode >/dev/null && [ \"\$DOCKER_HOST\" = unix:///run/user/1000/docker.sock ] && [ \"\$NPM_CONFIG_IGNORE_SCRIPTS\" = true ] && echo ENV-OK\nexit\n' | docker exec -i t3-dev $sh -i 2>/dev/null | grep -qx ENV-OK"
done
check_host "agents are on PATH in t3-dev shell" "printf 'command -v t3 codex claude opencode >/dev/null && echo ENV-OK\nexit\n' | docker exec -i t3-dev t3-dev shell 2>/dev/null | grep -qx ENV-OK"

section "T3 server"
wait_for "t3 server answers on loopback" 180 'curl -fsS -o /dev/null http://127.0.0.1:3773/'
check "t3 server not exposed beyond loopback" '! ss -ltnH | awk "{print \$4}" | grep -E ":3773$" | grep -vq "^127.0.0.1:"'
check "only sshd listens on all interfaces" '[ -z "$(ss -ltnH | awk "{print \$4}" | grep -vE "^(127\.|\[::1\]|\[::ffff:127)" | grep -v ":2222$")" ]'
check_host "t3 port not published on the host" '! curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:3773/'
check "control: nested containers run" 'docker run --rm alpine true'
check "nested container cannot reach the t3 server via the host loopback" '! docker run --rm alpine wget -q -O /dev/null -T 5 http://10.0.2.2:3773/'
check "control: host-network nested containers run" 'docker run --rm --network host alpine true'
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

section "OpenCode 1 left by an older image"
check "control: OpenCode 1 replaces OpenCode 2" 'curl -fsSL --retry 3 https://opencode.ai/install | bash -s -- --no-modify-path >/dev/null 2>&1; ~/.opencode/bin/opencode --version | grep -q "^1\."'
check "install-agents moves it to OpenCode 2" "t3-dev install-agents && $opencode_recent"
check "update-agents runs the OpenCode 2 upgrade" 'out=$(t3-dev update-agents 2>&1); printf "%s\n" "$out"; printf "%s\n" "$out" | grep -q "Using method" && ! printf "%s\n" "$out" | grep -q "opencode upgrade selhal"'
