# 桌面端构建（Gate 0 结论）

- 基线：`dsh-v0.2.2-alpha.2`（`f3803c96974ad4a94195fb97e5c637e9c2a3afe3`）
- 状态：**Gate 0 通过**。上游载荷 + nixpkgs Electron 组装出的打包布局可启动：窗口渲染、
  Host 就绪、关窗退出均验证通过。Gate 1 的 Nix 实现以本文档为准。

## 载荷流水线（在 tag worktree 上实测）

1. `pnpm install --frozen-lockfile`
2. `pnpm run build --profile local`（10/10 gates，产生 client build record）
3. `pnpm --dir apps/desktop run build`
4. 打 tarball（目标目录必须传**绝对路径**，否则相对 package 目录落错位置）：
   - `pnpm exec tsx apps/desktop/scripts/pack-local-packages.ts --out <abs>/packed/dsh`
   - `pnpm --dir apps/desktop-host pack --pack-destination <abs>/packed/dsh`
   - `pnpm run release:pack --family vendor --out <abs>/packed/vendor`
   - `pnpm --dir native/system run build:ts`
   - `pnpm --dir native/system/packages/entry pack --pack-destination <abs>/packed/landlock`
5. primary runtime：allowlist 补丁后调用 `preparePrimaryRuntime()`；随后补
   `runtime/bin`（`apps/desktop/scripts/node-bin`）与 `runtime/versions.json`
   （`node` 取 runtime manifest 的官方 Node 版本，`pnpm` 取 runtime manifest）
6. `pnpm --dir apps/desktop run prepare:packages`
7. `pnpm --dir apps/desktop run prepare:dsh -- --defer-runtime-smoke`
8. shell 生产依赖：`pnpm --filter @deepseek-ai/dsh-desktop deploy --prod --ignore-scripts <dir>`

## 关键适配（`patches/`）

| 补丁 | 内容 |
|---|---|
| `0001-desktop-build-paths-linux.patch` | 目标白名单加 `linux-x64` 与平台映射 |
| `0002-prepare-dsh-runtime-node.patch` | Linux 用 runtime 自带官方 Node 运行 pnpm 与冒烟；安装脚本关闭（`--ignore-scripts`） |
| `0003-linux-desktop-adaptations.patch` | Linux 打包版 Host 用 runtime 官方 Node；关窗即退出（无托盘） |

不做补丁的部分：Electron 版本与 `require-builtin` 白名单冲突，改为 Host 不跑在 Electron 里。

## 结论性发现

1. **Electron 版本 → Host 运行时**：nixpkgs `electron_44` = 44.9.3，而 `require-builtin` 的
   Electron 指纹白名单只有 `43.0.0 / 44.0.0 / 44.7.0 / 45.0.0-alpha.6`，Host 跑在
   Electron-as-Node 下会报 `unsupported Electron runtime fingerprint`。方案：**Host 用 runtime
   自带的官方 Node（24.21.0）**，Electron 只负责外壳。
2. **`app.isPackaged`**：Electron 以可执行文件名判定；打包必须把 `electron` 二进制改名为
   `dsh-desktop`，否则 `app.isPackaged=false`，shell 进入开发路径并报
   `DSH_DESKTOP_PRIMARY_RUNTIME_DIR is required for an unpackaged launch`。
3. **安装脚本**：`koffi` 安装脚本在无 cmake 时失败；运行时项目统一 `--ignore-scripts`，
   原生依赖使用包内 prebuild（koffi 的 linux-x64 prebuilt 在官方 Node 下可正常加载）。
4. **布局**：plain `resources/app`（不使用 asar）。`resources/app/dsh` 自带
   `desktop-runtime.json`（逐文件 sha256 + 可执行位），写入后不可再改字节；
   `resources/app/runtime` 符号链接指向 `../runtime`（`dsh-desktop-host` CLI 的 supportDir
   推导假设 asar 布局，用符号链接补齐）。
5. **冒烟**：`prepare:dsh` 的 release smoke 断言 Electron Node 语义，Linux 适配下用
   `--defer-runtime-smoke` 跳过，改由真实启动 + 后续验收脚本验证。
6. **GTK 环境**：Electron dist 自身不带 GTK/GIO wrapper 环境；Nix 用 `wrapGAppsHook3`
   提供（spike 手动导出等价的 `GIO_EXTRA_MODULES`/`GDK_PIXBUF_MODULE_FILE`/`XDG_DATA_DIRS`，
   并为 Electron 侧原生模块补 `LD_LIBRARY_PATH` 指向 `libstdc++`）。
7. **终端 CLI**：`resources/app/dsh/.../dsh-desktop-host/lib/cli.js` 用 runtime Node 可运行完整
   dsh CLI（`--version` 正常）；但 `--profile desktop` 的启动/dump 会被拒绝
   （`profile "desktop" is managed exclusively by the Electron application`），
   声明式设置不能靠 `--dump-config` 验证，需落到 home patch + 应用内/宿主文件验证。

## Gate 0 验证证据

- 打包布局启动后 niri 窗口：`app_id=deepseek-harness`，标题 `DSH 本地构建`，欢迎页正常渲染。
- 日志出现 `dsh web: http://127.0.0.1:<port>/?token=…`，Host 就绪。
- 关闭窗口后进程退出（关窗=退出适配生效）。
- 内置 CLI `--version` = `0.2.2-alpha.2`。

## 待 Gate 2 验证

- 声明式 home patch（`~/.dsh/cordis.patch.yml`）对 desktop profile 生效方式。
- 交互验收：API Key、工作区、bash 任务、终端、Office 往返。
- 桌面入口/图标/环境文件注入。

## Gate 2：Home Manager 与声明式设置（已验证部分）

- `programs.dsh-desktop` 生成 `~/.dsh/cordis.patch.yml`（home 层），`settings` 的键按 patch 行 id
  写入，`ui-onboarding` 等旧键名按上游迁移表重映射（→ `ui-settings-general`）。
- 用打包后的 CLI 对真实 config 做 `--profile web --dump-config` 验证：5 个 layer patch 全部
  命中（`patched by .../cordis.patch.yml`），`permission.defaultPreset`、
  `agent-default-model`、`llm-pi-ai`、`ui-settings-general` 的声明值出现在合成配置中，无 skipped patch。
- `environmentFiles`（sops 渲染的 `dsh_env`）由启动器在 exec 前 source；`DSH_HOME` 固定为
  `~/.dsh`（与终端 dsh 共享）。
- nixos-config 已接入：`dsh-nix` input（follows nixpkgs）、overlay + `home-manager.sharedModules`、
  `modules/development/dsh-desktop.nix`；旧 `sycamore.dsh.settings` 迁移到 `programs.dsh-desktop.settings`，
  旧 CLI 的持久化/环境文件保持不动，`cli.enable = false` 过渡。
- 待用户执行 `nixos-rebuild switch` 后完成：桌面入口启动、真实 `~/.dsh` 下的欢迎/设置验收。
