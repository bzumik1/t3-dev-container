# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Rootless Docker inside"
check "docker info reports rootless" 'docker info --format "{{.SecurityOptions}}" | grep -q rootless'
check "docker run hello-world" 'docker run --rm hello-world'
check "nested root is uid 1000 on the outside" 'docker run -d --name nested-sleep alpine sleep 300 >/dev/null && sleep 2 && u=$(ps -o uid= -C sleep | tr -d " " | sort -u); docker rm -f nested-sleep >/dev/null; echo "$u"; [ "$u" = 1000 ]'
check "published port reachable on localhost" 'docker run -d --name web -p 18080:80 nginx:alpine && for i in $(seq 30); do curl -fsS localhost:18080 >/dev/null && break; sleep 1; done; curl -fsS localhost:18080 | grep -q nginx; s=$?; docker rm -f web; exit $s'
check "docker build" 'd=$(mktemp -d) && printf "FROM alpine\nRUN echo ok > /ok\n" > $d/Dockerfile && docker build -q -t t3-dev-build-test $d && docker run --rm t3-dev-build-test cat /ok | grep -qx ok'
check "docker buildx build" 'd=$(mktemp -d) && printf "FROM alpine\nRUN echo buildx > /b\n" > $d/Dockerfile && docker buildx build --load -q -t t3-dev-buildx-test $d'
check "docker compose with two services and a network" '
  d=$(mktemp -d) && cat > $d/compose.yml <<EOF
services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_PASSWORD: test
    healthcheck:
      test: pg_isready -U postgres
      interval: 2s
      retries: 30
  client:
    image: postgres:17-alpine
    depends_on:
      db:
        condition: service_healthy
    environment:
      PGPASSWORD: test
    command: psql -h db -U postgres -tAc "select 42"
EOF
  cd $d && docker compose up --abort-on-container-exit --exit-code-from client 2>&1 | tee /tmp/compose.log && grep -q "42" /tmp/compose.log; s=$?; docker compose down -v; exit $s'
check "volumes keep data" 'docker volume create t3v && docker run --rm -v t3v:/d alpine sh -c "echo x > /d/f" && docker run --rm -v t3v:/d alpine cat /d/f | grep -qx x && docker volume rm t3v'
check "docker system df works" 'docker system df'

section "Nested containers stay inside (T6-T8, T13, T16)"
gateway=$(dev "ip route | awk '/default/ {print \$3}'")
python3 -m http.server 18999 --bind 0.0.0.0 >/dev/null 2>&1 &
host_server=$!
sleep 2
check "privileged nested containers are refused (rootless cannot grant them)" '! docker run --rm --privileged alpine true 2>/dev/null'
check "privileged nested container cannot write host kernel settings" '! docker run --rm --privileged alpine sh -c "echo x > /proc/sys/kernel/core_pattern" 2>/dev/null'
check "privileged nested container cannot reach the Docker host" "! docker run --rm --privileged alpine wget -q -O /dev/null -T 5 http://$gateway:18999/"
check "nested NET_ADMIN host-network container cannot bypass the firewall" "! docker run --rm --cap-add NET_ADMIN --network host alpine sh -c 'apk add -q iptables >/dev/null 2>&1; iptables -F 2>/dev/null; iptables -P OUTPUT ACCEPT 2>/dev/null; wget -q -O /dev/null -T 5 http://$gateway:18999/'"
check "seccomp filter is inherited by nested containers" 'docker run --rm alpine grep -q "^Seccomp:\s*2" /proc/self/status'
check "outer seccomp still applies to an unconfined nested container (keyctl ENOSYS)" 'docker run --rm --security-opt seccomp=unconfined python:3-alpine python -c "import ctypes,sys; l=ctypes.CDLL(None,use_errno=True); r=l.syscall(250,0,0,0,0,0); sys.exit(0 if r==-1 and ctypes.get_errno()==38 else 1)"'
check "nested daemon publishes ports on 127.0.0.1 only" 'docker run -d --name p1 -p 18084:80 nginx:alpine >/dev/null && sleep 2 && docker port p1 80 | grep -qx "127.0.0.1:18084"; s=$?; docker rm -f p1 >/dev/null; exit $s'
check "nested daemon uses the local log driver" 'docker info -f "{{.LoggingDriver}}" | grep -qx local'
ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" t3-dev-net)
dev 'docker run -d --name p2 -p 0.0.0.0:18082:80 nginx:alpine >/dev/null; sleep 3'
check "control: the 0.0.0.0-published nested port answers inside" 'curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:18082/'
check_host "an explicitly 0.0.0.0-published nested port is still unreachable from the host" "! curl -sS -o /dev/null --max-time 5 http://$ip:18082/"
dev 'docker rm -f p2 >/dev/null'
check "maintenance removes stopped containers" 'docker run --name stopped alpine true && [ -n "$(docker ps -aq --filter name=^stopped$)" ] && MAINTENANCE_UNTIL=0s /usr/local/libexec/t3-dev/maintenance --once && [ -z "$(docker ps -aq --filter name=^stopped$)" ]'
kill "$host_server"
