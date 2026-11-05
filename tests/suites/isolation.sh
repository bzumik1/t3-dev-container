# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Privileges"
check "every process in the container runs as uid 1000" '[ "$(ps -eo uid= | tr -d " " | sort -u)" = 1000 ]'
check "PID 1 is tini as dev" '[ "$(ps -o comm= -p 1)" = tini ] && [ "$(ps -o uid= -p 1 | tr -d " ")" = 1000 ]'
check "bounding set holds only SETUID and SETGID (initial user namespace)" 'init=$(readlink /proc/1/ns/user); for p in $(pgrep .); do [ "$(readlink /proc/$p/ns/user 2>/dev/null)" = "$init" ] || continue; b=$(awk "/^CapBnd/ {print \$2}" /proc/$p/status 2>/dev/null) || continue; [ -z "$b" ] || [ "$b" = 00000000000000c0 ] || { echo "pid $p: $b"; exit 1; }; done'
check "no process in the initial user namespace has capabilities" 'init=$(readlink /proc/1/ns/user); for p in $(pgrep .); do [ "$(readlink /proc/$p/ns/user 2>/dev/null)" = "$init" ] || continue; for f in CapEff CapPrm CapAmb CapInh; do v=$(awk "/^$f/ {print \$2}" /proc/$p/status 2>/dev/null) || continue; [ -z "$v" ] || [ "$v" = 0000000000000000 ] || { echo "pid $p $f=$v $(tr "\\0" " " </proc/$p/cmdline)"; exit 1; }; done; done'
check "sshd and t3 services run with no_new_privs (cannot use newuidmap file caps)" 'for svc in sshd t3 maintenance; do p=$(supervisorctl -c /etc/t3-dev/supervisord.conf pid $svc); [ "$(awk "/^NoNewPrivs/ {print \$2}" /proc/$p/status)" = 1 ] || { echo "$svc ($p) without no_new_privs"; exit 1; }; done'
check "no setuid or setgid binaries" '[ -z "$(find / -xdev -type f -perm /6000 2>/dev/null)" ]'
check "only newuidmap/newgidmap carry file capabilities" '[ "$(getcap -r /usr /bin /sbin /opt 2>/dev/null | sort | awk "{print \$1}" | tr "\n" " ")" = "/usr/bin/newgidmap /usr/bin/newuidmap " ]'
check "no sudo" '! command -v sudo'
check_host "root account has no usable password" 'docker exec -u 0 t3-dev awk -F: "\$1==\"root\" {print \$2}" /etc/shadow | grep -qE "^[*!]"'

section "Read-only system for dev"
check "dev cannot write /etc" '! touch /etc/t3-dev-test 2>/dev/null'
check "dev cannot write /usr" '! touch /usr/local/bin/t3-dev-test 2>/dev/null'
check "dev cannot change the firewall" '! iptables -F OUTPUT 2>/dev/null && ! iptables-nft -F OUTPUT 2>/dev/null'
check "dev cannot read the container root home" '! ls /root 2>/dev/null'
check "dev cannot regain capabilities via setpriv" '! setpriv --inh-caps=+net_admin --ambient-caps=+net_admin true 2>/dev/null'

section "Container configuration"
check_host "image and t3-dev default to uid 1000 (docker exec, healthcheck)" '[ "$(docker exec t3-dev id -u)" = 1000 ] && [ "$(docker inspect -f "{{.Config.User}}" t3-dev)" = 1000:1000 ]'
check_host "t3-dev adds only SETUID and SETGID" 'v=$(docker inspect -f "{{range .HostConfig.CapAdd}}{{println .}}{{end}}" t3-dev | sort | tr "\n" " " | sed "s/^ *//"); echo "$v"; [ "$v" = "CAP_SETGID CAP_SETUID " ]'
check_host "t3-dev-net adds only NET_ADMIN, read-only, no-new-privileges" 'v=$(docker inspect -f "{{range .HostConfig.CapAdd}}{{.}} {{end}}{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.SecurityOpt}}" t3-dev-net); echo "$v"; [ "$v" = "CAP_NET_ADMIN true [no-new-privileges:true]" ]'
check_host "t3-dev-init adds only CHOWN, has no network and finished" 'v=$(docker inspect -f "{{range .HostConfig.CapAdd}}{{.}} {{end}}{{.HostConfig.NetworkMode}} {{.State.Status}} {{.State.ExitCode}}" t3-dev-init); echo "$v"; [ "$v" = "CAP_CHOWN none exited 0" ]'
check_host "t3-dev-net only holds the namespace (tini + sleep)" 'v=$(docker top t3-dev-net -o pid,comm | tail -n +2 | awk "{print \$2}" | sort | tr "\n" " "); echo "$v"; [ "$v" = "sleep tini " ]'
check_host "not privileged" '[ "$(docker inspect -f "{{.HostConfig.Privileged}}" t3-dev)" = false ]'
check_host "no host Docker socket mounted" '! docker inspect -f "{{range .Mounts}}{{.Source}} {{end}}" t3-dev | grep -q docker.sock'
check_host "memory, CPU and pids limits applied" '[ "$(docker inspect -f "{{.HostConfig.Memory}} {{.HostConfig.PidsLimit}}" t3-dev)" = "8589934592 4096" ]'
check "server name from SERVER_NAME" 'grep -qx "PRETTY_HOSTNAME=\"CI Test\"" /etc/machine-info'
check "time zone applied" '[ "$(date +%Z)" = CET ] || [ "$(date +%Z)" = CEST ]'

