#!/usr/bin/env python3
"""Validate the committed runtime project: no registry URLs, patch hashes match."""
import hashlib
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
lock = (root / "pnpm-lock.yaml").read_text()
workspace = (root / "pnpm-workspace.yaml").read_text()

problems = []
if re.search(r"https?://", lock):
    problems.append("pnpm-lock.yaml contains registry URLs (expected none)")

def block(text, name):
    match = re.search(rf"^{name}:\n((?:  .*\n)*)", text, re.MULTILINE)
    return match.group(1) if match else ""

workspace_patches = dict(re.findall(r"^  ('?[^':]+'?): (patches/[^\n]+)$", block(workspace, "patchedDependencies"), re.MULTILINE))
lock_patches = dict(re.findall(r"^  ('?[^':]+'?): ([0-9a-f]{64})$", block(lock, "patchedDependencies"), re.MULTILINE))
if set(workspace_patches) != set(lock_patches):
    problems.append(f"patchedDependencies keys differ: workspace={sorted(workspace_patches)} lock={sorted(lock_patches)}")
for dep, path in workspace_patches.items():
    patch = root / path
    if not patch.is_file():
        problems.append(f"{dep}: missing patch file {path}")
        continue
    digest = hashlib.sha256(patch.read_bytes()).hexdigest()
    if lock_patches.get(dep) != digest:
        problems.append(f"{dep}: lock hash {lock_patches.get(dep)} != {digest} ({path})")

if problems:
    print("runtime lockfile check failed:", file=sys.stderr)
    for problem in problems:
        print(f"  - {problem}", file=sys.stderr)
    sys.exit(1)
print(f"runtime lockfile ok ({len(lock_patches)} patches)")
