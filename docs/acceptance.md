# 切换与验收清单（Gate 2 人工部分）

## nixos-config 接线（已提交到本地仓库，未推送）

改动：

- `flake.nix`：新增 input `dsh-nix`（`follows nixpkgs`）。
- `modules/development/dsh-desktop.nix`：overlay + `home-manager.sharedModules` +
  `programs.dsh-desktop`（sops 环境文件、声明式 settings）。
- `modules/development/dsh.nix`：`sycamore.dsh.settings` 迁移到新模块，旧 CLI 的环境/持久化不动。
- hosts `home` / `laptop` 均已 import 新模块。

切换（当前运行的是 laptop 主机；home 服务器用 `.#home`）：

```sh
cd ~/.nixos-config
sudo nixos-rebuild switch --flake .#laptop   # home 用 .#home
```

首次构建约 7–10 分钟（payload 离线构建），之后走缓存。toplevel 已预构建验证过。

## 切换后验收

自动化部分（本仓库已验证）：`packages.dsh-desktop` 可启动、窗口与 Host 就绪、关窗退出、
包内 CLI `--version` 正常、home patch 在 `--dump-config` 中逐层命中。

切换后先跑自动验收（不启动 GUI、不写真实 DSH_HOME）：

```sh
bash scripts/verify-desktop.sh
```

它检查 HM 生成的 launcher/desktop entry/home patch，并用打包 CLI 确认声明式设置被 dsh
配置层接受（`patched by ~/.dsh/cordis.patch.yml`、permission preset 进入合成配置）。

然后手动检查：

1. **桌面入口**：应用启动器搜 "DeepSeek Harness"，或运行 `~/.local/bin/dsh-desktop`。
   desktop entry 为 `~/.local/share/applications/deepseek-harness.desktop`，其 id 与
   Wayland `app_id=deepseek-harness` 一致；窗口标题应为 `DSH 本地构建`。
2. **日志**：`~/.config/DeepSeek Harness/logs/`；主进程 stdout 里应有
   `dsh web: http://127.0.0.1:<port>/?token=...`（Host 就绪）。
3. **凭据**：sops 渲染的 `dsh_env` 由启动器 source（`SYCAMORE_API_KEY` / `DEEPSEEK_API_KEY`）；
   欢迎页"开始设置"里确认模型路由可用。
4. **任务**：新建/选择工作区 → 发一条消息 → 确认 bash 工具能执行并回传。
5. **终端面板**：打开终端，`pwd` / `ls` 正常。
6. **Office**：生成或打开一个表格/csv，确认读写往返。
7. **声明式设置**：`cat ~/.dsh/cordis.patch.yml` 应含
   `agent-default-model`、`permission`、`llm-pi-ai`、`ui-settings-general` 等行；
   用包内 CLI 复核：

   ```sh
   RT=~/.nix-profile/share/dsh-desktop/node/bin/node  # 以实际包路径为准
   # 或：nix shell github:0Sycamores/dsh-nix -c dsh-desktop --version
   ```

   最可靠的是 `nix eval` 后的 store 路径：
   `${dsh-desktop}/lib/dsh-desktop/resources/runtime/primary-runtime/dependencies/node/bin/node`
   加 `resources/app/dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/cli.js`，
   `--profile web --dump-config` 检查 `patched by ~/.dsh/cordis.patch.yml`。
8. **旧 CLI 不受影响**：`dsh --version` 仍是 `0.2.2-alpha.2`（旧 pkgs/dsh 提供，`cli.enable=false`）。

## 回滚

```sh
sudo nixos-rebuild switch --rollback
```

或 revert nixos-config 的接线提交；`~/.dsh` 数据与旧 CLI 均不受影响。

## 已知限制（验收时可接受）

- 无托盘、无自动更新、无开机自启；关窗即退出（Linux 适配）。
- Host/CLI 跑 runtime 自带官方 Node，依赖系统 `nix-ld`（已启用）。
- 上游 release smoke 在构建中跳过，真实启动与上述手动项替代。
- 仅 x86_64-linux / Wayland 验证；X11 未验证。