section "Root contexts never run code from dev's home (X2, P1)"
check_host "image has no PATH or HOME pointing into /home/dev" '! docker image inspect -f "{{json .Config.Env}}" "$(docker inspect -f "{{.Image}}" t3-dev)" | grep -qE "\"(PATH|HOME)=[^\"]*/home/dev"'
check_host "root exec gets HOME=/root, dev gets /home/dev" '[ "$(docker exec -u 0 t3-dev printenv HOME)" = /root ] && [ "$(docker exec t3-dev printenv HOME)" = /home/dev ]'
check_host "t3-dev-net has no HOME in the home volume" '! docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" t3-dev-net | grep -q "^HOME=/home/dev"'
dev 'mkdir -p ~/.local/bin && for c in cat sed grep git ls id awk printf; do printf "#!/bin/sh\ntouch /tmp/canary-\$(/usr/bin/id -u)-%s\nexec /usr/bin/%s \"\$@\"\n" $c $c > ~/.local/bin/$c; chmod +x ~/.local/bin/$c; done; echo "touch /tmp/canary-\$(/usr/bin/id -u)-bashrc" >> ~/.bashrc'
docker exec -u 0 t3-dev /usr/local/bin/t3-dev help >/dev/null 2>&1 || true
docker exec -u 0 t3-dev /usr/local/bin/t3-dev bogus >/dev/null 2>&1 || true
docker exec -u 0 -i t3-dev bash -i -c true </dev/null >/dev/null 2>&1 || true
docker exec -u 0 t3-dev git --version >/dev/null 2>&1 || true
docker exec -u 0 -e HOME=/home/dev -e PATH="$DEV_PATH" -i t3-dev bash -i -c true </dev/null >/dev/null 2>&1 || true
check "no root context ran code from dev's home" '! ls /tmp/canary-0-* 2>/dev/null'
check "dockerd and supervisord run with a system PATH" 'for p in $(pgrep -x dockerd) $(pgrep -x supervisord); do tr "\0" "\n" < /proc/$p/environ | grep -qx "PATH=/usr/sbin:/usr/bin:/sbin:/bin" || { echo "pid $p"; tr "\0" "\n" < /proc/$p/environ | grep ^PATH; exit 1; }; done'
check "supervisord does not start dockerd-rootless.sh from ~/.local/bin" '
  printf "#!/bin/sh\ntouch /tmp/canary-dockerd\nexec /usr/bin/dockerd-rootless.sh \"\$@\"\n" > ~/.local/bin/dockerd-rootless.sh && chmod +x ~/.local/bin/dockerd-rootless.sh &&
  supervisorctl -c /etc/t3-dev/supervisord.conf restart dockerd >/dev/null;
  for i in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 2; done; rm -f ~/.local/bin/dockerd-rootless.sh; [ ! -e /tmp/canary-dockerd ]'
dev 'for c in cat sed grep git ls id awk printf; do rm -f ~/.local/bin/$c; done; sed -i "/canary/d" ~/.bashrc'

section "Healthcheck runs with no_new_privs and a system PATH (P2)"
check_host "healthcheck goes through setpriv --no-new-privs" 'docker inspect -f "{{json .Config.Healthcheck.Test}}" t3-dev | grep -q "no-new-privs"'
dev 'printf "#!/bin/sh\n/usr/bin/grep -q \"^NoNewPrivs:[[:space:]]*0\" /proc/self/status && echo \$PPID >> /tmp/canary-nonnp\necho ran >> /tmp/canary-hc\nexec /usr/bin/grep \"\$@\"\n" > ~/.local/bin/grep && chmod +x ~/.local/bin/grep && rm -f /tmp/canary-nonnp /tmp/canary-hc'
sleep 70
check "no healthcheck ran code from ~/.local/bin" '[ ! -e /tmp/canary-hc ] && [ ! -s /tmp/canary-nonnp ]'
check "control: the planted grep runs for dev" '"$HOME"/.local/bin/grep -q x <<<x && [ -e /tmp/canary-hc ]'
dev 'rm -f ~/.local/bin/grep /tmp/canary-hc /tmp/canary-nonnp'

section "Home and runtime settings (H6, R2-R4)"
check "home and workspace are private (0700)" '[ "$(stat -c %a ~)" = 700 ] && [ "$(stat -c %a /workspace)" = 700 ]'
check_host "log driver, OOM priority and CPU shares of t3-dev" 'v=$(docker inspect -f "{{.HostConfig.LogConfig.Type}} {{index .HostConfig.LogConfig.Config \"max-size\"}} {{.HostConfig.OomScoreAdj}} {{.HostConfig.CPUShares}}" t3-dev); echo "$v"; [ "$v" = "local 10m 800 256" ]'
check_host "t3-dev-net and t3-dev-init have small local logs" 'for c in t3-dev-net t3-dev-init; do v=$(docker inspect -f "{{.HostConfig.LogConfig.Type}} {{index .HostConfig.LogConfig.Config \"max-size\"}}" $c); [ "$v" = "local 1m" ] || { echo "$c: $v"; exit 1; }; done'
check "dev cannot lower its OOM priority" '[ "$(cat /proc/1/oom_score_adj)" = 800 ] && ! sh -c "echo 0 > /proc/self/oom_score_adj" 2>/dev/null'
check "dev cannot change the firewall even as root of its own user namespace" '! unshare -Ur iptables-nft -F OUTPUT 2>/dev/null'
check_host "the namespace firewall is untouched after that" 'docker exec t3-dev-net iptables-nft -S OUTPUT | grep -q "192.168.0.0/16.*REJECT"'
check "IPv6 is off and dev cannot turn it on" '[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" = 1 ] && ! sh -c "echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6" 2>/dev/null'
