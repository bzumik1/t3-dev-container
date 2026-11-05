# shellcheck shell=bash disable=SC2016,SC2154
start "$image"

section "Languages"
check "java 25 (Temurin)" 'java -version 2>&1 | grep -q "\"25" && java -version 2>&1 | grep -qi temurin'
check "javac 25" 'javac -version 2>&1 | grep -q "^javac 25"'
check "node 24" 'node -v | grep -q "^v24\."'
check_host "npm is the pinned version" "[ \"\$(docker exec t3-dev npm -v)\" = \"$(sed -n 's/^ARG NPM_VERSION=//p' "$root/Dockerfile")\" ]"
check "pnpm" 'pnpm -v'
check "python3 for scripts" 'python3 --version'

section "Supply-chain settings"
check "npm min-release-age 3" '[ "$(npm config get min-release-age)" = 3 ]'
check "npm ignore-scripts" '[ "$(npm config get ignore-scripts)" = true ]'
check "control: the same install script runs when allowed" 'd=$(mktemp -d) && cd $d && npm init -y >/dev/null && node -e "const p=require(\"./package.json\");p.scripts={postinstall:\"touch /tmp/allowed\"};require(\"fs\").writeFileSync(\"package.json\",JSON.stringify(p))" && npm install --ignore-scripts=false >/dev/null 2>&1; [ -e /tmp/allowed ]'
check "npm blocks install scripts" 'd=$(mktemp -d) && cd $d && npm init -y >/dev/null && node -e "const p=require(\"./package.json\");p.scripts={postinstall:\"touch /tmp/pwned\"};require(\"fs\").writeFileSync(\"package.json\",JSON.stringify(p))" && npm install >/dev/null 2>&1; [ ! -e /tmp/pwned ]'
check "control: npm installs an old version" 'd=$(mktemp -d) && cd $d && npm init -y >/dev/null && npm install typescript@5.4.5 >/dev/null 2>&1'
check "npm refuses too-fresh versions" 'd=$(mktemp -d) && cd $d && npm init -y >/dev/null && v=$(npm view typescript@next version --min-release-age=0) && ! npm install "typescript@$v" >/dev/null 2>&1'
check "npm global installs go to ~/.local" '[ "$(npm config get prefix)" = "$HOME/.local" ] && npm install -g cowsay@1.6.0 >/dev/null 2>&1 && [ -x ~/.local/bin/cowsay ]'
check "pnpm minimum release age" '[ "$(cd /tmp && pnpm config get minimumReleaseAge)" = 4320 ]'
check "uv cooldown configured" 'grep -q "exclude-newer = \"3 days\"" /etc/uv/uv.toml'

section "CLI tools"
check "git, git-lfs, gh, mise" 'git --version && git lfs version && gh --version && mise --version'
check "shell tools" 'for t in jq yq rg fd fzf tmux vim less htop zsh starship rsync unzip zip xz wget curl file lsof dig nc ping make gcc g++ pkg-config ssh; do command -v $t >/dev/null || { echo "missing $t"; exit 1; }; done'
check "docker CLI, compose, buildx" 'docker --version && docker compose version && docker buildx version'
check "t3-dev helper" 't3-dev help | grep -q install-agents'
check "mise installs a runtime without root" 'mise exec python@3.13 -- python --version'
check "mise installs node 22 next to 24" 'mise exec node@22 -- node -v | grep -q "^v22"'
check "locale UTF-8" 'locale | grep -q "UTF-8" && python3 -c "print(\"čeština\")" | grep -q čeština'
check "zsh config loads cleanly" 'zsh -ic "exit" 2>&1 | { ! grep -qi "error\|not found"; }'
check "agent guidance installed on first start" 'for f in ~/.codex/AGENTS.md ~/.claude/CLAUDE.md ~/.config/opencode/AGENTS.md; do for i in $(seq 60); do [ -s $f ] && break; sleep 2; done; [ -s $f ] || { echo "missing $f"; exit 1; }; done'

section "Projects cannot switch the package protections off (C3)"
check "a project .npmrc cannot disable the npm protections" 'd=$(mktemp -d) && cd $d && printf "ignore-scripts=false\nmin-release-age=0\n" > .npmrc && [ "$(npm config get ignore-scripts)" = true ] && [ "$(npm config get min-release-age)" = 3 ]'
check "control: pnpm installs an old version" 'd=$(mktemp -d) && cd $d && echo "{}" > package.json && pnpm add typescript@5.4.5 >/dev/null 2>&1'
check "pnpm-workspace.yaml cannot disable the pnpm cooldown (functional)" 'd=$(mktemp -d) && cd $d && v=$(npm view typescript@next version --min-release-age=0) && echo "{}" > package.json && printf "minimumReleaseAge: 0\n" > pnpm-workspace.yaml && ! pnpm add "typescript@$v" >/dev/null 2>&1'
check "a project registry cannot replace the public registry" 'd=$(mktemp -d) && cd $d && printf "registry=https://example.invalid/\n" > .npmrc && [ "$(npm config get registry)" = https://registry.npmjs.org/ ] && [ "$(pnpm config get registry)" = https://registry.npmjs.org/ ]'
check "uv cooldown set in the environment" '[ "$UV_EXCLUDE_NEWER" = "3 days" ]'

section "Tools work in the agents' sandbox (where T3 and the agents really run)"
wait_for "rootless dockerd answers" 180 'docker info'
check_agent "control: this is the sandbox" '[ "$(awk "/^NoNewPrivs:/ {print \$2}" /proc/self/status)" = 1 ] && ! readlink /proc/1/ns/user >/dev/null 2>&1'
check_agent "nested Docker" 'docker run --rm alpine true'
check_agent "bubblewrap (Claude Code and Codex sandboxes)" 'bwrap --unshare-all --die-with-parent --ro-bind / / --proc /proc --dev /dev true'
check_agent "git repository in /workspace (safe.directory)" 'rm -rf /workspace/sbx && git init -q /workspace/sbx && git -C /workspace/sbx status --short'
check_agent "mise runtime" 'mise exec node@22 -- node -v | grep -q "^v22"'
check_agent "npm install with the protections" 'd=$(mktemp -d) && cd $d && npm init -y >/dev/null && npm install typescript@5.4.5 >/dev/null 2>&1'
check_agent "t3-dev status" 't3-dev status'
