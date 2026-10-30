#!/usr/bin/env bash
set -euo pipefail
TARGET="$PWD/apps/desktop/.desktop-build/targets/linux-x64"
mkdir -p "$out"
cp -a "$TARGET/dsh" "$out/dsh"
cp -a "$TARGET/runtime" "$out/runtime"
