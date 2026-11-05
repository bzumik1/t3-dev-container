# shellcheck shell=bash disable=SC2016,SC2154
start "$image" "GITHUB_USER=bzumik1"
wait_ready
wait_for "t3 installed" 300 '[ -x ~/.local/bin/t3 ]'
check "prepare state" 'echo keep > /workspace/marker && echo keep > ~/marker && docker pull -q alpine && docker volume create keepvol'

section "docker restart"
docker restart -t 60 t3-dev >/dev/null
wait_ready
check "home, workspace and nested images survive a restart" '[ -f /workspace/marker ] && [ -f ~/marker ] && docker image inspect alpine >/dev/null && docker volume inspect keepvol >/dev/null'
check "services are back after the restart" 'pgrep -x sshd && { pgrep -f "t3 serve" || pgrep -f t3-dev/t3; }'

section "Agent instructions are managed and refreshed, the owner's own text stays"
for f in .codex/AGENTS.md .claude/CLAUDE.md .config/opencode/AGENTS.md; do
  check "managed block at the top of ~/$f" "head -1 ~/$f | grep -q '^<!-- t3-dev:begin' && grep -q 'Never merge, approve or push' ~/$f"
done
dev 'printf "\nMy own note for Claude\n" >> ~/.claude/CLAUDE.md && sed -i "s/^You run inside/STALE You run inside/" ~/.claude/CLAUDE.md'

section "recreate (new container, same volumes)"
restart_with "$image" "GITHUB_USER=bzumik1" "SERVER_NAME=Renamed"
wait_ready
check "state survives a recreate" '[ -f /workspace/marker ] && [ -f ~/marker ] && [ -x ~/.local/bin/t3 ] && docker image inspect alpine >/dev/null'
check "new SERVER_NAME applied" 'grep -qx "PRETTY_HOSTNAME=\"Renamed\"" /etc/machine-info'
wait_for "the managed block was refreshed after a recreate" 120 '! grep -q "^STALE" ~/.claude/CLAUDE.md && [ "$(grep -c "t3-dev:begin" ~/.claude/CLAUDE.md)" = 1 ]'
check "the owner's own text in the instructions file is kept" 'grep -qx "My own note for Claude" ~/.claude/CLAUDE.md'
check "user edits to .zshrc are kept" 'echo "# mine" >> ~/.zshrc' 
restart_with "$image" "GITHUB_USER=bzumik1"
wait_ready
check "user edits to .zshrc still there" 'grep -q "# mine" ~/.zshrc'

section "volume ownership repair"
docker compose -f "$compose" down --timeout 60
sudo chown root:root "$work/home" "$work/workspace"
docker compose -f "$compose" up -d
wait_ready
check "root-owned volume directories are handed back to dev" '[ "$(stat -c %u ~ /workspace | sort -u)" = 1000 ]'

section "Healthcheck needs both dockerd and t3 (N10)"
check_host "control: healthy before" 'for i in $(seq 40); do [ "$(docker inspect -f "{{.State.Health.Status}}" t3-dev)" = healthy ] && exit 0; sleep 5; done; exit 1'
dev 'supervisorctl -c /etc/t3-dev/supervisord.conf stop t3' >/dev/null
check_host "unhealthy once t3 is stopped" 'for i in $(seq 40); do [ "$(docker inspect -f "{{.State.Health.Status}}" t3-dev)" = unhealthy ] && exit 0; sleep 5; done; exit 1'
dev 'supervisorctl -c /etc/t3-dev/supervisord.conf start t3' >/dev/null
