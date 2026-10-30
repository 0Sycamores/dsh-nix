# AGENTS.md

DSH 桌面端的 Nix/NixOS 打包（个人自用、非官方）。入口文档：

- 架构与离线构建：[docs/nix-implementation.md](docs/nix-implementation.md)
- 上游/Linux 适配事实：[docs/desktop-build.md](docs/desktop-build.md)、[docs/upstream-audit.md](docs/upstream-audit.md)
- 切换与验收：[docs/acceptance.md](docs/acceptance.md)
- 审计与已知限制：[docs/audit.md](docs/audit.md)
- 更新流程：[scripts/update.sh](scripts/update.sh)（先生成运行期 lockfile，再刷新 hash）

## 不变量

- 构建密封：普通派生构建阶段无网络；联网只发生在 `fetchPnpmDeps`/`fetchurl` FOD。
- `dsh` 运行时树带逐文件摘要（`desktop-runtime.json`）：不要对 payload/runtime 输出做 fixup/strip/patchShebangs；`nix/desktop.nix` 保持 `dontFixup`。
- `nix/runtime/project/*` 是 `scripts/update.sh` 的生成物，禁止手改；依赖/版本变更走更新脚本。
- Electron 用 `electron_44-bin`（`electron_44` 的 libexec dist 在本机会 GPU 崩溃）；Host/CLI 跑 runtime 自带的官方 Node。
- 工具链用 `nix develop`（node/pnpm/python3/shellcheck/nixfmt 已固定），不要依赖宿主工具。
- 系统切换由用户执行；切换后跑 `scripts/verify-desktop.sh`，改动生成布局时先跑 `scripts/check.sh`。

## Gotchas

- `nix eval` 不要读取派生输出里的文件（会触发 IFD/卡住）；版本等值从 flake 传入。
- 管道会吞掉失败状态：构建/watch 命令用 `set -o pipefail`，或检查 `${PIPESTATUS[0]}`。
- 杀进程用精确 pid（如 `pgrep -x dsh-desktop`），不要 `pkill -f` 匹配到自己命令行里的字符串。
- 当前主机可能是 `laptop` 而非 `home`：给切换命令前先看 `hostname` 与 `/run/current-system`。
