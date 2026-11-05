# shellcheck shell=bash disable=SC2016,SC2154
key="$RUNNER_TEMP/t3-dev-mounts-key"
other="$RUNNER_TEMP/t3-dev-mounts-other"
rm -f "$key" "$key.pub" "$other" "$other.pub"
ssh-keygen -q -t ed25519 -N '' -f "$key"
ssh-keygen -q -t ed25519 -N '' -f "$other"

section "No mount target lies inside another volume (V1)"
start "$image" "SSH_AUTHORIZED_KEYS=$(cat "$key.pub")"
wait_ready
check_host "t3-dev mount targets are not nested" 'targets=$(docker inspect -f "{{range .Mounts}}{{println .Destination}}{{end}}" t3-dev | sort -u); echo "$targets"; for d in $targets; do for o in $targets; do [ "$d" != "$o" ] && case "$d/" in "$o"/*) echo "nested: $d in $o"; exit 1;; esac; done; done; true'
check_host "t3-dev-init does not mount the shared keys volume" '! docker inspect -f "{{range .Mounts}}{{.Destination}} {{end}}" t3-dev-init | grep -q /etc/t3-dev/shared'
check "nested Docker data are a separate mount outside home" 'findmnt -rn --mountpoint /var/lib/t3-dev/docker >/dev/null && docker info -f "{{.DockerRootDir}}" | grep -qx /var/lib/t3-dev/docker'

section "A symlink planted by dev does not redirect any mount after a restart"
dev 'mkdir -p ~/.local/share && rm -rf ~/.local/share/docker && ln -s /etc/t3-dev/shared ~/.local/share/docker && ln -sfn /etc ~/.local/share/etc-link'
dev 'kill -TERM 1' || true
sleep 40
wait_ready
check "shared keys volume still root-owned and read-only" '[ "$(stat -c %u /etc/t3-dev/shared)" = 0 ] && findmnt -n -o OPTIONS --mountpoint /etc/t3-dev/shared | grep -qw ro'
check "dev still cannot write the keys file" '! sh -c "cat >> /etc/t3-dev/shared/authorized_keys" </dev/null 2>/dev/null'
docker exec -i t3-dev sh -c 'cat >> /etc/t3-dev/shared/authorized_keys' < "$other.pub" 2>/dev/null || true
check_host "a key dev tried to plant does not log in" "! ssh -p 2222 -i $other -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 dev@127.0.0.1 true"
check_host "control: the configured key still logs in" "ssh -p 2222 -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 dev@127.0.0.1 true"

check_host "no setuid or setgid files anywhere in the volumes" '[ -z "$(sudo find "$work/home" "$work/workspace" "$work/shared" -perm /6000 -print -quit)" ]'
