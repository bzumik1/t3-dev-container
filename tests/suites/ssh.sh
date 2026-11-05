# shellcheck shell=bash disable=SC2016,SC2154
key="$RUNNER_TEMP/t3-dev-test-key"
other="$RUNNER_TEMP/t3-dev-other-key"
rm -f "$key" "$key.pub" "$other" "$other.pub"
ssh-keygen -q -t ed25519 -N '' -f "$key"
ssh-keygen -q -t ed25519 -N '' -f "$other"
ssh_opts=(-p 2222 -i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10)
no_such_user=t3-dev-ci-no-such-user-0000

listener_on_2222_is_closed() {
  local label="$1" ip
  ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" t3-dev-net)
  dev "nohup python3 -m http.server 2222 --bind 0.0.0.0 >/dev/null 2>&1 &"
  sleep 2
  check "$label: control, a dev listener answers on 2222 inside" 'curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:2222/'
  check_host "$label: it gets no inbound connections" "[ -n '$ip' ] && ! curl -sS -o /dev/null --max-time 5 http://$ip:2222/"
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
ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" t3-dev-net)
check_host "control: SSH answers on the container address the closed-port checks use" "[ -n '$ip' ] && ssh-keyscan -T 5 -p 2222 $ip 2>/dev/null | grep -q ssh-ed25519"
check "keys from GitHub and the extra key are installed read-only" '[ "$(grep -c . /etc/t3-dev/shared/authorized_keys)" -ge 2 ] && [ "$(stat -c %u /etc/t3-dev/shared/authorized_keys)" = 0 ] && ! touch /etc/t3-dev/shared/authorized_keys 2>/dev/null'
check "the keys file has no duplicates" '[ -z "$(sort /etc/t3-dev/shared/authorized_keys | uniq -d)" ]'
check "sshd reads keys only from the read-only file" '/usr/sbin/sshd -T -f /etc/t3-dev/sshd_config 2>/dev/null | grep -i "^authorizedkeysfile" | grep -qx "authorizedkeysfile /etc/t3-dev/shared/authorized_keys"'
check "sshd logs verbosely (key fingerprints)" '/usr/sbin/sshd -T -f /etc/t3-dev/sshd_config 2>/dev/null | grep -qx "loglevel VERBOSE"'
check_host "login with the configured key" "ssh ${ssh_opts[*]} dev@127.0.0.1 'id -u' | grep -qx 1000"
check_host "login shell has the full environment" "ssh ${ssh_opts[*]} dev@127.0.0.1 'docker info >/dev/null && java -version && node -v && command -v t3-dev'"
check_host "SSH sessions run with no_new_privs" "ssh ${ssh_opts[*]} dev@127.0.0.1 'grep -q \"^NoNewPrivs:.*1\" /proc/self/status'"
put_file /tmp/ptrace.py <<'PY'
import ctypes, errno, os, sys
libc = ctypes.CDLL(None, use_errno=True)
pid = int(sys.argv[1])
if libc.ptrace(16, pid, 0, 0) == 0:
    os.waitpid(pid, 0)
    libc.ptrace(17, pid, 0, 0)
    sys.exit(0)
e = ctypes.get_errno()
sys.exit(2 if e == errno.EPERM else 1)
PY
sup=$(dev "pgrep -x supervisord")
check_host "an SSH session cannot ptrace supervisord" "ssh ${ssh_opts[*]} dev@127.0.0.1 'python3 -I /tmp/ptrace.py $sup'; [ \$? = 2 ]"
check_host "SSH sessions live in their own user namespace" "[ \"\$(ssh ${ssh_opts[*]} dev@127.0.0.1 readlink /proc/self/ns/user)\" != \"\$(docker exec t3-dev readlink /proc/1/ns/user)\" ]"
check_host "zsh is the login shell" "ssh ${ssh_opts[*]} dev@127.0.0.1 'echo \$SHELL' | grep -q zsh"
docker exec -i t3-dev bash -c "install -d -m700 ~/.ssh && cat >> ~/.ssh/authorized_keys" < "$other.pub"
check_host "a key added by a dev process does not work" "! ssh -p 2222 -i $other -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 dev@127.0.0.1 true"
sudo chmod g+w "$work/shared/authorized_keys"
dev 'supervisorctl -c /etc/t3-dev/supervisord.conf restart sshd' >/dev/null 2>&1 || true
sleep 5
check_host "sshd refuses a group-writable keys file (StrictModes replacement)" '! ssh-keyscan -T 5 -p 2222 127.0.0.1 2>/dev/null | grep -q ssh && docker logs t3-dev 2>&1 | grep -q "zapisovatelný pro skupinu"'
sudo chmod 0644 "$work/shared/authorized_keys"
dev 'supervisorctl -c /etc/t3-dev/supervisord.conf restart sshd' >/dev/null 2>&1 || true
wait_for "control: sshd back with a 0644 keys file" 60 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
check_host "password login refused" "! ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no dev@127.0.0.1 true"
check_host "root login refused" "! ssh ${ssh_opts[*]} root@127.0.0.1 true"
check_host "local port forwarding to the container works" "ssh ${ssh_opts[*]} -o ExitOnForwardFailure=yes -L 13773:127.0.0.1:2222 dev@127.0.0.1 'sleep 10' & sleep 4; ssh-keyscan -T 5 -p 13773 127.0.0.1 2>&1 | grep ssh-ed25519"
check_host "control: stdio forwarding to the container localhost works" "ssh ${ssh_opts[*]} -W 127.0.0.1:2222 dev@127.0.0.1 </dev/null 2>/dev/null | head -c 7 | grep -qx SSH-2.0"
check_host "forwarding to an internet host is refused by PermitOpen (not by the firewall)" "ssh ${ssh_opts[*]} -W github.com:443 dev@127.0.0.1 </dev/null 2>&1 | grep -qi 'administratively prohibited'"
check_host "remote port forwarding refused" "! timeout 15 ssh ${ssh_opts[*]} -o ExitOnForwardFailure=yes -R 2299:127.0.0.1:22 dev@127.0.0.1 true"

section "Host key persists"
check "host key lives in home" '[ -f ~/.ssh/host-keys/ssh_host_ed25519_key ]'
fingerprint=$(ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print $2}' | sort | head -1)
restart_with "$image" "GITHUB_USER=bzumik1" "SSH_AUTHORIZED_KEYS=$(cat "$key.pub")"
wait_for "sshd back after recreate" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
check_host "host key unchanged after recreate" "[ \"\$(ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print \$2}' | sort | head -1)\" = '$fingerprint' ]"
check "no duplicate keys after a restart" '[ -z "$(sort /etc/t3-dev/shared/authorized_keys | uniq -d)" ]'

section "Revocation takes effect while sshd keeps running (K1, T7)"
restart_with "$image" "GITHUB_USER=$no_such_user" "SSH_AUTHORIZED_KEYS=$(cat "$other.pub")"
wait_for "sshd listens with the kept key" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
check_host "control: the kept key logs in" "ssh -p 2222 -i $other -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 dev@127.0.0.1 true"
check_host "the dropped key no longer logs in" "! ssh ${ssh_opts[*]} dev@127.0.0.1 true"
check "only the kept key is installed" '[ "$(grep -c . /etc/t3-dev/shared/authorized_keys)" = 1 ]'

section "GitHub unreachable: cached keys only for the same user and at most 7 days (K1, T8)"
offline() {
  docker compose -f "$compose" down --timeout 60 >/dev/null 2>&1 || true
  write_compose "$image" "$@"
  mutate 's#^    dns:$#    extra_hosts:\n      - "github.com:198.18.0.1"\n    dns:#'
  docker compose -f "$compose" up -d --quiet-pull || true
  wait_ready
}
start "$image" "GITHUB_USER=bzumik1"
wait_ready
check "control: keys from GitHub are installed" '[ -s /etc/t3-dev/shared/authorized_keys ]'
offline "GITHUB_USER=bzumik1"
check_host "same user: the cached keys are used" 'docker logs t3-dev-net 2>&1 | grep -q "GitHub je nedostupný (HTTP 000), používám klíče bzumik1"'
check "same user: keys installed while GitHub is unreachable" '[ -s /etc/t3-dev/shared/authorized_keys ]'
sudo sed -i "1s/fetched=[0-9]*/fetched=$(( $(date +%s) - 8 * 86400 ))/" "$work/shared/authorized_keys.github"
offline "GITHUB_USER=bzumik1"
check "cache older than 7 days is not used" '[ ! -s /etc/t3-dev/shared/authorized_keys ]'
start "$image" "GITHUB_USER=bzumik1"
wait_ready
offline "GITHUB_USER=octocat"
check "the cache of another user is not used" '[ ! -s /etc/t3-dev/shared/authorized_keys ]'
