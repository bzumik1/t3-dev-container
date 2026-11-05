# t3-dev-container

This file is for working **on this repository**. It does not go into the image.

The instructions that agents get **inside** the running container are a different file: `rootfs/etc/t3-dev/AGENTS.md`. Every start copies it into `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md` and `~/.config/opencode/AGENTS.md`. Put what is true for any project in the container there, and what is about developing this repository here.

The repository builds a hardened dev container for T3 Code and AI agents. It runs on the owner's home server (ZimaOS, Docker 27.5.1) next to a production app with personal data. A mistake here reaches that server, so security comes before convenience. `README.md` (in Czech) is the user documentation and explains the architecture and the security model. Read its `Jak je to poskládané` and `Zabezpečení` sections before changing anything security related.

## Layout

| Path | What it is |
|---|---|
| `Dockerfile` | The one image used by all three containers. `COPY rootfs/ /` brings in everything below. |
| `compose.yml` | `t3-dev-init` (volume ownership), `t3-dev-net` (network and firewall, root with `NET_ADMIN`), `t3-dev` (everything else, runs as `dev`). |
| `rootfs/usr/local/bin/t3-dev-entrypoint` | Verifies the sandbox and refuses to start when a compose option is missing. |
| `rootfs/usr/local/bin/t3-dev` | The `t3-dev` helper command. |
| `rootfs/usr/local/libexec/t3-dev/` | Service wrappers, firewall, maintenance, `agent-instructions`, `compose-version`. |
| `rootfs/etc/t3-dev/` | Config of the services and the shells, and the agents' `AGENTS.md`. |
| `seccomp.json` | **Generated** by `scripts/generate-seccomp.mjs`. Never edit it by hand. |
| `scripts/` | The seccomp generator and the lints used by CI. |
| `tests/run.sh`, `tests/lib.sh`, `tests/suites/` | Integration suites. Each one starts the real stack from `compose.yml` and checks it. |
| `.github/workflows/ci.yml` | `lint`, `build`, `test`, `nfnn`, `scan`, `gate`, `publish`. |

## Checking a change

The `lint` job in `.github/workflows/ci.yml` is the authority. Most of it runs here:

```bash
docker compose -f compose.yml config -q
python3 scripts/check-compose-mounts.py compose.yml
python3 scripts/check-seccomp.py seccomp.json
node scripts/generate-seccomp.mjs | diff -u seccomp.json -
scripts/lint-docker-exec.sh README.md rootfs/usr/local/bin/t3-dev
```

`shellcheck` and `hadolint` are not installed in `t3-dev`. Run them in nested Docker, with the arguments and the pinned Hadolint digest from the `lint` job (for ShellCheck, the image `koalaman/shellcheck:stable` with the repository mounted read-only).

The integration suites do **not** run inside `t3-dev`: `tests/lib.sh` needs `sudo` and the security options of `compose.yml`. On a Docker host with `sudo` it is `tests/run.sh <image> <suite>`. Otherwise CI on the PR is the test, so say in the PR what you could not run locally.

## Changes that must move together

CI fails, or worse, stays green and misleads, when one of these is changed alone.

- **`seccomp.json`:** change the generator, regenerate with `node scripts/generate-seccomp.mjs > seccomp.json`, then update the SHA-256 in `README.md` (installation step 1). `scripts/check-seccomp.py` holds the list of syscalls that must stay blocked.
- **A new `compose.yml` requirement:** when the image needs the new `compose.yml`, raise `required` in `rootfs/usr/local/libexec/t3-dev/compose-version`, all three `T3_DEV_COMPOSE` values in `compose.yml`, the hardcoded versions in the `compose-version refuses...` step of `ci.yml`, and describe the upgrade in `README.md`.
- **Resource limits:** the values also appear literally in `tests/lib.sh` (`cpus: 10`), `tests/suites/selfcheck.sh`, `tests/suites/isolation.sh`, `tests/suites/resources.sh`, `README.md` and `rootfs/etc/t3-dev/AGENTS.md`. The entrypoint enforces bounds on them too.
- **Other `compose.yml` lines:** `tests/lib.sh` and `tests/suites/selfcheck.sh` edit it with `sed` on exact lines, so a reworded line silently stops matching. Search the tests for the line before changing it.
- **A new security option in `compose.yml`:** add the check to the entrypoint and a mutation to `tests/suites/selfcheck.sh` that proves the container refuses to start without it.
- **A new test suite:** add it to the `suite` matrix in `ci.yml`. Suites are not discovered automatically. Only `test` counts for `gate`. The `nfnn-*` suites run a real project with `continue-on-error`.
- **`README.md`:** CI greps it. Keep `KbdInteractiveAuthentication no` and `IdentitiesOnly yes`, and send every suggested `docker exec` through the `t3-dev` helper (`scripts/lint-docker-exec.sh`).

