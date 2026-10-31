#!/usr/bin/env bash
# 前台启动 dsh Web surface，token URL 直接打印在终端（不经 tmux 换行）。
# 使用已安装的 dsh（HM wrapper，会注入环境与 DSH_HOME）；没有时用 --package
# 指向的包或构建 .#dsh。Ctrl-C 停止，不常驻、不自启。
#
# 用法：bash scripts/serve-web.sh [--host 127.0.0.1] [--port 3080] [--package <store path>]
set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HOST=127.0.0.1
PORT=3080
PKG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST=${2:?--host needs a value}; shift 2 ;;
    --port) PORT=${2:?--port needs a value}; shift 2 ;;
    --package) PKG=${2:?--package needs a path}; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$PKG" ]; then
  DSH="$PKG/bin/dsh"
elif DSH=$(command -v dsh 2>/dev/null) && [ -n "$DSH" ]; then
  :
else
  PKG=$(nix build "$REPO#dsh" --no-link --print-out-paths | tail -1) || {
    echo "dsh not installed and failed to build $REPO#dsh; run nixos-rebuild switch or pass --package" >&2
    exit 1
  }
  DSH="$PKG/bin/dsh"
fi

if [ ! -x "$DSH" ]; then
  echo "missing dsh executable: $DSH" >&2
  exit 1
fi

echo "dsh web: starting on $HOST:$PORT (Ctrl-C to stop)"
exec "$DSH" web --no-open --host "$HOST" --port "$PORT"
