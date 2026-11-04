# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "nfnn backend (./gradlew test with Testcontainers and Cucumber)"
check "clone nfnn" 'git clone -q --depth 1 https://github.com/bzumik1/nfnn.git /workspace/nfnn'
check "./gradlew test" 'cd /workspace/nfnn/backend && ./gradlew --no-daemon test'
