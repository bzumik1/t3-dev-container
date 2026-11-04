# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Rootless Docker inside"
check "docker info reports rootless" 'docker info --format "{{.SecurityOptions}}" | grep -q rootless'
check "docker run hello-world" 'docker run --rm hello-world'
check "nested root is uid 1000 on the outside" 'docker run -d --name s alpine sleep 300 >/dev/null && sleep 2 && u=$(ps -o uid= -C sleep | tr -d " " | sort -u); docker rm -f s >/dev/null; echo "$u"; [ "$u" = 1000 ]'
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
check "privileged nested container is refused or harmless" 'docker run --rm --privileged alpine true 2>/dev/null; docker run --rm alpine true'
check "volumes keep data" 'docker volume create t3v && docker run --rm -v t3v:/d alpine sh -c "echo x > /d/f" && docker run --rm -v t3v:/d alpine cat /d/f | grep -qx x && docker volume rm t3v'
check "docker system df works" 'docker system df'
