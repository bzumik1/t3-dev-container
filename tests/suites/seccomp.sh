# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

syscall_probe='
import ctypes, errno, sys
libc = ctypes.CDLL(None, use_errno=True)
numbers = {"bpf": 321, "perf_event_open": 298, "kexec_load": 246, "init_module": 175, "finit_module": 313,
           "userfaultfd": 323, "io_uring_setup": 425, "open_by_handle_at": 304, "add_key": 248, "keyctl": 250, "getpid": 39}
name = sys.argv[1]
r = libc.syscall(numbers[name], 0, 0, 0, 0, 0)
e = ctypes.get_errno()
print(name, r, errno.errorcode.get(e, e))
sys.exit(0 if r == -1 and e in (errno.EPERM, errno.ENOSYS) else 1)
'
put_file /tmp/probe.py <<<"$syscall_probe"

section "Syscalls the profile keeps blocked"
check "control: the probe reports an allowed syscall as allowed" '! python3 /tmp/probe.py getpid'
for s in bpf perf_event_open kexec_load init_module finit_module userfaultfd io_uring_setup open_by_handle_at keyctl add_key; do
  check "$s blocked for dev" "python3 /tmp/probe.py $s"
  check "$s blocked inside a user namespace" "unshare -Ur python3 /tmp/probe.py $s"
done

section "Syscalls rootless Docker needs"
check "user namespaces work" 'unshare -Ur id -u | grep -qx 0'
check_host "profile in use is the custom one" 'docker inspect -f "{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}" t3-dev | grep -q "^seccomp="'
check_host "AppArmor unconfined, no masked or read-only /proc paths, nothing else relaxed" 'v=$(docker inspect -f "{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}" t3-dev | grep -E "^(apparmor|label|no-new-privileges|privileged)" | sort | tr "\n" " "); m=$(docker inspect -f "{{len .HostConfig.MaskedPaths}} {{len .HostConfig.ReadonlyPaths}} {{.HostConfig.Privileged}}" t3-dev); echo "$v / $m"; [ "$v" = "apparmor=unconfined " ] && [ "$m" = "0 0 false" ]'

section "Socket families the profile keeps blocked"
put_file /tmp/probe-socket.py <<'PY'
import errno, socket, sys
family, kind = int(sys.argv[1]), int(sys.argv[2])
try:
    socket.socket(family, kind, 0)
except OSError as e:
    print(family, errno.errorcode.get(e.errno, e.errno))
    sys.exit(0 if e.errno in (errno.EPERM, errno.EAFNOSUPPORT) else 1)
print(family, "created")
sys.exit(1)
PY
check "control: the socket probe reports an allowed family as allowed" '! python3 /tmp/probe-socket.py 2 1'
check "AF_ALG blocked" 'python3 /tmp/probe-socket.py 38 5'
check "AF_VSOCK blocked" 'python3 /tmp/probe-socket.py 40 1'
check "AF_ALG blocked inside a user namespace" 'unshare -Ur python3 /tmp/probe-socket.py 38 5'
