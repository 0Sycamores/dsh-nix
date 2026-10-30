#!/usr/bin/env bash
# shellcheck disable=SC2154  # $out 由 Nix builder 提供
set -euo pipefail
TARGET="$PWD/apps/desktop/.desktop-build/targets/linux-x64"
mkdir -p "$out"
cp -a "$TARGET/dsh" "$out/dsh"
cp -a "$TARGET/runtime" "$out/runtime"
