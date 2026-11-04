# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Limits protect the host"
check "pids limit stops runaway process creation" 'python3 - <<EOF
import os, signal, time
children = []
try:
    for _ in range(6000):
        pid = os.fork()
        if pid == 0:
            time.sleep(120)
            os._exit(0)
        children.append(pid)
except OSError as e:
    print("fork stopped after", len(children), e)
for pid in children:
    os.kill(pid, signal.SIGKILL)
for pid in children:
    os.waitpid(pid, 0)
assert len(children) < 4096, len(children)
EOF'
check "container still healthy after hitting the pids limit" 'sleep 5; docker info >/dev/null'
check "memory limit kills the hog inside, not the container" '! sh -c "head -c 9G /dev/zero | tail" 2>/dev/null; sleep 5; pgrep supervisord >/dev/null && docker info >/dev/null'
check_host "container kept running" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev)" = true ]'
check "nested containers count against the same limits" 'docker run --rm alpine sh -c "cat /sys/fs/cgroup/pids.max 2>/dev/null || true"; out=$(docker run --rm alpine sh -c "head -c 9G /dev/zero | tail" 2>&1); echo "$out"; sleep 5; pgrep supervisord >/dev/null'
check_host "host free memory unaffected" 'free -g; [ "$(free -g | awk "/Mem:/ {print \$7}")" -ge 2 ]'
