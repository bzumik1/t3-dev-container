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
docker exec -u dev -e PATH="$DEV_PATH" t3-dev sh -c "cat /dev/null" >/dev/null 2>&1 || true
check "control: the canaries fire for a process that uses dev PATH" 'ls /tmp/canary-1000-cat'
check_host "root in t3-dev cannot even enter dev's home (no DAC_OVERRIDE, home 0700)" '! docker exec -u 0 t3-dev ls /home/dev >/dev/null 2>&1'
dev 'rm -f /tmp/canary-1000-*'
docker exec -u 0 t3-dev /usr/local/bin/t3-dev help >/dev/null 2>&1 || true
docker exec -u 0 t3-dev /usr/local/bin/t3-dev bogus >/dev/null 2>&1 || true
docker exec -u 0 -i t3-dev bash -i -c true </dev/null >/dev/null 2>&1 || true
docker exec -u 0 t3-dev git --version >/dev/null 2>&1 || true
docker exec -u 0 -e HOME=/home/dev -e PATH="$DEV_PATH" -i t3-dev bash -i -c true </dev/null >/dev/null 2>&1 || true
check "no root context ran code from dev's home" '! ls /tmp/canary-0-* 2>/dev/null'
check "dockerd and supervisord run with a system PATH" '[ -n "$(pgrep -x supervisord)" ] && [ -n "$(pgrep -x dockerd)" ] && for p in $(pgrep -x dockerd) $(pgrep -x supervisord); do tr "\0" "\n" < /proc/$p/environ | grep -qx "PATH=/usr/sbin:/usr/bin:/sbin:/bin" || { echo "pid $p"; tr "\0" "\n" < /proc/$p/environ | grep ^PATH; exit 1; }; done'
check "supervisord does not start dockerd-rootless.sh from ~/.local/bin" '
  printf "#!/bin/sh\ntouch /tmp/canary-dockerd\nexec /usr/bin/dockerd-rootless.sh \"\$@\"\n" > ~/.local/bin/dockerd-rootless.sh && chmod +x ~/.local/bin/dockerd-rootless.sh &&
  supervisorctl -c /etc/t3-dev/supervisord.conf restart dockerd >/dev/null;
  for i in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 2; done; rm -f ~/.local/bin/dockerd-rootless.sh; [ ! -e /tmp/canary-dockerd ]'
dev 'for c in cat sed grep git ls id awk printf; do rm -f ~/.local/bin/$c; done; sed -i "/canary/d" ~/.bashrc'

section "Healthcheck runs with no_new_privs in its own user namespace (P2, M1)"
site=$(dev 'python3 -c "import site; print(site.getusersitepackages())"')
dev "mkdir -p $site"
put_file "$site/t3hc.pth" <<'PY'
import os; c = open("/proc/self/cmdline").read(); ("supervisorctl" in c and "status" in c) and open("/tmp/canary-hc-ns", "a").write(open("/proc/self/status").read().split("NoNewPrivs:\t")[1][0] + " " + os.readlink("/proc/self/ns/user") + "\n")
PY
dev 'rm -f /tmp/canary-hc-ns'
docker exec -u dev t3-dev python3 /usr/bin/supervisorctl -c /etc/t3-dev/supervisord.conf status >/dev/null 2>&1 || true
check "control: the .pth canary records a plain supervisorctl" '[ -s /tmp/canary-hc-ns ]'
dev 'rm -f /tmp/canary-hc-ns'
check_host "the image healthcheck enters the sandbox itself" 'docker inspect -f "{{json .Config.Healthcheck.Test}}" t3-dev | grep -qF "\"/usr/bin/setpriv\",\"--no-new-privs\",\"--\",\"/usr/bin/unshare\",\"--user\",\"--map-current-user\""'
init_ns=$(docker exec t3-dev readlink /proc/1/ns/user)
before=$(docker inspect -f '{{json .State.Health.Log}}' t3-dev | jq -r '.[-1].Start')
dev 'rm -f /tmp/hc-seen; end=$((SECONDS + 90)); while [ $SECONDS -lt $end ]; do for p in $(pgrep -f "[s]upervisorctl -c /etc/t3-dev/supervisord.conf status dockerd t3"); do s=$(awk "/^NoNewPrivs:/ {print \$2}" /proc/$p/status 2>/dev/null) && n=$(readlink /proc/$p/ns/user 2>/dev/null) && [ -n "$s" ] && echo "$s $n" >> /tmp/hc-seen; done; sleep 0.05; done'
after=$(docker inspect -f '{{json .State.Health.Log}}' t3-dev | jq -r '.[-1].Start')
check_host "control: a healthcheck ran in the window" "[ '$before' != '$after' ]"
check "control: the sampler saw the healthcheck's supervisorctl" '[ -s /tmp/hc-seen ]'
check "the healthcheck's supervisorctl runs with no_new_privs outside the initial user namespace" "! grep -v '^1 user:' /tmp/hc-seen && ! grep -qF '$init_ns' /tmp/hc-seen"
check "the healthcheck loads no Python code from dev's home (supervisorctl -I)" '[ ! -s /tmp/canary-hc-ns ]'
dev "rm -f $site/t3hc.pth /tmp/canary-hc-ns"

