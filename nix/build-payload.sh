#!/usr/bin/env bash
# Hermetic upstream payload build: offline install, build, pack, package-set, shell deps.
set -euo pipefail

export DSH_DESKTOP_TARGET_PLATFORM=linux
export DSH_DESKTOP_TARGET_ARCH=x64
export HOME="$TMPDIR/home"
mkdir -p "$HOME"
export pnpm_config_pm_on_fail=ignore
export pnpm_config_trust_lockfile=true
# 非 git 源码树：用锁定的上游 tag commit 生成浏览器构建元数据。
export DSH_CLIENT_COMMIT_HASH="${SRC_REVISION:?}"
# release/pack 脚本通过 npm_execpath 找回 pnpm；pnpm exec 不设置它。
export npm_execpath="$(command -v pnpm)"

STORE="$TMPDIR/store-monorepo"
mkdir -p "$STORE"
tar --zstd -xf "$MONOREPO_DEPS/pnpm-store.tar.zst" -C "$STORE"
chmod -R +w "$STORE"
if [ -f "$STORE/v11/index.db.sql" ]; then
  sqlite3 "$STORE/v11/index.db" < "$STORE/v11/index.db.sql"
  rm "$STORE/v11/index.db.sql"
fi

pnpm config set store-dir "$STORE"
pnpm config set reporter append-only
pnpm config set package-import-method clone-or-copy
pnpm install --offline --ignore-scripts --frozen-lockfile

pnpm run build --profile local
pnpm --dir apps/desktop run build

TARGET="$PWD/apps/desktop/.desktop-build/targets/linux-x64"
mkdir -p "$TARGET/packed/dsh" "$TARGET/packed/vendor" "$TARGET/packed/landlock"
pnpm exec tsx apps/desktop/scripts/pack-local-packages.ts --out "$TARGET/packed/dsh"
pnpm --dir apps/desktop-host pack --pack-destination "$TARGET/packed/dsh"
pnpm run release:pack --family vendor --out "$TARGET/packed/vendor"
pnpm --dir native/system run build:ts
pnpm --dir native/system/packages/entry pack --pack-destination "$TARGET/packed/landlock"

# pnpm pack 的字节随文件系统 readdir 顺序变化；统一重打包成确定性 tarball，
# 供运行期 lockfile 的 file: 依赖 integrity 使用。
mapfile -t tarballs < <(find "$TARGET/packed" -name '*.tgz' -type f | LC_ALL=C sort)
bash ./.dsh-nix-normalize-tarballs.sh "${tarballs[@]}"
pnpm --dir apps/desktop run prepare:packages

rm -rf "$OUT_SHELL"
pnpm --filter @deepseek-ai/dsh-desktop deploy --prod --ignore-scripts --offline "$OUT_SHELL"
