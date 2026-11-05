# shellcheck shell=bash disable=SC2016,SC2154
key="$RUNNER_TEMP/t3-dev-test-key"
other="$RUNNER_TEMP/t3-dev-other-key"
rm -f "$key" "$key.pub" "$other" "$other.pub"
ssh-keygen -q -t ed25519 -N '' -f "$key"
ssh-keygen -q -t ed25519 -N '' -f "$other"
ssh_opts=(-p 2222 -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10)
no_such_user=t3-dev-ci-no-such-user-0000

listener_on_2222_is_closed() {
  local label="$1" ip
  ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" t3-dev-net)
  dev "nohup python3 -m http.server 2222 --bind 0.0.0.0 >/dev/null 2>&1 &"
  sleep 2
  check "$label: control, a dev listener answers on 2222 inside" 'curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:2222/'
  check_host "$label: it gets no inbound connections" "! curl -sS -o /dev/null --max-time 5 http://$ip:2222/"
  dev 'pkill -f "http.server 2222"' || true
}

section "SSH off by default: nothing comes in on 2222"
start "$image"
wait_ready
check_host "sshd not listening" '! ssh-keyscan -T 5 -p 2222 127.0.0.1 2>/dev/null | grep -q ssh'
check_host "log explains SSH is off" 'docker logs t3-dev 2>&1 | grep -q "SSH je vypnuté"'
listener_on_2222_is_closed "SSH off"

section "GITHUB_USER without keys does not open 2222 (K2)"
restart_with "$image" "GITHUB_USER=$no_such_user"
wait_ready
check_host "log says GitHub has no keys for the user" "docker logs t3-dev-net 2>&1 | grep -q 'GitHub nezná uživatele $no_such_user'"
listener_on_2222_is_closed "GITHUB_USER without keys"

section "SSH with GITHUB_USER and SSH_AUTHORIZED_KEYS (set on t3-dev-net)"
restart_with "$image" "GITHUB_USER=bzumik1" "SSH_AUTHORIZED_KEYS=$(cat "$key.pub")"
wait_for "sshd listens" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
check "keys from GitHub and the extra key are installed read-only" '[ "$(grep -c . /etc/t3-dev/shared/authorized_keys)" -ge 2 ] && [ "$(stat -c %u /etc/t3-dev/shared/authorized_keys)" = 0 ] && ! touch /etc/t3-dev/shared/authorized_keys 2>/dev/null'
check "the keys file has no duplicates" '[ -z "$(sort /etc/t3-dev/shared/authorized_keys | uniq -d)" ]'
check "sshd reads keys only from the read-only file" '/usr/sbin/sshd -T -f /etc/t3-dev/sshd_config 2>/dev/null | grep -i "^authorizedkeysfile" | grep -qx "authorizedkeysfile /etc/t3-dev/shared/authorized_keys"'
check "sshd logs verbosely (key fingerprints)" '/usr/sbin/sshd -T -f /etc/t3-dev/sshd_config 2>/dev/null | grep -qx "loglevel VERBOSE"'
check_host "login with the configured key" "ssh ${ssh_opts[*]} dev@127.0.0.1 'id -u' | grep -qx 1000"
check_host "login shell has the full environment" "ssh ${ssh_opts[*]} dev@127.0.0.1 'docker info >/dev/null && java -version && node -v && command -v t3-dev'"
check_host "SSH sessions run with no_new_privs" "ssh ${ssh_opts[*]} dev@127.0.0.1 'grep -q \"^NoNewPrivs:.*1\" /proc/self/status'"
check_host "zsh is the login shell" "ssh ${ssh_opts[*]} dev@127.0.0.1 'echo \$SHELL' | grep -q zsh"
docker exec -i t3-dev bash -c "install -d -m700 ~/.ssh && cat >> ~/.ssh/authorized_keys" < "$other.pub"
check_host "a key added by a dev process does not work" "! ssh -p 2222 -i $other -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 dev@127.0.0.1 true"
check_host "password login refused" "! ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no dev@127.0.0.1 true"
check_host "root login refused" "! ssh ${ssh_opts[*]} root@127.0.0.1 true"
check_host "local port forwarding to the container works" "ssh ${ssh_opts[*]} -o ExitOnForwardFailure=yes -L 13773:127.0.0.1:2222 dev@127.0.0.1 'sleep 10' & sleep 4; ssh-keyscan -T 5 -p 13773 127.0.0.1 2>&1 | grep ssh-ed25519"
gateway=$(dev "ip route | awk '/default/ {print \$3}'")
python3 -m http.server 18999 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server=$!
sleep 2
check_host "local port forwarding into the LAN is refused" "ssh ${ssh_opts[*]} -L 18996:$gateway:18999 dev@127.0.0.1 'sleep 10' & sleep 4; ! curl -fsS -o /dev/null --max-time 4 http://127.0.0.1:18996/"
kill "$host_server"
check_host "remote port forwarding refused" "! timeout 15 ssh ${ssh_opts[*]} -o ExitOnForwardFailure=yes -R 2299:127.0.0.1:22 dev@127.0.0.1 true"

section "Host key persists"
check "host key lives in home" '[ -f ~/.ssh/host-keys/ssh_host_ed25519_key ]'
fingerprint=$(ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print $2}' | sort | head -1)
restart_with "$image" "GITHUB_USER=bzumik1" "SSH_AUTHORIZED_KEYS=$(cat "$key.pub")"
wait_for "sshd back after recreate" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
check_host "host key unchanged after recreate" "[ \"\$(ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print \$2}' | sort | head -1)\" = '$fingerprint' ]"
check "no duplicate keys after a restart" '[ -z "$(sort /etc/t3-dev/shared/authorized_keys | uniq -d)" ]'

section "Revocation takes effect (K1)"
restart_with "$image" "GITHUB_USER=$no_such_user" "SSH_AUTHORIZED_KEYS="
wait_ready
sleep 5
check "keys file is empty after switching to a user without keys and dropping the extra key" '[ ! -s /etc/t3-dev/shared/authorized_keys ]'
check_host "the old key no longer logs in" "! ssh ${ssh_opts[*]} dev@127.0.0.1 true"
