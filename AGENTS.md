# AGENTS.md

DSH 桌面端与 Web/CLI 的 Nix/NixOS 打包（个人自用、非官方）。入口文档：

- 术语：[GLOSSARY.md](GLOSSARY.md)；架构取舍：[docs/adr/0001-one-runtime-three-surfaces.md](docs/adr/0001-one-runtime-three-surfaces.md)
- 架构与离线构建：[docs/nix-implementation.md](docs/nix-implementation.md)
- Web 运行手册：[docs/web.md](docs/web.md)
- 上游/Linux 适配事实：[docs/desktop-build.md](docs/desktop-build.md)、[docs/upstream-audit.md](docs/upstream-audit.md)
- 切换与验收：[docs/acceptance.md](docs/acceptance.md)
- 审计与已知限制：[docs/audit.md](docs/audit.md)
- 更新流程：[scripts/update.sh](scripts/update.sh)（先生成运行期 lockfile，再刷新 hash）

## 不变量

- 构建密封：普通派生构建阶段无网络；联网只发生在 `fetchPnpmDeps`/`fetchurl` FOD。
- 共享一份 runtime：`packages.dsh` 只引用 `dsh-desktop-runtime`，不复制/不 fixup；`./result/bin/dsh` 的闭包不得出现 Electron/GTK。
- `dsh` 运行时树带逐文件摘要（`desktop-runtime.json`）：不要对 payload/runtime 输出做 fixup/strip/patchShebangs；`nix/desktop.nix` 保持 `dontFixup`。
- `nix/runtime/project/*` 是 `scripts/update.sh` 的生成物，禁止手改；依赖/版本变更走更新脚本。
- Electron 用 `electron_44-bin`（`electron_44` 的 libexec dist 在本机会 GPU 崩溃）；Host/CLI 跑 runtime 自带的官方 Node。
- `programs.dsh` 是 `$DSH_HOME/cordis.patch.yml` 的唯一写入者；桌面模块只读它的 `dshHome`/`environmentFiles`，不要加回 settings 选项。
- Web **只手动启动**：不加 systemd unit、不自启；只绑 loopback 或 tailnet，不接公网 vhost。共享 `~/.dsh`，同一 session 只能在一个 Host 打开。
- 工具链：构建/检查/生成命令走 `nix develop`（node/pnpm/python3/shellcheck/nixfmt/curl 已固定）；只读排查可以直接用宿主 `rg`/`sed`/`ssh`。
- 系统切换由用户执行；桌面切换后跑 `scripts/verify-desktop.sh`，Web 用 `scripts/verify-web.sh`；改动生成布局时先跑 `scripts/check.sh`（重包用 `--full`）。
- 目标主机地址、SSH 端口、checkout 位置属于私有 `nixos-config`，不写进本仓库；切换前先看目标机 `hostname`、`/run/current-system` 和它自己的 git 状态，不要假设 laptop/home 同分支。

## Gotchas

- 新增 `.nix` 文件必须先 `git add`；flake path input 看不到未跟踪文件（`scripts/check.sh` 会预检）。
- 排查 UI 文案/行为读 `$DSH_SRC`（`nix develop` 设置）的源码，不要 `rg` 打包后的 `*-frontend/dist`：minified 单行，输出巨大且没有上下文。
- 临时 JSON/网络检查可 `nix develop -c jq …` / `nix develop -c curl …`；宿主 PATH 未必有 jq。
- `nix eval` 不要读取派生输出里的文件（会触发 IFD/卡住）；版本等值从 flake 传入。
- 管道会吞掉失败状态：构建/watch 命令用 `set -o pipefail`，或检查 `${PIPESTATUS[0]}`。
- 杀进程用精确 pid（如 `pgrep -x dsh-desktop`），不要 `pkill -f` 匹配到自己命令行里的字符串。
- `dsh web --host` 拒绝 wildcard；用 `tailscale ip -4` 的具体地址。token URL 每次启动都会变。