section "No process without no_new_privs loads Python code from dev's home (N1, E2)"
dev 'd=$(python3 -c "import site; print(site.getusersitepackages())") && mkdir -p "$d" && printf "%s\n" "import os; s=open(\"/proc/self/status\").read(); (\"NoNewPrivs:\\t0\" in s) and open(\"/tmp/canary-pth-%d\" % os.getpid(), \"w\").write(open(\"/proc/self/cmdline\").read().replace(\"\\0\", \" \"))" > "$d/t3canary.pth" && cp "$d/t3canary.pth" "$d/usercustomize.py"'
check "control: a dev python without no_new_privs loads the planted .pth" 'rm -f /tmp/canary-pth-*; python3 -c pass; ls /tmp/canary-pth-*'
dev 'rm -f /tmp/canary-pth-*; kill -TERM 1' || true
sleep 40
wait_ready
sleep 30
check "supervisord runs isolated (python3 -I)" 'tr "\0" " " < /proc/$(pgrep -x supervisord)/cmdline | grep -q "python3 -I"'
check "nothing without no_new_privs loaded it after a restart (supervisord, entrypoint)" '! cat /tmp/canary-pth-* 2>/dev/null | grep .'
dev 'd=$(python3 -c "import site; print(site.getusersitepackages())"); rm -f "$d/t3canary.pth" "$d/usercustomize.py" /tmp/canary-pth-*'

section "Services are kept away from processes without no_new_privs (M1)"
check "sshd, t3 and maintenance run in their own user namespace" 'init=$(readlink /proc/1/ns/user); for svc in sshd t3 maintenance; do p=$(supervisorctl -c /etc/t3-dev/supervisord.conf pid $svc); [ -n "$p" ] && [ "$p" != 0 ] && [ "$(readlink /proc/$p/ns/user)" != "$init" ] || { echo "$svc ($p) shares the user namespace of PID 1"; exit 1; }; done'
put_file /tmp/ptrace.py <<'PY'
import ctypes, errno, os, sys
libc = ctypes.CDLL(None, use_errno=True)
pid = int(sys.argv[1])
if libc.ptrace(16, pid, 0, 0) == 0:
    os.waitpid(pid, 0)
    libc.ptrace(17, pid, 0, 0)
    print("attached")
    sys.exit(0)
e = ctypes.get_errno()
try:
    open(f"/proc/{pid}/mem", "rb").close()
    print("mem opened")
    sys.exit(0)
except PermissionError:
    pass
