# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "nfnn backend (./gradlew test with Testcontainers and Cucumber)"
check "clone nfnn" 'git clone -q --depth 1 https://github.com/bzumik1/nfnn.git /workspace/nfnn'
check "./gradlew test" 'cd /workspace/nfnn/backend && ./gradlew --no-daemon test > /tmp/gradle.log 2>&1 && exit 0; tail -40 /tmp/gradle.log; echo "--- failed tests"; grep -l "<failure" build/test-results/*/*.xml | while read -r f; do grep -o "testcase name=\"[^\"]*\" classname=\"[^\"]*\"" "$f"; grep -A15 "<failure" "$f" | head -30; done; exit 1'
