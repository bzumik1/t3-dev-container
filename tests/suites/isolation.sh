# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Privileges"
check "every process in the container runs as uid 1000" '[ "$(ps -eo uid= | tr -d " " | sort -u)" = 1000 ]'
check "PID 1 is tini as dev" '[ "$(ps -o comm= -p 1)" = tini ] && [ "$(ps -o uid= -p 1 | tr -d " ")" = 1000 ]'
check "bounding set holds only SETUID and SETGID (initial user namespace)" 'init=$(readlink /proc/1/ns/user); for p in $(pgrep .); do [ "$(readlink /proc/$p/ns/user 2>/dev/null)" = "$init" ] || continue; b=$(awk "/^CapBnd/ {print \$2}" /proc/$p/status 2>/dev/null) || continue; [ -z "$b" ] || [ "$b" = 00000000000000c0 ] || { echo "pid $p: $b"; exit 1; }; done'
check "no process in the initial user namespace has capabilities" 'init=$(readlink /proc/1/ns/user); for p in $(pgrep .); do [ "$(readlink /proc/$p/ns/user 2>/dev/null)" = "$init" ] || continue; for f in CapEff CapPrm CapAmb CapInh; do v=$(awk "/^$f/ {print \$2}" /proc/$p/status 2>/dev/null) || continue; [ -z "$v" ] || [ "$v" = 0000000000000000 ] || { echo "pid $p $f=$v $(tr "\\0" " " </proc/$p/cmdline)"; exit 1; }; done; done'
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
