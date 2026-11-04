# shellcheck shell=bash disable=SC2016,SC2154
key="$RUNNER_TEMP/t3-dev-test-key"
rm -f "$key" "$key.pub"
ssh-keygen -q -t ed25519 -N '' -f "$key"
ssh_opts=(-p 2222 -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10)

section "SSH off without GITHUB_USER"
start "$image" "GITHUB_USER="
sleep 15
check_host "sshd not listening" '! ssh-keyscan -T 5 -p 2222 127.0.0.1 2>/dev/null | grep -q ssh'
check_host "log explains SSH is off" 'docker logs t3-dev 2>&1 | grep -q "SSH je vypnuté"'

section "SSH with GITHUB_USER"
restart_with "$image" "GITHUB_USER=bzumik1"
wait_for "sshd listens with keys from GitHub" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519 && [ -s ~/.ssh/authorized_keys.github ]'
docker exec -u dev t3-dev bash -c "install -d -m700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" < "$key.pub"
check_host "login with an authorized key" "ssh ${ssh_opts[*]} dev@127.0.0.1 'id -u' | grep -qx 1000"
check_host "login shell has the full environment" "ssh ${ssh_opts[*]} dev@127.0.0.1 'docker info >/dev/null && java -version && node -v && command -v t3-dev'"
check_host "zsh is the login shell" "ssh ${ssh_opts[*]} dev@127.0.0.1 'echo \$SHELL' | grep -q zsh"
check_host "password login refused" "! ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no dev@127.0.0.1 true"
check_host "root login refused" "! ssh ${ssh_opts[*]} root@127.0.0.1 true"
check_host "unknown key refused" "k=\$(mktemp -u) && ssh-keygen -q -t ed25519 -N '' -f \$k && ! ssh -p 2222 -i \$k -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes dev@127.0.0.1 true"
check_host "local port forwarding works" "ssh ${ssh_opts[*]} -f -N -L 13773:127.0.0.1:2222 dev@127.0.0.1 && sleep 2 && ssh-keyscan -p 13773 127.0.0.1 2>/dev/null | grep -q ssh; s=\$?; pkill -f 'L 13773' ; exit \$s"
check_host "remote port forwarding refused" "! timeout 15 ssh ${ssh_opts[*]} -o ExitOnForwardFailure=yes -R 2299:127.0.0.1:22 dev@127.0.0.1 true"
check "host key persists in home" '[ -f ~/.ssh/host-keys/ssh_host_ed25519_key ]'
fingerprint=$(ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print $2}' | sort | head -1)
restart_with "$image" "GITHUB_USER=bzumik1"
wait_for "sshd back after recreate" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
check_host "host key unchanged after recreate" "[ \"\$(ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print \$2}' | sort | head -1)\" = '$fingerprint' ]"
