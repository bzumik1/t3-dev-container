---
name: change-agents
description: Add, remove or relocate a coding agent (Codex, Claude Code, OpenCode or a new one) in the t3-dev image. Use before changing how the agents are installed, updated, put on PATH or given their instructions inside the container.
---

# Change the set of agents in the image

The agents are not in the `Dockerfile`. They install into the home directory on the first start and update themselves. One agent is spread over several places, so change all of them in one PR:

- `rootfs/usr/local/bin/t3-dev`: `install_agents`, `update_agents` and the version list of `status`
- `rootfs/usr/local/libexec/t3-dev/agent-instructions`: the list of global instruction files it writes
- `PATH`, if the agent installs outside `~/.local/bin`: `rootfs/etc/t3-dev/env.sh`, the `[program:t3]` environment in `rootfs/etc/t3-dev/supervisord.conf`, the `export PATH` in `rootfs/usr/local/bin/t3-dev`, and `DEV_PATH` in `tests/lib.sh`
- `rootfs/etc/t3-dev/agent-environment.md`: the credential paths that agents must never print
- `tests/suites/agents.sh` (installed, runs, on `PATH`), `tests/suites/tools.sh` (instructions installed) and `tests/suites/persistence.sh` (managed block kept and refreshed)
- `README.md`: `Co v něm je`, signing in (installation step 4), `Instrukce pro agenty`, and the token risk in `Zabezpečení`

The installers are vendor scripts piped into a shell. A new agent widens the supply chain and adds tokens that can be stolen, so say so in the PR.

The agents in this list also develop this repository. When one is added or removed, check that the layout in `AGENTS.md` (`How the agent instructions are organized`) still works for it.
