#!/usr/bin/env node
// Builds seccomp.json from Docker's default profile: the same filter, plus the
// namespace, mount and keyring syscalls that rootless Docker needs inside an
// unprivileged container. Everything else the default blocks (bpf,
// perf_event_open, kernel modules, kexec, userfaultfd, io_uring, ...) stays blocked.
// Usage: node scripts/generate-seccomp.mjs > seccomp.json

import { createHash } from "node:crypto";

// Pinned upstream: moby/profiles at a fixed commit, verified by SHA-256.
// To update: set both values from https://github.com/moby/profiles and regenerate.
const commit = "4b8214fc4971e06172938a1f1554ccff6647ee80";
const sha256 = "6416b47770785a41ac59073cdc77d9fe98517df2799dc83ef207e622de3053f6";
const source = `https://raw.githubusercontent.com/moby/profiles/${commit}/seccomp/default.json`;

const rootlessDockerSyscalls = [
  "chroot",
  "clone",
  "clone3",
  "fsconfig",
  "fsmount",
  "fsopen",
  "fspick",
  "mount",
  "mount_setattr",
  "move_mount",
  "open_tree",
  "pivot_root",
  "setdomainname",
  "sethostname",
  "setns",
  "umount2",
  "unshare",
];

const response = await fetch(source);
if (!response.ok) throw new Error(`${source}: ${response.status}`);
const body = Buffer.from(await response.arrayBuffer());
const digest = createHash("sha256").update(body).digest("hex");
if (digest !== sha256) throw new Error(`${source}: SHA-256 ${digest}, expected ${sha256}`);
const profile = JSON.parse(body.toString("utf8"));

const restrictsWithoutSysAdmin = (rule) => rule.excludes?.caps?.includes("CAP_SYS_ADMIN");
profile.syscalls = profile.syscalls.filter((rule) => !restrictsWithoutSysAdmin(rule));
profile.syscalls.push({
  names: rootlessDockerSyscalls,
  action: "SCMP_ACT_ALLOW",
  comment: "t3-dev: rootless Docker (rootlesskit, runc) inside an unprivileged container",
});

profile.syscalls.push({
  names: ["add_key", "keyctl", "request_key"],
  action: "SCMP_ACT_ERRNO",
  errnoRet: 38,
  comment: "t3-dev: keyrings report ENOSYS; runc tolerates that and nested containers keep working",
});

process.stdout.write(JSON.stringify(profile, null, 2) + "\n");