print(os.strerror(e))
sys.exit(2 if e == errno.EPERM else 1)
PY
supervisord_pid=$(dev "pgrep -x supervisord")
check_host "control: with Yama off, a no_new_privs process in the container namespace can ptrace supervisord" "docker exec t3-dev setpriv --no-new-privs python3 -I /tmp/ptrace.py $supervisord_pid"
t3_pid=$(dev "supervisorctl -c /etc/t3-dev/supervisord.conf pid t3")
for target in 1 "$supervisord_pid" $(dev "pgrep -x rootlesskit"); do
  check_host "from a fresh services sandbox: EPERM for ptrace and /proc/$target/mem" "docker exec t3-dev setpriv --no-new-privs unshare --user --map-current-user python3 -I /tmp/ptrace.py $target; [ \$? = 2 ]"
  check_host "from the real t3 namespace: EPERM for ptrace and /proc/$target/mem" "docker exec t3-dev setpriv --no-new-privs nsenter --user --target $t3_pid --preserve-credentials python3 -I /tmp/ptrace.py $target; [ \$? = 2 ]"
done
put_file /tmp/nnp-audit.py <<'PY'
import os, sys
allowed = set(sys.argv[1:])
children = {}
for p in os.listdir("/proc"):
    if p.isdigit():
        try:
            ppid = int(open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()[1])
        except OSError:
            continue
        children.setdefault(ppid, []).append(int(p))
init_ns = os.readlink("/proc/1/ns/user")
bad, todo = [], [1]
while todo:
    pid = todo.pop()
    todo += children.get(pid, [])
    try:
        status = open(f"/proc/{pid}/status").read()
        comm = open(f"/proc/{pid}/comm").read().strip()
    except OSError:
        continue
    if "NoNewPrivs:\t0" not in status:
        continue
    try:
        if os.readlink(f"/proc/{pid}/ns/user") != init_ns:
            continue
    except OSError:
        bad.append(f"{pid} {comm} (namespace unreadable)")
        continue
    if comm not in allowed:
        bad.append(f"{pid} {comm}")
print("\n".join(bad) or "ok")
raise SystemExit(1 if bad else 0)
PY
check "only tini, supervisord and the rootless Docker parents run without no_new_privs" 'python3 -I /tmp/nnp-audit.py tini supervisord rootlesskit slirp4netns'
check "control: the audit reaches the Docker tree" 'python3 -I /tmp/nnp-audit.py tini supervisord | grep -q " rootlesskit$"'

