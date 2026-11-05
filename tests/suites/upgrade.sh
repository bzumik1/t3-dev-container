# shellcheck shell=bash disable=SC2016,SC2154
previous=ghcr.io/bzumik1/t3-dev-container:latest

section "Upgrade from the published image"
if ! docker pull -q "$previous" >/dev/null 2>&1; then
  pass "no published image yet, nothing to upgrade from"
  return 0
fi
if [ "$(docker image inspect -f "{{.Config.User}}" "$previous")" != 1000:1000 ]; then
  pass "published image predates the rootless layout, no upgrade path to test yet"
  return 0
fi
start "$previous" "GITHUB_USER=bzumik1"
wait_ready
wait_for "agents installed by the previous image" 300 '[ -x ~/.local/bin/t3 ] && [ -x ~/.local/bin/claude ]'
check "state before upgrade" 'echo keep > /workspace/marker && docker pull -q alpine'

restart_with "$image" "GITHUB_USER=bzumik1"
wait_ready
check "workspace, agents and nested images survive the upgrade" '[ -f /workspace/marker ] && [ -x ~/.local/bin/t3 ] && docker image inspect alpine >/dev/null'
wait_for "t3 server answers after the upgrade" 240 'curl -fsS -o /dev/null http://127.0.0.1:3773/'
wait_for "sshd answers after the upgrade" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
