# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

syscall_probe='
import ctypes, errno, sys
libc = ctypes.CDLL(None, use_errno=True)
numbers = {"bpf": 321, "perf_event_open": 298, "kexec_load": 246, "init_module": 175, "finit_module": 313,
           "userfaultfd": 323, "io_uring_setup": 425, "open_by_handle_at": 304, "add_key": 248}
name = sys.argv[1]
r = libc.syscall(numbers[name], 0, 0, 0, 0, 0)
e = ctypes.get_errno()
print(name, r, errno.errorcode.get(e, e))
sys.exit(0 if r == -1 and e in (errno.EPERM, errno.ENOSYS) else 1)
'
dev "cat > /tmp/probe.py" <<<"$syscall_probe"

section "Syscalls the profile keeps blocked"
for s in bpf perf_event_open kexec_load init_module finit_module userfaultfd io_uring_setup open_by_handle_at; do
  check "$s blocked for dev" "python3 /tmp/probe.py $s"
  check "$s blocked inside a user namespace" "unshare -Ur python3 /tmp/probe.py $s"
done

section "Syscalls rootless Docker needs"
check "user namespaces work" 'unshare -Ur id -u | grep -qx 0'
check "keyring syscalls allowed (runc needs them)" 'python3 /tmp/probe.py add_key | grep -v EPERM'
check_host "profile in use is the custom one" 'docker inspect -f "{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}" t3-dev | grep -q "^seccomp="'
check_host "AppArmor unconfined and systempaths unconfined, nothing else relaxed" '[ "$(docker inspect -f "{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}" t3-dev | grep -v "^seccomp=" | sort | tr "\n" " ")" = "apparmor=unconfined systempaths=unconfined " ]'