section "Every t3-dev entry point and interactive shell runs in the agents' sandbox (R6 N1, N2)"
put_file /home/dev/.local/bin/gh <<'SH'
#!/bin/sh
echo "$(/usr/bin/awk '/^NoNewPrivs:/ {print $2}' /proc/self/status) $(/usr/bin/readlink /proc/self/ns/user)" >> /tmp/canary-helper
exec /usr/bin/gh "$@"
SH
dev 'chmod +x ~/.local/bin/gh; rm -f /tmp/canary-helper'
init_ns=$(docker exec t3-dev readlink /proc/1/ns/user)
docker exec -u dev -e PATH="$DEV_PATH" t3-dev gh --version >/dev/null 2>&1 || true
check_host "control: the planted gh records an unsandboxed caller" "docker exec t3-dev grep -qxF '0 $init_ns' /tmp/canary-helper"
docker exec t3-dev rm -f /tmp/canary-helper
docker exec t3-dev t3-dev status >/dev/null 2>&1 || true
check_host "t3-dev status from the host ran dev's PATH only inside the sandbox" "docker exec t3-dev sh -c '[ -s /tmp/canary-helper ] && ! grep -qF \"$init_ns\" /tmp/canary-helper && ! grep -q \"^0 \" /tmp/canary-helper'"
dev 'rm -f ~/.local/bin/gh /tmp/canary-helper'
check_host "interactive bash and zsh from docker exec enter the sandbox" 'i=$(docker exec t3-dev readlink /proc/1/ns/user); for sh in bash zsh; do o=$(docker exec -i t3-dev $sh -i -c "awk \"/^NoNewPrivs/ {print \\\$2}\" /proc/self/status; readlink /proc/self/ns/user" </dev/null 2>/dev/null | tail -2 | tr "\n" " "); echo "$sh: $o"; case "$o" in "1 "*) [ "${o#1 }" != "$i " ] || exit 1;; *) exit 1;; esac; done'
check_host "control: non-interactive bash -c stays where the tests need it" '[ "$(docker exec t3-dev bash -c "readlink /proc/self/ns/user")" = "$(docker exec t3-dev readlink /proc/1/ns/user)" ]'
put_file /tmp/rc-canary.sh <<'SH'
echo "$(/usr/bin/awk '/^NoNewPrivs:/ {print $2}' /proc/self/status) $(/usr/bin/readlink /proc/self/ns/user)" >> /tmp/canary-rc
SH
dev 'for f in ~/.bashrc ~/.zshrc ~/.zshenv ~/.profile; do echo ". /tmp/rc-canary.sh # canary" >> $f; done; rm -f /tmp/canary-rc'
printf 'exit\n' | docker exec -i t3-dev bash -i >/dev/null 2>&1 || true
printf 'exit\n' | docker exec -i t3-dev zsh -i >/dev/null 2>&1 || true
docker exec t3-dev zsh -c true >/dev/null 2>&1 || true
docker exec t3-dev bash -lc true >/dev/null 2>&1 || true
check_host "plain interactive shells, zsh -c and bash -lc read dev's rc files only inside the sandbox" "docker exec t3-dev sh -c '[ \$(grep -c . /tmp/canary-rc) -ge 4 ] && ! grep -q \"^0 \" /tmp/canary-rc && ! grep -qF \"$init_ns\" /tmp/canary-rc'"
dev 'sh /tmp/rc-canary.sh'
check_host "control: the rc canary records an unsandboxed caller" "docker exec t3-dev grep -qxF '0 $init_ns' /tmp/canary-rc"
dev 'sed -i "/# canary/d" ~/.bashrc ~/.zshrc ~/.zshenv ~/.profile; rm -f /tmp/canary-rc'

section "Home and runtime settings (H6, R2-R4)"
check "home and workspace are private (0700)" '[ "$(stat -c %a ~)" = 700 ] && [ "$(stat -c %a /workspace)" = 700 ]'
check_host "log driver, OOM priority and CPU shares of t3-dev" 'v=$(docker inspect -f "{{.HostConfig.LogConfig.Type}} {{index .HostConfig.LogConfig.Config \"max-size\"}} {{.HostConfig.OomScoreAdj}} {{.HostConfig.CPUShares}}" t3-dev); echo "$v"; [ "$v" = "local 10m 800 256" ]'
check_host "t3-dev-net and t3-dev-init have small local logs" 'for c in t3-dev-net t3-dev-init; do v=$(docker inspect -f "{{.HostConfig.LogConfig.Type}} {{index .HostConfig.LogConfig.Config \"max-size\"}}" $c); [ "$v" = "local 1m" ] || { echo "$c: $v"; exit 1; }; done'
check "dev cannot lower its OOM priority" '[ "$(cat /proc/1/oom_score_adj)" = 800 ] && ! sh -c "echo 0 > /proc/self/oom_score_adj" 2>/dev/null'
check "dev cannot change the firewall even as root of its own user namespace" '! unshare -Ur iptables-nft -F OUTPUT 2>/dev/null'
check_host "the namespace firewall is untouched after that" 'docker exec t3-dev-net iptables-nft -S OUTPUT | grep -q "192.168.0.0/16.*REJECT"'
check "outgoing ports stay clear of the nested Docker port range" 'read -r low high < /proc/sys/net/ipv4/ip_local_port_range; echo "$low $high"; [ "$low $high" = "61000 65535" ]'
check "IPv6 is off and dev cannot turn it on" '[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" = 1 ] && ! sh -c "echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6" 2>/dev/null'
