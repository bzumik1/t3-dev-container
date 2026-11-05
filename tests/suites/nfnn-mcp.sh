# shellcheck shell=bash disable=SC2016,SC2154
start "$image"
wait_ready

section "nfnn connector and full stack"
check "clone nfnn" 'git clone -q --depth 1 https://github.com/bzumik1/nfnn.git /workspace/nfnn'
check "mcp: npm ci, check, build" 'cd /workspace/nfnn/mcp && npm ci && npm run check && npm run build'
check "stack: docker compose up --build inside the container" 'cd /workspace/nfnn && cp .env.example .env && sed -i "s/^SPRING_PROFILES_ACTIVE=.*/SPRING_PROFILES_ACTIVE=dev/" .env && docker compose up -d --build --wait --wait-timeout 600'
check "stack: site answers on :8080" 'for i in $(seq 60); do curl -fsS -o /dev/null http://localhost:8080/ && exit 0; sleep 5; done; exit 1'
dev 'cd /workspace/nfnn && docker compose down -v' >/dev/null 2>&1 || true
