# syntax=docker/dockerfile:1.7

FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_MAJOR=24
ARG JAVA_MAJOR=25

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Europe/Prague

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
 && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" > /etc/apt/sources.list.d/adoptium.list \
 && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor -o /etc/apt/keyrings/mise.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/mise.gpg] https://mise.jdx.dev/deb stable main" > /etc/apt/sources.list.d/mise.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin \
      uidmap libcap2-bin bubblewrap socat slirp4netns iptables iproute2 \
      "temurin-${JAVA_MAJOR}-jdk" nodejs gh mise \
      git git-lfs openssh-server openssh-client supervisor tini tzdata locales \
      build-essential pkg-config jq yq ripgrep fd-find fzf tmux vim less htop \
      wget unzip zip xz-utils rsync file procps psmisc lsof dnsutils iputils-ping netcat-openbsd \
      zsh zsh-autosuggestions zsh-syntax-highlighting bash-completion man-db \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && npm install -g --prefix /usr npm@latest pnpm@latest \
 && npx -y playwright@latest install-deps chromium \
 && curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin \
 && rm -rf /var/lib/apt/lists/* /root/.npm /root/.cache /tmp/*

RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd --gid 1000 dev \
 && useradd --uid 1000 --gid 1000 --create-home --shell /usr/bin/zsh dev \
 && usermod -p '*' dev \
 && echo "dev:100000:65536" > /etc/subuid \
 && echo "dev:100000:65536" > /etc/subgid \
 && mkdir -p /workspace /home/dev/.local/share/docker /home/dev/.config/t3-dev \
 && install -d -m 0700 -o 1000 -g 1000 /run/user/1000 \
 && ln -sf /home/dev/.config/t3-dev/machine-info /etc/machine-info \
 && chown -R dev:dev /workspace /home/dev \
 && ln -sf /run/user/1000/docker.sock /var/run/docker.sock \
 && find / -xdev -type f -perm /6000 -exec chmod a-s {} + \
 && getcap -r /usr /opt 2>/dev/null | awk "{print \$1}" | xargs -r -n1 setcap -r \
 && setcap cap_setuid=ep /usr/bin/newuidmap \
 && setcap cap_setgid=ep /usr/bin/newgidmap \
 && rm -f /etc/update-motd.d/* /etc/legal

COPY rootfs/ /

ENV HOME=/home/dev \
    USER=dev \
    SHELL=/usr/bin/zsh \
    XDG_RUNTIME_DIR=/run/user/1000 \
    DOCKER_HOST=unix:///run/user/1000/docker.sock \
    TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED=false \
    TESTCONTAINERS_HOST_OVERRIDE=localhost \
    NPM_CONFIG_IGNORE_SCRIPTS=true \
    NPM_CONFIG_MIN_RELEASE_AGE=3

USER 1000:1000

WORKDIR /workspace

EXPOSE 2222

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
  CMD ["/usr/local/bin/t3-dev", "health"]

ENTRYPOINT ["/usr/local/bin/t3-dev-entrypoint"]
