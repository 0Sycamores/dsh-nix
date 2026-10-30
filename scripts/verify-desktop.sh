#!/usr/bin/env bash
# 切换后的自动化验收：检查 HM 生成的入口/launcher/home patch，并用打包 CLI 复核
# 声明式设置真的被 dsh 配置层接受。可安全重复执行（不启动 GUI、不写真实 DSH_HOME）。
#
# 用法：bash scripts/verify-desktop.sh [--package <store path>]
# 退出码：0 = 全部通过；1 = 有失败项。
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
  # 优先用系统里实际安装的包（NixOS HM 默认装到 /etc/profiles/per-user/<user>）。
  INSTALLED=$(command -v dsh-desktop 2>/dev/null || true)
  if [ -n "$INSTALLED" ]; then
    PKG=$(dirname "$(dirname "$(readlink -f "$INSTALLED")")")
  fi
fi
if [ -z "$PKG" ]; then
  PKG=$(nix build "$REPO#dsh-desktop" --no-link --print-out-paths | tail -1)
fi

HOME_DIR=${HOME:?}
DSH_HOME=${DSH_HOME:-$HOME_DIR/.dsh}
RT="$PKG/lib/dsh-desktop/resources/runtime/primary-runtime/dependencies/node/bin/node"
CLI="$PKG/lib/dsh-desktop/resources/app/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js"

fails=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

[ -x "$RT" ] && pass "runtime node: $RT" || fail "missing runtime node: $RT"
[ -f "$CLI" ] && pass "desktop-host CLI: $CLI" || fail "missing CLI: $CLI"
[ -f "$DSH_HOME/cordis.patch.yml" ] && pass "home patch: $DSH_HOME/cordis.patch.yml" \
  || fail "missing home patch（是否已 nixos-rebuild switch？）"
[ -x "$HOME_DIR/.local/bin/dsh-desktop" ] && pass "launcher: ~/.local/bin/dsh-desktop" \
  || fail "missing launcher ~/.local/bin/dsh-desktop"
[ -f "$HOME_DIR/.local/share/applications/deepseek-harness.desktop" ] \
  && pass "desktop entry: ~/.local/share/applications/deepseek-harness.desktop" \
  || fail "missing desktop entry deepseek-harness.desktop"

ENTRY="$HOME_DIR/.local/share/applications/deepseek-harness.desktop"
if [ -f "$ENTRY" ]; then
  EXEC=$(sed -n 's/^Exec=//p' "$ENTRY" | head -1 | awk '{print $1}')
  if [ -n "$EXEC" ] && [ -x "$EXEC" ]; then
    pass "desktop entry Exec 可执行: $EXEC"
  else
    fail "desktop entry Exec 不可执行: ${EXEC:-<empty>}"
  fi
  if grep -q '^Icon=dsh-desktop$' "$ENTRY"; then pass "desktop entry Icon=dsh-desktop"; else fail "desktop entry Icon 异常"; fi
fi

if [ -f "$DSH_HOME/cordis.patch.yml" ]; then
  for id in agent-default-model permission ui-settings-general; do
    if grep -q "id: $id" "$DSH_HOME/cordis.patch.yml"; then
      pass "home patch 含 id: $id"
    else
      echo "WARN  home patch 不含 id: $id（若你的配置未声明该行则正常）"
    fi
  done
fi

ICON=""
for candidate in \
  "$PKG/share/icons/hicolor/512x512/apps/dsh-desktop.png" \
  "$HOME_DIR/.nix-profile/share/icons/hicolor/512x512/apps/dsh-desktop.png" \
  "/etc/profiles/per-user/${USER:-}/share/icons/hicolor/512x512/apps/dsh-desktop.png"; do
  if [ -f "$candidate" ]; then ICON=$candidate; break; fi
done
if [ -n "$ICON" ]; then
  pass "icon: $ICON"
else
  fail "missing icon（home.packages 是否安装？）"
fi

if [ -f "$DSH_HOME/cordis.patch.yml" ] && [ -x "$RT" ] && [ -f "$CLI" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp"
  cp "$DSH_HOME/cordis.patch.yml" "$tmp/cordis.patch.yml"
  if DSH_HOME=$tmp "$RT" --expose-internals "$CLI" --profile web --dump-config >"$tmp/dump.yml" 2>"$tmp/dump.err"; then
    patched=$(grep -c "patched by $tmp/cordis.patch.yml" "$tmp/dump.yml" || true)
    if [ "${patched:-0}" -gt 0 ]; then
      pass "home patch 被 dsh 配置层接受（$patched 个 layer patch）"
    else
      fail "home patch 未被任何 layer 命中"
    fi
    if grep -q 'danger-full-access' "$tmp/dump.yml"; then
      pass "permission preset 已进入合成配置"
    else
      fail "permission preset 未出现（检查 home patch 内容/整行替换语义）"
    fi
  else
    fail "CLI --profile web --dump-config 失败（见下）"
    tail -5 "$tmp/dump.err" | sed 's/^/      /'
  fi
fi

echo
echo "package: $PKG"
if [ "$fails" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
fi
echo "$fails CHECK(S) FAILED"
exit 1
