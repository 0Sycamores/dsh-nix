#!/usr/bin/env bash
# dsh web 离线 smoke：用临时 DSH_HOME 起一个 port 0 的 web 服务，验证
# token URL 的 303、cookie 交换后的 200，以及页面确实注入了 boot manifest。
# 不读取、不写入真实 ~/.dsh，不打开浏览器。
#
# 用法：bash scripts/verify-web.sh [--package <store path>]
# 退出码：0 = 通过；1 = 失败。
set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

PKG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --package) PKG=${2:?--package needs a path}; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$PKG" ]; then
  PKG=$(nix build "$REPO#dsh" --no-link --print-out-paths | tail -1) || {
    echo "failed to build $REPO#dsh" >&2
    exit 1
  }
fi

DSH="$PKG/bin/dsh"
if [ ! -x "$DSH" ]; then
  echo "missing dsh executable: $DSH" >&2
  exit 1
fi

tmp=$(mktemp -d)
pid=""
cleanup() {
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

log="$tmp/web.log"
cookies="$tmp/cookies"
export DSH_HOME="$tmp/home"
"$DSH" web --no-open --port 0 >"$log" 2>&1 &
pid=$!

url=""
for _ in $(seq 1 150); do
  if grep -q 'dsh web: http' "$log" 2>/dev/null; then
    url=$(grep -o 'http://[^ ]*' "$log" | head -1)
    break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "dsh web exited before printing a URL" >&2
    sed 's/^/  /' "$log" >&2
    exit 1
  fi
  sleep 0.2
done

if [ -z "$url" ]; then
  echo "timed out waiting for dsh web URL" >&2
  sed 's/^/  /' "$log" >&2
  exit 1
fi

status=$(curl --max-time 10 -sS -o /dev/null -w '%{http_code}' -c "$cookies" "$url") || {
  echo "curl failed for token URL: $url" >&2
  exit 1
}
if [ "$status" != "303" ]; then
  echo "expected 303 from token URL, got $status: $url" >&2
  exit 1
fi

base=${url%%\?*}
status=$(curl --max-time 10 -sS -o "$tmp/index.html" -w '%{http_code}' -b "$cookies" "$base") || {
  echo "curl failed for authenticated index: $base" >&2
  exit 1
}
if [ "$status" != "200" ]; then
  echo "expected 200 from authenticated index, got $status: $base" >&2
  exit 1
fi
if ! grep -q '__DSH_BOOT__' "$tmp/index.html"; then
  echo "index is missing the injected __DSH_BOOT__ manifest" >&2
  exit 1
fi

echo "web smoke ok: $url -> 303 -> 200 (boot manifest present)"
