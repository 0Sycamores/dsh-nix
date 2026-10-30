# 独立审计与处理记录

审计对象：`dsh-nix`（Gate 3 前状态，HEAD 8d4faf3）。只读审计，覆盖 flake 输出、三个派生、
运行期 lockfile 生成、更新脚本、HM 模块、补丁、文档与许可。结论：**无 P0**；P1 10 项、P2 14 项。
本节记录处理结果（对应提交 `fix: apply independent audit findings (P1/P2)`）。

## P1 处理

| # | 发现 | 处理 |
|---|---|---|
| 1 | `GIO_EXTRA_MODULES` 指向 `${dconf}` 而非拆分后的 `dconf.lib`，模块不存在 | 改为 `${lib.getLib dconf}/lib/gio/modules`，已对照 nixpkgs electron wrapper 验证 |
| 2 | README 的 HM 示例缺 overlay，照抄会因 `pkgs.dsh-desktop` 缺失而 eval 失败 | README 拆成 NixOS 侧（overlay）与 HM 侧示例，并给出显式 `package` 替代 |
| 3 | patch 行是**整行替换 config**，示例 `permission.defaultPreset` 会静默丢掉 base presets | 模块 option 文档写明替换语义；README/HM 接线补全 `permission.presets` 与 `agent-preset-registry.default` |
| 4 | 旧 settings 迁移表仅 1/3 | 补齐 `ui-developer-tools → ui-settings`、`shell → bash-sandbox`（Linux） |
| 5 | README 缺 nix-ld 前置条件 | README 明确：官方 runtime Node/Python 需要 `programs.nix-ld.enable`，Electron dist 不需要 |
| 6 | `update.sh` 依赖宿主 python3，`nix shell nixpkgs#…` 未用 flake.lock | 脚本先 `nix develop` 固定工具链（devShell 含 node/pnpm/git/python3）再执行 |
| 7 | `update.sh` 失败无回滚，`refresh_hash` 可能留下错误 hash | 加 `trap`：失败时回滚 `flake.nix`/`flake.lock`/hash 文件/`nix/runtime` |
| 8 | `update.sh` 在 git 中非可执行 | 改为 100755 |
| 9 | `payload/src` 保留嵌套 `node_modules` → 584 个悬空符号链接 | tar 排除任意层级 `node_modules`；重建后 dangling=0、无嵌套 node_modules |
| 10 | 过渡期共享 `~/.dsh` 与旧 CLI 冲突（首个桌面启动会 rename 导入旧 `settings.yaml`） | README 与验收文档写明：过渡期不要反复交替运行旧 CLI 与桌面端，必要时给旧 CLI 单独 `DSH_HOME` |

## P2 处理（择要）

- 删除无消费者的 `nix/runtime/pnpm-lock.yaml`（只保留 `nix/runtime/project/pnpm-lock.yaml`）。
- devShell 与交付物统一 `electron_44-bin`；补 `gnutar/gzip`。
- desktop 派生补 `meta`（license/platforms/mainProgram/sourceProvenance）。
- `dsh-src.rev` 在本地覆盖输入场景下可能为 null：给全 0 回退，客户端构建元数据仍合法。
- `install-payload.sh` 排除 `.dsh-nix-*` 引导脚本。
- `normalize-tarballs.sh` 条目列表改为 NUL 安全（`mapfile -d ''`）。
- `update.sh` 增加工件目录守卫（必须位于仓库内）、结尾改动白名单断言、移除未用 jq。
- `environmentFiles` 注入改用 `lib.escapeShellArg`；`dshHome` 断言排除等于家目录；
  settings/patches 重复 id 断言；`force = true` 语义注释。
- README 指明推荐入口（桌面 entry / `~/.local/bin/dsh-desktop`，会 source 环境文件）。
- 文档修正 FOD 数量口径（2 个 pnpm FOD + 13 个 fetchurl 资产）、Gate 验证范围措辞。

## 未处理（记录在案）

- overlay 仍钉死 `electron_44-bin`/`nodejs_24`/`pnpm_11` 属性：换到不含这些属性的旧/新 nixpkgs
  会 eval 失败。属预期的兼容窗口问题，文档注明目标 nixpkgs（nixpkgs-unstable @ e62746b0）。
- `checks` 只构建桌面包，未引入 home-manager input 做模块求值检查（避免额外重量级输入）。
- X11 桌面关联未验证：已把 desktop entry 文件名改为 `deepseek-harness.desktop`、
  `StartupWMClass`/`CHROME_DESKTOP` 统一为 `deepseek-harness`，与实测 Wayland `app_id` 一致；X11 下未测。
- 未重跑完整 `update.sh` 的失败路径（仅验证成功路径零 diff 与静态审阅）。

## 切换后实测补充修复

- 首次 `nixos-rebuild switch` 后验收发现 `~/.local/share/applications/deepseek-harness.desktop`
  是指向 **目录** 的符号链接（`makeDesktopItem` 的输出是 `share/applications/...` 目录树）。
  已改为 `source = "${desktopItem}/share/applications/deepseek-harness.desktop"` 指向文件本身。
- 验收脚本改为优先读取系统实际安装的 `dsh-desktop`（NixOS HM 默认装到
  `/etc/profiles/per-user/<user>`），icon 检查同时覆盖包路径与用户 profile。

## Retro 后续（2026-10-31）

根据本次 build 的 retrospective，新增确定性门禁而不是更多文字规则：

- `checks.hm-module`（dummy package）覆盖“desktop entry source 指向目录”这类只在切换后暴露的 bug；
- `checks.scripts` / `checks.runtime-lockfile` 覆盖 shellcheck、格式化、lockfile 与 patch hash 不变量；
- `scripts/check.sh` + `.github/workflows/ci.yml` 提供本地与 CI 共用的廉价门禁；
- `scripts/verify-desktop.sh --self-test` 用夹具回归验收脚本自身的路径/断言逻辑；
- `AGENTS.md` 记录导航指针与不变量（IFD、pipefail、pkill 自身、host 判断等 gotchas）。
