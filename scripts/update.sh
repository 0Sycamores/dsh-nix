#!/usr/bin/env bash
# 更新 dsh-desktop 到新的上游 tag：重锁输入 → 重建载荷 → 重生成运行期 lockfile →
# 刷新 pnpm 依赖 hash → 全离线重建并输出包路径。
#
# 联网只发生在：fetch 类 FOD（依赖/资产预取）与上游 tag 的 pnpm install。
# 工具链固定在本仓库 flake 的 devShell（node/pnpm/git/python3）；失败会回滚已改文件。
#
# 用法：scripts/update.sh dsh-v0.2.3
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?usage: scripts/update.sh <dsh-vX.Y.Z>}
REGISTRY=${NPM_REGISTRY:-https://registry.npmmirror.com}
WORK=${DSH_UPDATE_WORKDIR:-$REPO/.update}
UPSTREAM_REMOTE=${DSH_UPSTREAM_REMOTE:-https://github.com/deepseek-ai/deepseek-harness.git}

log() { printf '\n== %s ==\n' "$*"; }

case "$WORK" in
  "$REPO"/*) ;;
  *)
    echo "error: DSH_UPDATE_WORKDIR 必须位于 $REPO 内（当前：$WORK）" >&2
    exit 1
    ;;
esac

if [ "${DSH_UPDATE_IN_DEV_SHELL:-}" != "1" ]; then
  # 工具链固定到 flake.lock 的 nixpkgs，避免生成的 lockfile 随宿主 pnpm 漂移。
  export DSH_UPDATE_IN_DEV_SHELL=1
  exec nix develop "$REPO" -c bash "$0" "$@"
fi

cleanup() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    echo "update 失败（exit $status）；回滚 flake/hash/runtime 生成物" >&2
    git -C "$REPO" checkout -- flake.nix flake.lock nix/payload.nix nix/runtime.nix nix/runtime 2>/dev/null || true
    git -C "$REPO" clean -fdq nix/runtime 2>/dev/null || true
    git -C "$REPO" status --short >&2 || true
  fi
  exit "$status"
}
trap cleanup EXIT

# 把一次 nix build 里 "got: sha256-..." 的哈希写回文件，然后重试一次。
refresh_hash() {
  local file=$1 attr=$2 target=$3
  local logfile got
  logfile=$(mktemp)
  if NIX_NPM_REGISTRY=$REGISTRY nix build "$target" --no-link -L >"$logfile" 2>&1; then
    echo "build already succeeds: $target"
    rm -f "$logfile"
    return 0
  fi
  got=$(grep -oE 'got:[[:space:]]+sha256-[A-Za-z0-9+/=]+' "$logfile" | tail -1 | awk '{print $2}') || true
  if [ -z "${got:-}" ]; then
    echo "error: build output has no hash mismatch; see below" >&2
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
text, count = re.subn(r'(dsh-src = \{\n\s+url = "github:deepseek-ai/deepseek-harness/)[^"]+(")', rf'\g<1>{tag}\g<2>', text)
if count != 1:
    raise SystemExit(f'expected exactly one dsh-src url in {path}, got {count}')
open(path, 'w').write(text)
PY
nix flake update dsh-src

log "2/7 准备上游 tag 检出与依赖（用于生成运行期 lockfile）"
rm -rf "$WORK"
mkdir -p "$WORK"
git clone --depth 1 --branch "$TAG" "$UPSTREAM_REMOTE" "$WORK/upstream"
(
  cd "$WORK/upstream"
  for patch in "$REPO"/patches/*.patch; do
    git apply "$patch"
  done
  pnpm install --frozen-lockfile --registry="$REGISTRY"
)

log "3/7 构建 payload（顺带刷新 monorepo 依赖 hash）"
refresh_hash "$REPO/nix/payload.nix" monorepoDepsHash .#dsh-desktop-payload
PAYLOAD=$(NIX_NPM_REGISTRY=$REGISTRY nix build .#dsh-desktop-payload --no-link --print-out-paths | tail -1)
echo "payload: $PAYLOAD"

log "4/7 重新生成运行期项目与 lockfile"
cp "$REPO/nix/gen-runtime-lock.ts" "$WORK/upstream/.dsh-nix-gen-runtime-lock.ts"
# 脚本内 ./apps/... 相对导入按脚本所在目录解析，因此放在检出根目录运行。
(
  cd "$WORK/upstream"
  NPM_REGISTRY="$REGISTRY" pnpm exec tsx .dsh-nix-gen-runtime-lock.ts "$PAYLOAD/package-set" "$REPO/nix/runtime"
)

log "5/7 刷新 runtime 依赖 hash"
refresh_hash "$REPO/nix/runtime.nix" runtimeDepsHash .#dsh-desktop-runtime

log "6/7 离线重建桌面包"
DESKTOP=$(NIX_NPM_REGISTRY=$REGISTRY nix build .#dsh-desktop --no-link --print-out-paths | tail -1)
echo "desktop: $DESKTOP"

log "7/7 检查改动并输出结果"
ALLOWED='^(flake\.nix|flake\.lock|nix/payload\.nix|nix/runtime\.nix|nix/runtime/project/)'
UNEXPECTED=$(git -C "$REPO" status --porcelain | sed -E 's/^...//' | grep -vE "$ALLOWED" || true)
if [ -n "$UNEXPECTED" ]; then
  echo "error: unexpected changes outside the update whitelist:" >&2
  echo "$UNEXPECTED" >&2
  exit 1
fi
trap - EXIT
echo "tag:       $TAG"
echo "payload:   $PAYLOAD"
echo "desktop:   $DESKTOP"
git -C "$REPO" status --short
