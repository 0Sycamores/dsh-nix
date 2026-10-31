# 密封离线 Nix 构建（Gate 1）

## 结构

三个正常派生 + 两个 pnpm 依赖 FOD（`fetchPnpmDeps`）+ 13 个 `fetchurl` 资产 FOD，构建阶段不联网：

| 派生 | 作用 |
|---|---|
| `dsh-desktop-payload` | 上游 monorepo 离线安装（`fetchPnpmDeps`）、`build --profile local`、打四个 tarball、`prepare:packages`、`pnpm deploy` 取外壳生产依赖；产出 `desktop/`、`package-set/`、`shell-node-modules/` 和**已构建源码树** `src/` |
| `dsh-desktop-runtime` | 以 payload 的 `src/` 为源码，离线安装 workspace 依赖；把预取的 primary-runtime 资产（node/python/wheels）填进上游 sha256 缓存；`prepare:dsh --defer-runtime-smoke` 用**仓库里提交的 runtime lockfile** + 预取 pnpm store 离线物化 `dsh` 运行时树 |
| `dsh-desktop` | 纯组装：Electron dist + payload/运行时树 + 启动器；`dontFixup` 保证逐文件摘要的运行时树与 Electron dist 字节不变 |
| `dsh` | 薄 wrapper：只引用 `dsh-desktop-runtime` 的 `dsh/` 与 `runtime/`，提供 `bin/dsh`；不复制、不 fixup 运行时树，闭包不含 Electron |

FOD：

- `dsh-monorepo-deps`：monorepo `pnpm-lock.yaml` 的 pnpm store（`fetchPnpmDeps`, fetcherVersion 5）。
- `dsh-desktop-runtime-deps`：运行期项目 lockfile 的 pnpm store；`src` 是
  `nix/runtime/project/` + payload 产出的确定性 tarball。
- `fetchurl`：node / python-build-standalone / wheels，按上游
  `scripts/primary-runtime/lock.json` 的 sha256 预取。

hash 位置：`nix/payload.nix`（`monorepoDepsHash`）、`nix/runtime.nix`（`runtimeDepsHash`）。

## 共享 runtime 与 Home Manager 模块分工

桌面、终端 `dsh`、Web 共用同一份 `dsh-desktop-runtime` 输出（取舍见
[ADR 0001](adr/0001-one-runtime-three-surfaces.md)）。`dsh` 包只写一个 wrapper：

```
runtime/node --expose-internals dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js
```

因此 Web/CLI 的闭包不含 Electron/GTK；`nix/desktop.nix` 仍然只负责把 Electron 与
运行时树组装成桌面包。`desktop-host` CLI 的 `supportDir` 推导在 `dsh-desktop-runtime`
的兄弟目录布局（`dsh/` 与 `runtime/`）下天然成立，不需要桌面包里的 `resources/app/runtime`
符号链接。

Home Manager 拆成两个模块：

- `programs.dsh`（`homeModules.dsh`）：共享 `dshHome`、`environmentFiles`、`settings`/
  `patches`，写 `$DSH_HOME/cordis.patch.yml`，并安装带环境注入的 `dsh` wrapper。
- `programs.dsh-desktop`（`homeModules.default` / `homeModules.dsh-desktop`）：只负责
  Electron 包、launcher 与 desktop entry，import 共享模块并读取它的
  `dshHome`/`environmentFiles`；`programs.dsh.enable` 必须为 true。

这个拆分保证同一份 `cordis.patch.yml` 只有一个写入者；Web-only 主机只 import
`homeModules.dsh`，不需要桌面包。

## 确定性 tarball

`pnpm pack` 的条目顺序取决于文件系统 readdir 顺序，同一源码在本地检出与 Nix store 里
会得到不同字节，导致运行期 lockfile 的 `file:` 依赖 integrity 不稳定。
`nix/normalize-tarballs.sh` 在 `prepare:packages` 前把所有 tarball 重打包为
「条目排序 + 固定 mtime/owner + 权限归一（可执行 755，其余 644）+ 无 gzip 头」的确定性
字节；`nix/runtime/project/pnpm-lock.yaml` 基于这些字节生成。

