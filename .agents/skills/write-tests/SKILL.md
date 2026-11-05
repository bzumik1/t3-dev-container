---
name: write-tests
description: Write or change the integration tests and CI lints of this repository. Use before adding a check to tests/suites, adding a new suite, changing tests/lib.sh, or adding a lint step to .github/workflows/ci.yml.
---

# Write tests

`tests/run.sh <image> <suite>` sources `tests/lib.sh` and then `tests/suites/<suite>.sh`. A suite starts the real stack from `compose.yml`, with its paths moved to a temporary directory, and checks it.

## Helpers from tests/lib.sh

| Helper | Where the command runs |
|---|---|
| `check NAME 'CMD'` | inside `t3-dev` as `dev` |
| `check_agent NAME 'CMD'` | where the agents run: `no_new_privs`, own user namespace. Use it for anything an agent could try. |
| `check_host NAME 'CMD'` | on the CI runner, for example `docker inspect` |
| `wait_for NAME SECONDS 'CMD'` | inside `t3-dev`, retried until it succeeds or times out |

Commands are single-quoted on purpose, so they expand inside the container, not on the runner. Read `tests/lib.sh` for `start`, `wait_ready`, `section`, `skip`, `write_compose` and `mutate`, and `tests/suites/selfcheck.sh` for `refuses`.

## Every check must be able to fail

- A negative check (`! ...`) needs a control that proves the positive case works, otherwise a broken setup makes it pass. See the `control:` checks in `tests/suites/agents.sh`.
- A CI lint step that runs a script also feeds it a bad input and expects a failure. See the seccomp and compose mount steps in `ci.yml`.
- A `sed` pattern on `compose.yml` must match an existing line exactly (skill `change-compose`).

## A new suite

- Add it to the `suite` matrix of the `test` job in `ci.yml`. Suites are not discovered automatically.
- `gate` counts `lint`, `build`, `test` and `scan`. The `nfnn-*` suites run a real project with `continue-on-error`, so they never block a release.
- ShellCheck covers `tests/suites/*.sh` without changes.

## Running

The suites do not run inside `t3-dev`: `tests/lib.sh` needs `sudo` and the security options of `compose.yml`. On a Docker host with `sudo` it is `tests/run.sh <image> <suite>`. Otherwise CI on the PR is the test, so say in the PR which suites you could not run.
