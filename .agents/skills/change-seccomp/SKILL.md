---
name: change-seccomp
description: Change the seccomp profile of t3-dev. Use before touching seccomp.json, scripts/generate-seccomp.mjs or scripts/check-seccomp.py, for example to allow a syscall that rootless Docker or a tool needs.
---

# Change the seccomp profile

`seccomp.json` is generated. Never edit it by hand.

1. Change `scripts/generate-seccomp.mjs`. It starts from Docker's default profile at a pinned `moby/profiles` commit, verified by SHA-256. To move to a newer upstream, set both values from `moby/profiles`.
2. Regenerate: `node scripts/generate-seccomp.mjs > seccomp.json`.
3. Put the new `sha256sum seccomp.json` into `README.md` (installation step 1). CI fails when the README pins a different hash.
4. Run `python3 scripts/check-seccomp.py seccomp.json`. It lists the syscalls that must stay blocked (`bpf`, `perf_event_open`, kernel modules, `kexec`, `userfaultfd`, `io_uring`, `open_by_handle_at`, the keyring). It also requires the keyring calls to return `ENOSYS`, because the entrypoint uses that as proof that this profile is loaded. Never remove an entry to make a change pass.

## Reaching the server

The server keeps its own copy (`/DATA/AppData/t3-dev/seccomp.json`, README installation step 1), so a new profile takes effect only after the owner downloads it. When the image depends on the new profile, raise the compose version (skill `change-compose`): the old setup then stops with a clear message, and the README upgrade note tells the owner to download `seccomp.json` again.

## In the PR

Allowing a syscall loosens the sandbox. Say so explicitly and explain why there is no safer alternative. Then run the skill `check-change`.
