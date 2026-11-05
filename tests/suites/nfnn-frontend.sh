# shellcheck shell=bash disable=SC2016,SC2154
start "$image"

section "nfnn frontend (as its CI, with the container's npm protections)"
check_agent "clone nfnn" 'git clone -q --depth 1 https://github.com/bzumik1/nfnn.git /workspace/nfnn'
check_agent "npm ci" 'cd /workspace/nfnn/frontend && npm ci'
check_agent "format:check" 'cd /workspace/nfnn/frontend && npm run format:check'
check_agent "lint" 'cd /workspace/nfnn/frontend && npm run lint'
check_agent "lint:styles" 'cd /workspace/nfnn/frontend && npm run lint:styles'
check_agent "unit tests" 'cd /workspace/nfnn/frontend && npm test -- --watch=false'
check_agent "build" 'cd /workspace/nfnn/frontend && npm run build'
