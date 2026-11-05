#!/usr/bin/env python3
"""Fails when a seccomp profile would let t3-dev reach syscalls it must not have.
Usage: scripts/check-seccomp.py seccomp.json"""
import json
import sys

profile = json.load(open(sys.argv[1]))
granted = {"CAP_SETUID", "CAP_SETGID"}  # cap_add of t3-dev in compose.yml
blocking = {"SCMP_ACT_ERRNO", "SCMP_ACT_KILL", "SCMP_ACT_KILL_PROCESS", "SCMP_ACT_KILL_THREAD", "SCMP_ACT_TRAP"}
forbidden = {"bpf", "perf_event_open", "kexec_load", "kexec_file_load", "init_module", "finit_module", "delete_module",
             "userfaultfd", "io_uring_setup", "io_uring_enter", "io_uring_register", "open_by_handle_at",
             "keyctl", "add_key", "request_key"}

bad = [] if profile.get("defaultAction") in blocking else [f"defaultAction {profile.get('defaultAction')}"]
for rule in profile["syscalls"]:
    caps = set(rule.get("includes", {}).get("caps", []))
    if rule["action"] not in blocking and caps <= granted:
        bad += [f"{name}: {rule['action']} caps={sorted(caps)}" for name in rule["names"] if name in forbidden]
errno = {n: r.get("errnoRet") for r in profile["syscalls"] if r["action"] == "SCMP_ACT_ERRNO" for n in r["names"]}
bad += [f"{name} must return ENOSYS (entrypoint fingerprint)" for name in ("keyctl", "add_key", "request_key") if errno.get(name) != 38]
print("\n".join(bad) or "ok")
sys.exit(1 if bad else 0)
