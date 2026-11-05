# Environment of the dev user, shared by zsh (/etc/zsh/zshenv) and bash
# (/etc/t3-dev/bash-guard), so every shell finds the agents and tools.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export TZ="${TZ:-Europe/Prague}"
export XDG_RUNTIME_DIR=/run/user/1000
export DOCKER_HOST=unix:///run/user/1000/docker.sock
export TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=false
export TESTCONTAINERS_HOST_OVERRIDE=localhost
export NPM_CONFIG_IGNORE_SCRIPTS=true
export NPM_CONFIG_MIN_RELEASE_AGE=3
export PNPM_CONFIG_MINIMUM_RELEASE_AGE=4320
export UV_EXCLUDE_NEWER="3 days"
export NPM_CONFIG_REGISTRY=https://registry.npmjs.org/
export PNPM_CONFIG_REGISTRY=https://registry.npmjs.org/
export PNPM_CONFIG_MINIMUM_RELEASE_AGE_IGNORE_MISSING_TIME=false
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export EDITOR=vim