## 运行期 lockfile

`nix/runtime/project/{package.json,pnpm-workspace.yaml,pnpm-lock.yaml,patches}` 由
`nix/gen-runtime-lock.ts` 生成：在 payload 产出的 `package-set` 上调用上游
`createRuntimeProjectMetadata` + `prepareRuntimePatches`，再 `pnpm install --lockfile-only`。
离线构建里 `patches/0002` 让 `prepare:dsh` 直接复制这份 lockfile，并以 `--offline`
从预取 store 安装。**不要手工编辑该 lockfile**，用 `scripts/update.sh` 重新生成。

## 更新流程

```sh
scripts/update.sh dsh-v0.2.3
```

联网只发生在 fetch 类 FOD 与更新检出中的 `pnpm install`。脚本先用 `nix develop` 把
node/pnpm/git/python3 固定到本仓库 flake.lock 的 nixpkgs（避免生成 lockfile 的 pnpm 版本
随宿主漂移），然后：改 flake 输入并 `nix flake update dsh-src` → 检出 tag、应用补丁、
安装依赖 → 构建 payload（必要时刷新 `monorepoDepsHash`）→ 重新生成运行期项目/lockfile →
刷新 `runtimeDepsHash` → 全离线重建 `dsh-desktop` 与 `dsh` 并打印 store 路径。失败时用 `trap`
回滚 `flake.nix`/`flake.lock`/两个 hash 文件/`nix/runtime`；成功时断言改动只落在
白名单路径内。

## Linux 适配补丁

见 `patches/`（linux target 白名单、`prepare:dsh` 用 runtime 官方 Node + 离线开关、
桌面壳 Host 使用 runtime Node、关窗即退出）。Electron 采用 `electron_44-bin` 的 dist：
nixpkgs `electron_44` 的 libexec dist 本机测试 GPU 进程启动失败（`GPU process isn't
usable`），而 `electron_44-bin` dist 与 Gate 0 spike 一致、可正常开窗。

## 已知限制

- `prepare:dsh` 的上游 release smoke 断言 Electron Node 语义，Linux 适配下用
  `--defer-runtime-smoke` 跳过；真实启动 + CLI/配置 dump 作为验收。
- 运行期树里的 node/python 是官方预编译产物，运行依赖 NixOS 的 `nix-ld`。
- 仅 x86_64-linux；不生成 asar。

## 验证记录（本机，2026-10-31，桌面阶段）

- `nix build .#dsh-desktop`（审计修复后）：`/nix/store/cgjp0qj5cw7mhdmw7nkz14m0scnknmp8-dsh-desktop-0.2.2-alpha.2`
  （Electron dist 与运行时树字节未改动；payload `/nix/store/js3qmi8j0xw7f3rv8wh36cjmgi9fhmzj-dsh-desktop-payload-0.2.2-alpha.2`）。
- 启动后 niri 窗口 `app_id=deepseek-harness`、标题 `DSH 本地构建`，Host 输出
  `dsh web: http://127.0.0.1:<port>/?token=...`；关窗后进程退出。
- 包内 CLI（runtime Node + desktop-host `cli.js`）`--version` = `0.2.2-alpha.2`。
- 运行期树 `desktop-runtime.json` 的 20928 个文件摘要通过上游校验；准备阶段 49s（离线）。
- `scripts/update.sh dsh-v0.2.2-alpha.2` 在全新检出 + 独立 Nix 构建上重跑：重新生成的
  `nix/runtime/project` 与 committed 版本 **零 diff**（确定性 tarball + lockfile 生成验证通过）。
- `nix flake show`：packages/overlay/homeModules/devShells/checks 输出齐全；
  `nixosConfigurations.home/laptop` 的 toplevel 可求值并已预构建。

## Web/CLI 阶段验证（2026-10-31）

