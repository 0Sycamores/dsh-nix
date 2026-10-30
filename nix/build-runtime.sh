#!/usr/bin/env bash
# Hermetic runtime assembly: offline monorepo install, prefetched primary runtime, offline dsh tree.
set -euo pipefail

export DSH_DESKTOP_TARGET_PLATFORM=linux
export DSH_DESKTOP_TARGET_ARCH=x64
export HOME="$TMPDIR/home"
mkdir -p "$HOME"
export pnpm_config_pm_on_fail=ignore
export pnpm_config_trust_lockfile=true

extract_store() {
  local deps=$1 store=$2
  rm -rf "$store"
  mkdir -p "$store"
  tar --zstd -xf "$deps/pnpm-store.tar.zst" -C "$store"
  chmod -R +w "$store"
  if [ -f "$store/v11/index.db.sql" ]; then
    sqlite3 "$store/v11/index.db" < "$store/v11/index.db.sql"
    rm "$store/v11/index.db.sql"
  fi
}

# tsx 等 workspace 工具依赖；同样用预取的 monorepo store 离线安装。
extract_store "$MONOREPO_DEPS" "$TMPDIR/store-monorepo"
pnpm config set store-dir "$TMPDIR/store-monorepo"
pnpm config set reporter append-only
pnpm config set package-import-method clone-or-copy
pnpm install --offline --ignore-scripts --frozen-lockfile

TARGET="$PWD/apps/desktop/.desktop-build/targets/linux-x64"
mkdir -p "$TARGET"
cp -a "$PAYLOAD/package-set" "$TARGET/package-set"

# primary runtime：预取资产填进 sha256 缓存，离线解包并生成 versions.json。
mkdir -p apps/desktop/.desktop-build/downloads
cp -a "$RUNTIME_ASSETS"/. apps/desktop/.desktop-build/downloads/
pnpm exec tsx ./.dsh-nix-prepare-runtime.ts

# dsh 生产树：commit 的 runtime lockfile + 预取 store + --offline。
extract_store "$RUNTIME_DEPS" "$PWD/apps/desktop/.desktop-build/pnpm-store"
export DSH_DESKTOP_RUNTIME_LOCKFILE="$RUNTIME_LOCKFILE"
export DSH_DESKTOP_PNPM_OFFLINE=1
export DSH_DESKTOP_DEFER_NATIVE_SMOKE=1
# 沙箱里不能执行 payload 的外来二进制；用 nix node（同版本 24.21.0）跑 pnpm。
export DSH_DESKTOP_HOST_NODE="$(command -v node)"
pnpm --dir apps/desktop run prepare:dsh -- --defer-runtime-smoke
