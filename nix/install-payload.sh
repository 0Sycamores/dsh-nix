#!/usr/bin/env bash
set -euo pipefail
TARGET="$PWD/apps/desktop/.desktop-build/targets/linux-x64"
mkdir -p "$out/desktop"
cp -a apps/desktop/lib "$out/desktop/lib"
cp -a apps/desktop/renderer "$out/desktop/renderer"
cp apps/desktop/package.json "$out/desktop/package.json"
cp -a apps/desktop/resources "$out/desktop/resources"
cp -a "$TARGET/packed" "$out/packed"
cp -a "$TARGET/package-set" "$out/package-set"
cp -a "$OUT_SHELL/node_modules" "$out/shell-node-modules"

# 已构建的源码树快照：运行期装配派生用它来跑 prepare:dsh，避免重复 6 分钟构建。
mkdir -p "$out/src"
tar --exclude='./node_modules' \
    --exclude='./apps/desktop/.desktop-build' \
    --exclude='./.git' \
    --exclude='./.dsh-build' \
    --exclude='./.spike' \
    --exclude='./.desktop-build' \
    -cf - . | tar -xf - -C "$out/src"