## Security invariants

- No root at run time in `t3-dev`: no `sudo`, no setuid programs. Its only capabilities are `SETUID` and `SETGID`, and only `newuidmap` and `newgidmap` have file capabilities.
- SSH, T3, the agents and maintenance run with `no_new_privs` in their own user namespace (see `rootfs/etc/t3-dev/supervisord.conf`).
- The firewall lives in `t3-dev-net`, out of reach of `dev`. Private networks stay blocked, also for nested containers.
- Code outside that sandbox (the entrypoint, supervisord, `dockerd`, and everything in `t3-dev-net` and `t3-dev-init`) must not load anything `dev` can write. Such scripts set a system-only `PATH` and call tools by system paths, and Python runs with `-I`. Only the `t3` service and the `t3-dev` helper put `~/.local/bin` and the like on `PATH`, because they run inside the sandbox (the helper re-executes itself there first).
- The agents' `npm`, `pnpm` and `uv` protections come from the environment (`rootfs/etc/t3-dev/env.sh` and `ENV` in the `Dockerfile`), so a cloned project cannot switch them off. Keep the two in sync.

A change that loosens any of this (capabilities, seccomp, firewall, sandbox, mounts) must say so explicitly in the PR and explain why there is no safer alternative.

## Conventions

- **Language:** `README.md` and the runtime messages of the scripts (`[t3-dev] ...`) are in Czech. Code comments, test names, commit messages, `compose.yml` descriptions and both `AGENTS.md` files are in English.
- **Pinning:** the base image and GitHub Actions are pinned by digest or commit SHA, with the version in a comment. Tools in the `Dockerfile` are pinned through `ARG`s, and Dependabot does not cover those. No `@latest`.
- **Dockerfile:** every `npm`, `npx` or `pnpm` call starts with `NPM_CONFIG_IGNORE_SCRIPTS=true` (CI checks it).
- **Tests:** in a suite, `check` runs inside the container as `dev`, `check_agent` runs where the agents run (`no_new_privs`, own user namespace), and `check_host` runs on the runner. A new check must be able to fail, so CI lints come with a control that feeds them a bad input.
- **File modes:** scripts in `rootfs` keep their executable bit in git. `net-lib` is sourced, so it does not have one.

## Multiple agents

This repository is developed by Codex, Claude Code and OpenCode, all driven through T3 Code, and the container ships those same three. Any of them may continue work another one started.

**Instructions stay agent neutral.** Rules go in this file, which Codex and OpenCode read directly. `CLAUDE.md` only imports it, because Claude Code does not read `AGENTS.md`. Add something to `CLAUDE.md` only if it applies to Claude Code alone, and do not add other per-agent instruction files.

**State lives in the repository, not in a session.** One agent's conversation and memory are invisible to the others. Put what the next agent needs in a commit, the PR or the issue, including what was verified and what was not. A rule that should last goes in this file.

**Handing work over in T3 Code.** These are T3 tools, so they exist only in a session started by T3, and T3 gives the agent their exact rules:

| Need | Tool | What to keep in mind |
|---|---|---|
| A task for another agent or provider | `delegate_task` | The child gets only `task`, with no history of the parent, so the brief must stand on its own. |
| A separate checkout or PR per child | `delegate_task` with `isolation: "worktree"` | It starts from the parent commit, so **uncommitted edits stay out**. Commit first. |
| Move this thread to its own branch | `t3_worktree_handoff` | It ends the live session. Pass `continuationPrompt` or the thread just waits. |
| Branch off a thread, or bring its context back | `t3_thread_transfer` (`fork`, `merge_back`) | It moves conversation context, not files. |

Agents that run at the same time need separate worktrees and branches. By default a child shares the parent's checkout, so parallel edits there collide.

**Changing the set of agents in the image.** One agent is spread over several places, so update all of them:

- `install_agents`, `update_agents` and the version list in `rootfs/usr/local/bin/t3-dev`
- the target list in `rootfs/usr/local/libexec/t3-dev/agent-instructions`
- `PATH`, if it installs outside `~/.local/bin`: `rootfs/etc/t3-dev/env.sh`, `rootfs/etc/t3-dev/supervisord.conf`, `rootfs/usr/local/bin/t3-dev` and `DEV_PATH` in `tests/lib.sh`
- the credential paths in `rootfs/etc/t3-dev/AGENTS.md`
- `tests/suites/agents.sh`, `tests/suites/tools.sh`, `tests/suites/persistence.sh` and `README.md`

## Workflow

- Every change goes through a branch and a PR.
- **Never merge, approve or push to `main`, and never approve the `release` deployment.** Every image built from this repository runs on the owner's server. The owner reviews and merges.
- A change in `rootfs/etc/t3-dev/AGENTS.md` or anywhere else in the image reaches the server only after a release and a container restart.
