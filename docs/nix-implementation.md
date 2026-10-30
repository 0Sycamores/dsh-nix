# 密封离线 Nix 构建（Gate 1）

## 结构

两个正常派生 + 两个 pnpm 依赖 FOD（`fetchPnpmDeps`）+ 13 个 `fetchurl` 资产 FOD，构建阶段不联网：

| 派生 | 作用 |
|---|---|
| `dsh-desktop-payload` | 上游 monorepo 离线安装（`fetchPnpmDeps`）、`build --profile local`、打四个 tarball、`prepare:packages`、`pnpm deploy` 取外壳生产依赖；产出 `desktop/`、`package-set/`、`shell-node-modules/` 和**已构建源码树** `src/` |
| `dsh-desktop-runtime` | 以 payload 的 `src/` 为源码，离线安装 workspace 依赖；把预取的 primary-runtime 资产（node/python/wheels）填进上游 sha256 缓存；`prepare:dsh --defer-runtime-smoke` 用**仓库里提交的 runtime lockfile** + 预取 pnpm store 离线物化 `dsh` 运行时树 |
| `dsh-desktop` | 纯组装：Electron dist + payload/运行时树 + 启动器；`dontFixup` 保证逐文件摘要的运行时树与 Electron dist 字节不变 |

FOD：

- `dsh-monorepo-deps`：monorepo `pnpm-lock.yaml` 的 pnpm store（`fetchPnpmDeps`, fetcherVersion 5）。
- `dsh-desktop-runtime-deps`：运行期项目 lockfile 的 pnpm store；`src` 是
  `nix/runtime/project/` + payload 产出的确定性 tarball。
- `fetchurl`：node / python-build-standalone / wheels，按上游
  `scripts/primary-runtime/lock.json` 的 sha256 预取。

hash 位置：`nix/payload.nix`（`monorepoDepsHash`）、`nix/runtime.nix`（`runtimeDepsHash`）。

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
刷新 `runtimeDepsHash` → 全离线重建 `dsh-desktop` 并打印 store 路径。失败时用 `trap`
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

## 验证记录（本机，2026-10-31）

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
