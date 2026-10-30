# 上游审计摘要（基线 `dsh-v0.2.2-alpha.2`）

从可行性调研阶段压缩而来的关键事实，用于解释本仓库的适配决策。关键结论先后在 Gate 0/1/2 验证。

## 发布形态

- 上游 monorepo 用 pnpm workspace + TypeScript；官方桌面端只发 macOS / Windows（`apps/desktop/scripts/desktop-build-paths.mjs` 白名单无 linux）。
- 桌面产物 = Electron 外壳（`apps/desktop`）+ 生产运行时树（`apps/desktop-host` CLI 包 + `dsh` npm 包 + 依赖）+ primary runtime 载荷（官方 Node、python-build-standalone、wheels、pnpm）。
- 运行时树由 `prepare:dsh` 物化，自带 `desktop-runtime.json`（逐文件 sha256 + 可执行位 + 发布版本）；写入后不可再改字节，否则 Host 拒绝启动。
- 打包目录：`resources/app/{lib,renderer,package.json,dsh/,node_modules/,runtime→../runtime}`、`resources/runtime/`、`resources/icon.png`；官方用 plain `app` 目录（非 asar）。

## 与 Linux 打包相关的上游行为

- `app.isPackaged` 由 Electron 按**可执行文件名**判定；打包必须把 `electron` 改名为产品名，否则 shell 走开发路径。
- 官方 Host 用 `process.execPath`（Electron）配 `ELECTRON_RUN_AS_NODE=1` 运行；其中 `node-addon-require-builtin` 只接受
  官方 Node 与白名单内的 Electron 指纹（43.0.0 / 44.0.0 / 44.7.0 / 45.0.0-alpha.6）。nixpkgs Electron 44.9.3 不在白名单，
  因此本仓库让 Host/CLI 跑在 runtime 自带的官方 Node 上（补丁 0002/0003）。
- Host 的 supportDir 推导假设 asar 布局（`runtimeArchivePath`），plain 目录需要 `resources/app/runtime` 符号链接补齐。
- 设置层：bundle 层 → profile 的 `cordis.patch.yml` → **home 层 `$DSH_HOME/cordis.patch.yml`** → `--patch`。
  home 层对所有 profile 生效，适合声明式配置；上游不存在 `settings.yaml` 的现代等价物，旧键名（如 `ui-onboarding`）
  有迁移表（→ `ui-settings-general`）。
- `dsh --profile desktop` 的启动/dump 被拒绝（profile 由 Electron 应用独占管理），声明式验收要走 home patch + 应用内/宿主侧验证。
- 数据模型：共享 `$DSH_HOME`（默认 `~/.dsh`，`DSH_HOME` 可覆盖），桌面 profile 为 `profiles/desktop`；插件在 profile 内 pnpm 管理。
- Office 能力依赖运行时树里的 python / LibreOffice 资产；技能资产随 npm 包分发。

## 许可证与品牌

- 上游为 MIT；本仓库 MIT。Electron、Node、python-build-standalone、各 npm 依赖按其自身许可证分发（见 NOTICE）。
- 产品名与图标沿用官方素材；本仓库明确标注"个人自用、非官方"，不提供官方支持，也不发布到任何应用商店。
