#!/usr/bin/env node
// Builds seccomp.json from Docker's default profile: the same filter, plus the
// namespace, mount and keyring syscalls that rootless Docker needs inside an
// unprivileged container. Everything else the default blocks (bpf,
// perf_event_open, kernel modules, kexec, userfaultfd, io_uring, ...) stays blocked.
// Usage: node scripts/generate-seccomp.mjs > seccomp.json

const source = "https://raw.githubusercontent.com/moby/profiles/main/seccomp/default.json";

const rootlessDockerSyscalls = [
  "add_key",
  "chroot",
  "clone",
  "clone3",
  "fsconfig",
  "fsmount",
  "fsopen",
  "fspick",
  "keyctl",
  "mount",
  "mount_setattr",
  "move_mount",
  "open_tree",
  "pivot_root",
  "request_key",
  "setdomainname",
  "sethostname",
  "setns",
  "umount",
  "umount2",
  "unshare",
];

const response = await fetch(source);
if (!response.ok) throw new Error(`${source}: ${response.status}`);
const profile = await response.json();

const restrictsWithoutSysAdmin = (rule) => rule.excludes?.caps?.includes("CAP_SYS_ADMIN");
profile.syscalls = profile.syscalls.filter((rule) => !restrictsWithoutSysAdmin(rule));
profile.syscalls.push({
  names: rootlessDockerSyscalls,
  action: "SCMP_ACT_ALLOW",
  comment: "t3-dev: rootless Docker (rootlesskit, runc) inside an unprivileged container",
});

process.stdout.write(JSON.stringify(profile, null, 2) + "\n");