- `nix build .#dsh` 成功，输出 `dsh-0.2.2-alpha.2`；`bin/dsh` 只引用
  `dsh-desktop-runtime` 的 `dsh/` + `runtime/`，闭包无 Electron。
- `bin/dsh --version` = `0.2.2-alpha.2`；`bin/dsh web --help` 正常列出 `--host/--port/
  --public-url/--trusted-host/--tls-cert/--tls-key`。
- `scripts/verify-web.sh` 用临时 `DSH_HOME` 启动 `dsh web --no-open --port 0`：
  token URL 返回 303，cookie 交换后首页返回 200，页面含注入的 `__DSH_BOOT__`。
- HM 渲染检查（dummy 包）确认 `programs.dsh` 生成 home patch、安装带 `DSH_HOME`/
  `environmentFiles` 的 `dsh` wrapper，`programs.dsh-desktop` 只生成 launcher/desktop entry。

## 模块独立消费验证（不依赖用户 nixos-config）

用一个临时 flake（nixpkgs + home-manager + 本仓库 path input）做 standalone HM 求值/构建：

- `home-manager.lib.homeManagerConfiguration` + `dsh-nix.homeModules.default` +
  `programs.dsh.enable = true` + `programs.dsh-desktop.enable = true`（dummy 包），构建
  `activationPackage` 成功；
- 生成 `home-files/.dsh/cordis.patch.yml`、`.local/bin/dsh-desktop`、
  `home-path/bin/dsh`、`.local/share/applications/deepseek-harness.desktop`；
- `home-path/bin/dsh` 是 HM 安装的共享 wrapper，指向 `programs.dsh.package`，并注入
  `DSH_HOME` 与 `environmentFiles`。

结论：公开模块 + overlay 可在用户配置之外独立工作；`nix flake check --no-build`
（packages/devShells/formatter/checks）也通过。

## 桌面阶段最终验收（2026-10-31）

- `laptop` 主机 `nixos-rebuild switch --flake .#laptop` 成功（system generation 更新）；
- `scripts/verify-desktop.sh` 全部 PASS：launcher/desktop entry（文件而非目录）、icon、
  home patch 及其 5 个 layer patch 被 dsh 配置层接受、permission presets 进入合成配置；
- 从应用启动器启动桌面端，窗口 `app_id=deepseek-harness`、Host 就绪并日常使用；
- 旧 CLI `dsh --version` 仍为 `0.2.2-alpha.2`（未被新包影响）。

## 质量门与 CI（retro 之后）

- `checks.hm-module`：用 dummy package 构建 standalone Home Manager 配置，断言
  `programs.dsh` 生成 home patch、`dsh` wrapper 注入环境、desktop entry 是普通文件
  （本次真实 bug 的回归）、launcher 指向；不构建 1.3G 运行时。
- `checks.hm-module-negative`：用 `builtins.tryEval` 断言带 `ui-onboarding`/`welcomeNoticeVersion`
  的配置必须 eval 失败（带正向 control，防止误报）。
- `checks.scripts`：shellcheck + `bash -n` + `nixfmt --check`。
- `checks.runtime-lockfile`：lockfile 无 registry URL；`patchedDependencies` 与
  `nix/runtime/project/patches/*.patch` 的 sha256 一致。
- `checks.dsh` / `checks.dsh-desktop`：重包构建检查（`nix flake check` 会求值/构建；
  CI 不跑）。
- `scripts/check.sh`：本地/CI 统一入口（可执行位、shellcheck、nixfmt、`nix flake check --no-build`、
  三个轻量 check、`verify-desktop.sh --self-test`）；`--full` 才构建 `dsh`/`dsh-desktop`，
  断言 `dsh` 闭包无 Electron，并跑 `verify-web.sh`。
- `.github/workflows/ci.yml`：push/PR 跑 `bash scripts/check.sh`。
- `AGENTS.md`：导航与不变量（离线/FOD、dontFixup 字节保护、生成物不可手改、共享 runtime、
  手动 web、工具链、用户切换+验收）。
