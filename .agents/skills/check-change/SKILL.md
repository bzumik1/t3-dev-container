---
name: check-change
description: Run the local checks of this repository and report what could not run. Use before opening or updating a PR, after any change to the Dockerfile, compose.yml, rootfs, scripts, tests, seccomp.json, README.md, the agent instructions or the CI workflow.
---

# Check a change

The `lint` job in `.github/workflows/ci.yml` is the authority. When it and this skill disagree, follow the workflow and fix this skill.

## Checks that run here

```bash
docker compose -f compose.yml config -q
python3 scripts/check-compose-mounts.py compose.yml
python3 scripts/check-seccomp.py seccomp.json
node scripts/generate-seccomp.mjs | diff -u seccomp.json -
grep -q "$(sha256sum seccomp.json | cut -d' ' -f1)" README.md
scripts/lint-docker-exec.sh README.md rootfs/usr/local/bin/t3-dev
scripts/check-agent-files.sh
```

ShellCheck and Hadolint are not installed in `t3-dev`. Run them in nested Docker:

```bash
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable <arguments of the ShellCheck step>
docker run --rm -i hadolint/hadolint@<digest of the Hadolint step> hadolint --failure-threshold error - < Dockerfile
```

Copy the ShellCheck arguments and the Hadolint digest from `ci.yml`, not from here, because they change. The ShellCheck image has no shell, so the `$(grep ...)` in its arguments must be expanded by your own shell before `docker run`.

The other steps of the `lint` job are one-line `grep`, `yq` or `diff` checks. Run the ones your change can affect.

## What does not run here

The integration suites (`tests/run.sh <image> <suite>`) need `sudo` on a Docker host and the security options of `compose.yml`, and `t3-dev` has neither. CI runs them on the PR, together with the real-project suites and the Trivy scan.

## Report

In the PR description, list what you ran, what passed, and what you could not run. When CI on the PR fails, read the log of the failing job before changing anything.
