# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "Testcontainers (Java, like nfnn)"
copy_in "$root/tests/testcontainers-java" /workspace/testcontainers-java
check_agent "Gradle test with PostgreSQL in Testcontainers" '
  url=$(curl -fsSL https://services.gradle.org/versions/current | jq -r .downloadUrl) &&
  curl -fsSL "$url" -o /tmp/gradle.zip && unzip -q /tmp/gradle.zip -d /tmp/gradle &&
  cd /workspace/testcontainers-java && /tmp/gradle/gradle-*/bin/gradle --no-daemon test'
check_agent "Ryuk cleaned up after the run" 'sleep 15; [ -z "$(docker ps -q --filter label=org.testcontainers=true)" ]'
