#!/usr/bin/env bash
# 更新 dsh-desktop 到新的上游 tag：重锁输入 → 重建载荷 → 重生成运行期 lockfile →
# 刷新 pnpm 依赖 hash → 全部离线重建并输出包路径。
#
# 联网只发生在：fetch 类 FOD（依赖/资产预取）与上游 tag 的 pnpm install。
# 用法：scripts/update.sh dsh-v0.2.3
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?usage: scripts/update.sh <dsh-vX.Y.Z>}
REGISTRY=${NPM_REGISTRY:-https://registry.npmmirror.com}
WORK=${DSH_UPDATE_WORKDIR:-$REPO/.update}
UPSTREAM_REMOTE=${DSH_UPSTREAM_REMOTE:-https://github.com/deepseek-ai/deepseek-harness.git}
PNPM_PACKAGES=(nixpkgs#nodejs_24 nixpkgs#pnpm_11 nixpkgs#git nixpkgs#jq nixpkgs#cacert)

log() { printf '\n== %s ==\n' "$*"; }

# 把一次 nix build 里 "got: sha256-..." 的哈希写回文件（hash 默认为 lib.fakeHash 时先置空）。
refresh_hash() {
  local file=$1 attr=$2 target=$3
  local logfile
  logfile=$(mktemp)
  if NIX_NPM_REGISTRY=$REGISTRY nix build "$target" --no-link -L >"$logfile" 2>&1; then
    echo "build already succeeds: $target"
    rm -f "$logfile"
    return 0
  fi
  local got
  got=$(grep -oE 'got:[[:space:]]+sha256-[A-Za-z0-9+/=]+' "$logfile" | tail -1 | awk '{print $2}') || true
  if [ -z "${got:-}" ]; then
    echo "error: no hash mismatch in build output; see below" >&2
    tail -30 "$logfile" >&2
    rm -f "$logfile"
    return 1
  fi
  echo "updating $file: $attr -> $got"
  python3 - "$file" "$attr" "$got" <<'PY'
import re, sys
path, attr, got = sys.argv[1:4]
text = open(path).read()
pattern = re.compile(rf'({re.escape(attr)}\s*\?\s*")[^"]*(")')
if not pattern.search(text):
    raise SystemExit(f'{attr} not found in {path}')
open(path, 'w').write(pattern.sub(rf'\g<1>{got}\g<2>', text))
PY
  rm -f "$logfile"
  NIX_NPM_REGISTRY=$REGISTRY nix build "$target" --no-link -L >/dev/null 2>&1 || {
    echo "error: build still failing after hash refresh: $target" >&2
    NIX_NPM_REGISTRY=$REGISTRY nix build "$target" --no-link -L 2>&1 | tail -30 >&2
    return 1
  }
}

log "1/7 更新 flake 输入到 $TAG"
python3 - "$REPO/flake.nix" "$TAG" <<'PY'
import re, sys
path, tag = sys.argv[1:3]
text = open(path).read()
text = re.sub(r'(dsh-src = \{\n\s+url = "github:deepseek-ai/deepseek-harness/)[^"]+(")', rf'\g<1>{tag}\g<2>', text)
open(path, 'w').write(text)
PY
cd "$REPO"
nix flake update dsh-src

log "2/7 准备上游 tag 检出与依赖（用于生成运行期 lockfile）"
rm -rf "$WORK"
mkdir -p "$WORK"
git clone --depth 1 --branch "$TAG" "$UPSTREAM_REMOTE" "$WORK/upstream"
nix shell "${PNPM_PACKAGES[@]}" -c bash -c '
  set -euo pipefail
  cd "'"$WORK"'/upstream"
  git apply "'"$REPO"'"/patches/0001-desktop-build-paths-linux.patch
  git apply "'"$REPO"'"/patches/0002-prepare-dsh-runtime-node.patch
  git apply "'"$REPO"'"/patches/0003-linux-desktop-adaptations.patch
  pnpm install --frozen-lockfile --registry="'"$REGISTRY"'"
'

log "3/7 构建 payload（顺带刷新 monorepo 依赖 hash）"
refresh_hash "$REPO/nix/payload.nix" monorepoDepsHash .#dsh-desktop-payload
PAYLOAD=$(NIX_NPM_REGISTRY=$REGISTRY nix build .#dsh-desktop-payload --no-link --print-out-paths | tail -1)
echo "payload: $PAYLOAD"

log "4/7 重新生成运行期 lockfile 与项目元数据"
cp "$REPO/nix/gen-runtime-lock.ts" "$WORK/upstream/.dsh-nix-gen-runtime-lock.ts"
# 脚本内的 ./apps/... 相对导入按脚本所在目录解析，因此放在检出根目录运行。
nix shell "${PNPM_PACKAGES[@]}" -c bash -c '
  set -euo pipefail
  cd "'"$WORK"'/upstream"
  NPM_REGISTRY="'"$REGISTRY"'" pnpm exec tsx .dsh-nix-gen-runtime-lock.ts "'"$PAYLOAD"'/package-set" "'"$REPO"'/nix/runtime"
'

log "5/7 刷新 runtime 依赖 hash"
refresh_hash "$REPO/nix/runtime.nix" runtimeDepsHash .#dsh-desktop-runtime

log "6/7 离线重建桌面包"
DESKTOP=$(NIX_NPM_REGISTRY=$REGISTRY nix build .#dsh-desktop --no-link --print-out-paths | tail -1)
echo "desktop: $DESKTOP"

log "7/7 结果"
echo "tag:       $TAG"
echo "payload:   $PAYLOAD"
echo "desktop:   $DESKTOP"
git -C "$REPO" status --short
