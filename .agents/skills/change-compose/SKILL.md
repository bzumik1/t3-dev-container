---
name: change-compose
description: Change compose.yml without breaking the tests or the server. Use before editing any line of compose.yml, changing a resource limit (memory, CPU, pids, OOM), adding or removing a security option, or making the image require a newer compose.yml.
---

# Change compose.yml

## The tests rewrite compose.yml by exact lines

`write_compose` in `tests/lib.sh` and the `mutate` calls in `tests/suites/selfcheck.sh` edit `compose.yml` with `sed` on exact lines, including the indentation. When a line is reworded or reindented, its pattern silently stops matching and the test passes without testing anything. Before changing a line, search for it:

```bash
rg -nF 'mem_limit: 8g' tests
```

## Resource limits

`mem_limit`, `memswap_limit`, `cpus`, `cpu_shares`, `oom_score_adj` and `pids_limit` also appear literally in:

- `tests/lib.sh`: `cpus: 10` is replaced with the runner's CPU count
- `tests/suites/selfcheck.sh`: mutations that delete the lines
- `tests/suites/isolation.sh`: the values expected from `docker inspect`
- `tests/suites/resources.sh`: memory hogs that must exceed the limit
- `README.md`: the `Limity` item in `Zabezpečení`
- `rootfs/etc/t3-dev/agent-environment.md`: what the agents inside are told

The entrypoint (`rootfs/usr/local/bin/t3-dev-entrypoint`) refuses to start without a memory limit, without a pids limit or with one above 8192, with swap allowed, or with `oom_score_adj` under 500. A limit outside these bounds needs the entrypoint changed in the same PR, or the image will not start.

The same host runs a production app. Raising a limit takes resources from it, so that is the owner's decision. Propose it, do not assume it.

## A new security option

1. Add it to `compose.yml`.
2. Make the entrypoint check it and refuse to start without it (`die` with a Czech message).
3. Add a mutation to `tests/suites/selfcheck.sh` that removes it and expects the container to refuse (`refuses`).
4. Describe it in `README.md` (`Zabezpečení`).

## The image needs a newer compose.yml

When the image depends on something only the new `compose.yml` provides (an option the entrypoint checks, a volume, a new seccomp profile):

1. Raise `required` in `rootfs/usr/local/libexec/t3-dev/compose-version`.
2. Set all three `T3_DEV_COMPOSE` values in `compose.yml` to it. CI counts them.
3. Update the `compose-version refuses malformed and old versions` step in `ci.yml`: the previous version goes into the refused list, and the new one is the accepted value.
4. Describe the upgrade in `README.md` (`Aktualizace`).

## Checks

`docker compose -f compose.yml config -q` and `python3 scripts/check-compose-mounts.py compose.yml` (no nested mount targets, no volume source overlapping a writable source of `t3-dev`). Then run the skill `check-change`.
