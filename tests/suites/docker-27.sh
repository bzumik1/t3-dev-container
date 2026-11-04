# shellcheck shell=bash disable=SC2016,SC2154
section "Host Docker 27.5.1, as on ZimaOS 1.7"
version=$(docker version -f '{{.Server.Version}}')
if [ "$version" != 27.5.1 ]; then
  fail "runner runs Docker $version instead of 27.5.1 (the workflow installs it)"
fi
pass "host Docker $version"

start "$image" "GITHUB_USER=bzumik1"
wait_ready
check "docker run inside" 'docker run --rm hello-world'
check "published port inside" 'docker run -d --name web -p 18080:80 nginx:alpine && for i in $(seq 30); do curl -fsS localhost:18080 >/dev/null && break; sleep 1; done; curl -fsS localhost:18080 | grep -q nginx; s=$?; docker rm -f web; exit $s'
check "firewall active" 'curl -fsS -o /dev/null --max-time 15 https://github.com && ! curl -sS -o /dev/null --max-time 5 http://192.168.1.1/'
check "privileges dropped" '[ "$(ps -eo uid= | tr -d " " | sort -u)" = 1000 ]'
wait_for "sshd listens" 90 'ssh-keyscan -p 2222 127.0.0.1 2>/dev/null | grep -q ssh-ed25519'
docker cp "$root/tests/testcontainers-java" t3-dev:/workspace/testcontainers-java
as_root "chown -R 1000:1000 /workspace/testcontainers-java"
check "Testcontainers with PostgreSQL" '
  url=$(curl -fsSL https://services.gradle.org/versions/current | jq -r .downloadUrl) &&
  curl -fsSL "$url" -o /tmp/gradle.zip && unzip -q /tmp/gradle.zip -d /tmp/gradle &&
  cd /workspace/testcontainers-java && /tmp/gradle/gradle-*/bin/gradle --no-daemon -q test'
