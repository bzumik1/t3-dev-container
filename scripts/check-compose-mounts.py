#!/usr/bin/env python3
"""Fails when a mount target lies inside another volume of the same service, or
when any volume source overlaps a writable source of t3-dev (a symlink planted
there could redirect a mount). Usage: scripts/check-compose-mounts.py compose.yml"""
import json
import subprocess
import sys

config = json.loads(subprocess.check_output(["docker", "compose", "-f", sys.argv[1], "config", "--format", "json"]))
bad = []
for name, service in config["services"].items():
    targets = [v["target"] for v in service.get("volumes", [])]
    for t in targets:
        for o in targets:
            if t != o and (t.rstrip("/") + "/").startswith(o.rstrip("/") + "/"):
                bad.append(f"{name}: target {t} inside {o}")
writable = [v["source"] for v in config["services"]["t3-dev"]["volumes"] if not v.get("read_only")]
for name, service in config["services"].items():
    for v in service.get("volumes", []):
        for w in writable:
            a, b = v["source"].rstrip("/") + "/", w.rstrip("/") + "/"
            if a != b and (a.startswith(b) or b.startswith(a)):
                bad.append(f"{name}: source {v['source']} overlaps t3-dev writable source {w}")
print("\n".join(bad) or "ok")
sys.exit(1 if bad else 0)
