# t3-dev-container

Instructions for agents working **on this repository**. They do not go into the image.

This repository builds a hardened dev container for T3 Code and AI agents. It runs on the owner's home server (ZimaOS, Docker 27.5.1) next to a production app with personal data, so a mistake here reaches that server. Security comes before convenience. `README.md` (in Czech) is the user documentation and explains the architecture and the security model. Read its `Jak je to poskládané` and `Zabezpečení` sections before changing anything security related.

`rootfs/etc/t3-dev/agent-environment.md` is a different file: it tells agents working **inside** the running container about their environment, for any project. The image copies it into the global instructions of Codex, Claude Code and OpenCode. Put what is true for any project in the container there, and what is about developing this repository here.

## Skills

Procedures live in skills, `.agents/skills/<name>/SKILL.md`. Load the skill before the work it covers, and if your harness does not offer it, read the file.

| Before you | Skill |
|---|---|
| open or update a PR | `check-change` |
| touch `seccomp.json` or `scripts/generate-seccomp.mjs` | `change-seccomp` |
| change `compose.yml`, a resource limit or the compose version | `change-compose` |
| add or change a test, a suite or a CI lint | `write-tests` |
| add, remove or move an agent in the image | `change-agents` |
| hand work to another agent or thread, or pick up someone else's | `t3-handover` |

## Security invariants

- No root at run time in `t3-dev`: no `sudo`, no setuid programs. Its only capabilities are `SETUID` and `SETGID`, and only `newuidmap` and `newgidmap` have file capabilities.
- SSH, T3, the agents and maintenance run with `no_new_privs` in their own user namespace (`rootfs/etc/t3-dev/supervisord.conf`).
- The firewall lives in `t3-dev-net`, out of reach of `dev`. Private networks stay blocked, also for nested containers.
- Code outside that sandbox (the entrypoint, supervisord, `dockerd`, and everything in `t3-dev-net` and `t3-dev-init`) must not load anything `dev` can write. Such scripts set a system-only `PATH` and call tools by system paths, and Python runs with `-I`. Only the `t3` service and the `t3-dev` helper put `~/.local/bin` and the like on `PATH`, because they run inside the sandbox (the helper re-executes itself there first).
- The agents' `npm`, `pnpm` and `uv` protections come from the environment (`rootfs/etc/t3-dev/env.sh` and `ENV` in the `Dockerfile`), so a cloned project cannot switch them off. Keep the two in sync.

A change that loosens any of this (capabilities, seccomp, firewall, sandbox, mounts) must say so explicitly in the PR and explain why there is no safer alternative.

## Conventions

- **Language:** `README.md` and the runtime messages of the scripts (`[t3-dev] ...`) are in Czech. Code comments, test names, commit messages, `compose.yml` descriptions, the agent instructions and the skills are in English.
- **Pinning:** the base image and GitHub Actions are pinned by digest or commit SHA, with the version in a comment. Tools in the `Dockerfile` are pinned through `ARG`s, which Dependabot does not cover. No `@latest`.
- **Dockerfile:** every `npm`, `npx` or `pnpm` call starts with `NPM_CONFIG_IGNORE_SCRIPTS=true` (CI checks it).
- **Generated files:** `seccomp.json` comes from `scripts/generate-seccomp.mjs`. Never edit it by hand.
- **File modes:** scripts in `rootfs` keep their executable bit in git. `net-lib` is sourced, so it does not have one.
- **Tests:** the integration suites do not run inside `t3-dev`, because they need `sudo` on a Docker host. CI on the PR runs them.

## Workflow

- Every change goes through a branch and a PR. Say in the PR what you verified and what you could not run.
- **Never merge, approve or push to `main`, and never approve the `release` deployment.** Every image built from this repository runs on the owner's server. The owner reviews and merges.
- A change in the image reaches the server only after a release and a container restart.

## How the agent instructions are organized

Codex, Claude Code and OpenCode all work on this repository and load instructions differently, so the layout is fixed and `scripts/check-agent-files.sh` checks it in CI.

- **`AGENTS.md`** (this file) is always loaded: Codex and OpenCode read it natively, and `CLAUDE.md` imports it for Claude Code. Keep it short. Codex cuts project instructions at 32 KiB without a warning, so CI keeps this file under 24 KiB.
- **Skills** are read on demand. Codex and OpenCode find them in `.agents/skills`, and Claude Code through the symlink `.claude/skills -> ../.agents/skills`. The frontmatter holds only `name` (the directory name: lowercase letters, digits and hyphens) and a one-line `description` of at most 1024 characters that says when to use the skill. Add a new skill to the table above too, because a description alone does not always trigger it.
- **`CLAUDE.md`** starts with `@AGENTS.md`. Add something below it only if it applies to Claude Code alone.
- **Nothing else.** No `AGENTS.md`, `AGENTS.override.md` or `CLAUDE.md` in subdirectories, because each harness loads those differently: Codex when it starts in that directory or below, Claude Code only a nested `CLAUDE.md` and OpenCode only a nested `AGENTS.md`, each when it reads a file there. No `.claude/rules`, `.claude/commands`, `.claude/agents`, `.opencode/`, `.codex/` or `opencode.json`, because only one harness reads each of them.
- **State lives in the repository, not in a session.** One agent's conversation and memory are invisible to the others. A rule that should last goes in this file or a skill.
