# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Limits protect the host"
check "pids limit stops runaway process creation" 'for i in $(seq 4500); do sleep 120 & done 2>/dev/null; n=$(pgrep -c -x sleep); pkill -x sleep; echo "started $n"; [ "$n" -lt 4096 ]'
check "container still healthy after hitting the pids limit" 'sleep 5; docker info >/dev/null'
check "memory limit kills the hog inside, not the container" '! sh -c "head -c 9G /dev/zero | tail" 2>/dev/null; sleep 5; pgrep supervisord >/dev/null && docker info >/dev/null'
check_host "container kept running" '[ "$(docker inspect -f "{{.State.Running}}" t3-dev)" = true ]'
check "nested containers count against the same limits" 'docker run --rm alpine sh -c "cat /sys/fs/cgroup/pids.max 2>/dev/null || true"; out=$(docker run --rm alpine sh -c "head -c 9G /dev/zero | tail" 2>&1); echo "$out"; sleep 5; pgrep supervisord >/dev/null'
check_host "host free memory unaffected" 'free -g; [ "$(free -g | awk "/Mem:/ {print \$7}")" -ge 2 ]'
