# shellcheck shell=bash disable=SC2016,SC2154
start "$image"

section "nfnn frontend (as its CI, with the container's npm protections)"
check "clone nfnn" 'git clone -q --depth 1 https://github.com/bzumik1/nfnn.git /workspace/nfnn'
check "npm ci" 'cd /workspace/nfnn/frontend && npm ci'
check "format:check" 'cd /workspace/nfnn/frontend && npm run format:check'
check "lint" 'cd /workspace/nfnn/frontend && npm run lint'
check "lint:styles" 'cd /workspace/nfnn/frontend && npm run lint:styles'
check "unit tests" 'cd /workspace/nfnn/frontend && npm test -- --watch=false'
check "build" 'cd /workspace/nfnn/frontend && npm run build'
