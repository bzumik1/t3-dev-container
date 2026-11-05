# shellcheck shell=bash disable=SC2016,SC2154
start "$image"

section "nfnn e2e (Playwright Chromium against the production build)"
check_agent "clone nfnn" 'git clone -q --depth 1 https://github.com/bzumik1/nfnn.git /workspace/nfnn'
check_agent "npm ci" 'cd /workspace/nfnn/frontend && npm ci'
check_agent "Playwright Chromium installs without root" 'cd /workspace/nfnn/frontend && npx playwright install --only-shell chromium webkit'
check_agent "npm run e2e" 'cd /workspace/nfnn/frontend && npm run e2e'
