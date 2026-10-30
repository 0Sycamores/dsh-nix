#!/usr/bin/env bash
# Rewrite npm tarballs deterministically: sorted entries, fixed mtime/owner, normalized
# modes (755 when any exec bit, else 644), gzip without name/timestamp.
# 目的：pnpm pack 的条目顺序取决于文件系统 readdir 顺序，本地检出与 Nix store 不一致；
# 运行期 lockfile 的 file: 依赖 integrity 需要稳定字节。
set -euo pipefail

for tgz in "$@"; do
  work=$(mktemp -d)
  tar -xzf "$tgz" -C "$work"
  find "$work" -type d -exec chmod 755 {} +
  find "$work" -type f -perm -u+x -exec chmod 755 {} +
  find "$work" -type f ! -perm -u+x -exec chmod 644 {} +
  mapfile -d '' entries < <(cd "$work" && find . -mindepth 1 -maxdepth 1 -printf '%P\0' | LC_ALL=C sort -z)
  # 保留 tar 内的一级前缀（通常是 package/）；多个前缀逐一声明。
  tar --create --file "$work/../payload.tar" \
    --directory "$work" \
    --sort=name --mtime=@499162500 --owner=0 --group=0 --numeric-owner \
    --format=gnu "${entries[@]}"
  gzip -9 -n -c "$work/../payload.tar" > "$tgz.tmp"
  mv "$tgz.tmp" "$tgz"
  rm -rf "$work" "$work/../payload.tar"
done
