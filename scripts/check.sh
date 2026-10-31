#!/usr/bin/env bash
# 廉价质量门：脚本可执行位 / shellcheck / nixfmt / flake eval / 轻量 checks /
# verify 脚本自测。默认不构建 1.3G 的运行时/桌面端。
#
# 用法：bash scripts/check.sh [--full]   # --full 额外构建 dsh + dsh-desktop 并跑 web smoke
set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FULL=0
[ "${1:-}" = "--full" ] && FULL=1

if [ "${DSH_CHECK_IN_DEV_SHELL:-}" != "1" ]; then
  export DSH_CHECK_IN_DEV_SHELL=1
  exec nix develop "$REPO" -c bash "$0" "$@"
fi

fail=0
section() { printf '\n== %s ==\n' "$*"; }
check() {
  local name=$1
  shift
  if "$@"; then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    fail=$((fail + 1))
  fi
}

shell_files() {
  find "$REPO/scripts" "$REPO/nix" -maxdepth 1 -name '*.sh' ! -name 'launcher.sh' -type f | sort
}

section "executable bits"
bad=$(git -C "$REPO" ls-files -s scripts | awk '$1 != "100755"')
if [ -n "$bad" ]; then
  printf 'FAIL  scripts must be mode 100755:\n%s\n' "$bad"
  fail=$((fail + 1))
else
  printf 'ok    scripts are 100755\n'
fi

section "shellcheck / bash -n"
mapfile -t files < <(shell_files)
check shellcheck shellcheck "${files[@]}"
for file in "${files[@]}"; do
  check "bash -n $(basename "$file")" bash -n "$file"
done

section "nixfmt"
mapfile -t nixfiles < <(find "$REPO" -name '*.nix' -not -path '*/.update/*' -type f | sort)
check nixfmt nixfmt --check "${nixfiles[@]}"

section "flake tracked files"
untracked=$(git -C "$REPO" ls-files --others --exclude-standard -- '*.nix' 'scripts/*.sh' 'patches/*.patch' flake.nix)
if [ -n "$untracked" ]; then
  printf 'FAIL  untracked Nix files are invisible to flake path input; git add first:\n%s\n' "$untracked"
  fail=$((fail + 1))
else
  printf 'ok    all Nix files are tracked\n'
fi

section "flake eval"
check "nix flake check --no-build" nix flake check --no-build "$REPO"

section "lightweight checks"
check "checks (hm-module/hm-module-negative/scripts/runtime-lockfile)" \
  nix build "$REPO#checks.x86_64-linux.hm-module" \
            "$REPO#checks.x86_64-linux.hm-module-negative" \
            "$REPO#checks.x86_64-linux.scripts" \
            "$REPO#checks.x86_64-linux.runtime-lockfile" \
            --no-link

section "verify-desktop self-test"
check "verify-desktop --self-test" bash "$REPO/scripts/verify-desktop.sh" --self-test

if [ "$FULL" -eq 1 ]; then
  section "full desktop build"
  check "nix build .#dsh-desktop" nix build "$REPO#dsh-desktop" --no-link

  section "full dsh (CLI/web) build"
  if dsh_out=$(nix build "$REPO#dsh" --no-link --print-out-paths); then
    printf 'ok    nix build .#dsh\n'
    if [ -x "$dsh_out/bin/dsh" ]; then
      printf 'ok    dsh executable\n'
    else
      printf 'FAIL  dsh executable missing\n'
      fail=$((fail + 1))
    fi
    if nix-store -qR "$dsh_out" | grep -Eq -- 'electron[-_]'; then
      printf 'FAIL  .#dsh closure unexpectedly contains Electron:\n'
      nix-store -qR "$dsh_out" | grep -E -- 'electron[-_]' | sed 's/^/      /'
      fail=$((fail + 1))
    else
      printf 'ok    .#dsh closure has no Electron\n'
    fi
    check "verify-web" bash "$REPO/scripts/verify-web.sh" --package "$dsh_out"
  else
    printf 'FAIL  nix build .#dsh\n'
    fail=$((fail + 1))
  fi
fi

printf '\n'
if [ "$fail" -ne 0 ]; then
  echo "$fail CHECK(S) FAILED"
  exit 1
fi
echo "ALL CHECKS PASSED"
