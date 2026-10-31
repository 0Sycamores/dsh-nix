# 切换与验收清单（Gate 2 人工部分）

> 桌面阶段验收记录：2026-10-31，`laptop` 主机 `nixos-rebuild switch --flake .#laptop` 后
> `scripts/verify-desktop.sh` **全部 PASS**；桌面端已从应用启动器正常启动并日常使用
> （窗口 `app_id=deepseek-harness`、Host 就绪、home patch 5 层生效）。
>
> **Web/CLI 阶段（2026-10-31）已删除旧 `pkgs/dsh`**：终端 `dsh` 现由
> `programs.dsh` + 新 `packages.dsh` 提供；下面的 1–8 是桌面阶段的历史记录，其中
> “旧 CLI 不受影响”已不再适用。Web 阶段验收见文末。

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

## Web/CLI 阶段（2026-10-31）

### nixos-config 接线

- 删除本地自封装 `pkgs/dsh` 与 `sycamore.dsh`；终端 `dsh` 改由 `programs.dsh` 提供。
- `modules/development/dsh.nix`：overlay + `programs.dsh.{enable,environmentFiles,settings}`；
  home 主机另设 `home-manager.sharedModules = [ homeModules.dsh ]`，不装桌面包。
- `modules/development/dsh-desktop.nix`：只设 `programs.dsh-desktop.enable`，并 import
  `homeModules.default`（桌面模块内部 import 共享模块）；laptop 同时启用两者。
- 声明式 settings 从 `programs.dsh-desktop.settings` 迁到 `programs.dsh.settings`。
- 本地提交：`dsh-nix` `af63669`（已 push）；`nixos-config` `c20142f`（未 push）。

切换：

```sh
cd ~/.nixos-config
sudo nixos-rebuild switch --flake .#laptop   # laptop（桌面 + CLI/Web）
sudo nixos-rebuild switch --flake .#home     # home（仅 CLI/Web；在 home 上执行）
```

### 构建/自动验收（在仓库内）

```sh
nix build .#dsh
result/bin/dsh --version
bash scripts/verify-web.sh --package "$(nix build .#dsh --no-link --print-out-paths)"
bash scripts/check.sh --full
```

`verify-web.sh` 用临时 `DSH_HOME` 启动 `dsh web --no-open --port 0`，断言 token URL 的
303、cookie 交换后的 200、页面含 `__DSH_BOOT__`；不碰真实 `~/.dsh`。

### home 手动 Web 验收

```sh
tmux new -As dsh-web 'dsh web --no-open --host "$(tailscale ip -4)" --port 3080'
# 复制打印出的 token URL，在 laptop 浏览器打开
```

1. 页面加载，发一条消息，确认模型与 bash 工具可用。
2. `ss -ltnp | grep 3080` 只显示 `<tailnet-ip>:3080`，没有 `0.0.0.0` / `[::]`。
3. 重启 web 后旧 token URL 失效；重新拿新 URL，历史会话仍在。
4. laptop 桌面端正常；桌面与 web 同时运行时，同一会话只在一个 surface 打开
   （另一个会提示 "This session is already in use…"）。

### 回滚

```sh
sudo nixos-rebuild switch --rollback
```

回滚到上一个 generation 会恢复旧 `pkgs/dsh`；`~/.dsh` 数据不受影响。

### 验收记录

实现侧（2026-10-31，本机）：

- `nix build .#dsh`：`/nix/store/1s5b13ycfmcnda5ivg5hw9632ihj17b3-dsh-0.2.2-alpha.2`；
  `bin/dsh --version` = `0.2.2-alpha.2`；闭包无 Electron。
- `scripts/verify-web.sh`：token URL 303 → cookie 后 200，页面含 `__DSH_BOOT__`。
- 非 loopback 绑定预演（laptop 的 tailnet IP `100.64.0.3`）：`--host 100.64.0.3` 正常监听，
  打印的 URL 用该 IP，token 303 / cookie 200，页面含 boot manifest；同时出现上游的
  “plain HTTP; restrict this port” 警告（预期）。
- 用真实 `~/.dsh/cordis.patch.yml` 的临时副本跑 `--profile web --dump-config`：5 个 layer
  patch 命中，`permission`/`agent-default-model`/`agent-preset-registry`/`llm-pi-ai`/
  `ui-settings-general` 均在合成配置里，`danger-full-access` 生效。
- `scripts/check.sh --full`：desktop/dsh 构建、闭包断言、web smoke 全 PASS。
- home/laptop 的 `nixosConfigurations.*.system.build.toplevel` 均已构建；home HM 生成
  只有 `dsh`，laptop 有 `dsh` + `dsh-desktop` + desktop entry。

切换侧（2026-10-31 13:55，laptop 已完成）：

- [x] laptop 切换完成：`/run/current-system` =
  `maxih9gjnrnill9wqijwfi111hzxxdl9-nixos-system-laptop-…`；
  `/etc/profiles/per-user/sycamore/bin/dsh` → `lz66ps3f6smpyxiay9pvl1f0z4lh75hb-dsh/bin/dsh`，
  `dsh --version` = `0.2.2-alpha.2`。
- [x] `scripts/verify-desktop.sh` **ALL CHECKS PASSED**：新桌面包
  `4ji19qaq6a6spbdd88q54jqb152b4qjh-dsh-desktop-0.2.2-alpha.2` 的 launcher/entry/icon/
  home patch 均正确；home patch 5 个 layer 命中，`danger-full-access` 生效。
- [x] `scripts/verify-web.sh`：token URL 303 → cookie 200，`__DSH_BOOT__` 存在。
- [x] 新桌面包实际开窗：2026-10-31 14:18 用户重启桌面端，运行中的 Electron/Host
  已是 `4ji19qaq…-dsh-desktop-0.2.2-alpha.2`，`verify-desktop.sh` 再次 ALL PASSED。
- [x] laptop tailnet Web surface：手动起在 `100.64.0.3:3080`，token 303 → cookie 200，
  `__DSH_BOOT__` 存在；浏览器内的真实对话验收见下一条。
- [x] 预览版说明无法继续（已修复）：home patch 的
  `ui-settings-general.welcomeNoticeVersion` 还是 `2026-08-13.1`，而 0.2.2-alpha.2 的
  `WELCOME_NOTICE_VERSION` 是 `2026-09-28.1`；home 层优先级高于 UI 写入，所以
  Continue 报“暂时无法保存确认状态”。已在 nixos-config `7ab0e6a` 把声明值更新为当前版本，
  构建出新的 HM patch，并临时把 `~/.dsh/cordis.patch.yml` 指向它后重启 Web；模态框消失，
  输入框可用。下次 `nixos-rebuild switch` 会永久生效。
- [ ] laptop Web 浏览器对话：用户打开 token URL 并完成一次模型/bash 往返（进行中）。
- [ ] home 切换与手动 Web：用户明确「home 先不着急」，暂缓。home 当前仍是旧
  generation（`df24z8…`，2026-09-29），`nixos-config` checkout 在 `04da93b`。
  laptop 主分支已合并 home 的本机提交并包含 pki 修复（当前 `7ab0e6a`），只差
  `git push origin main`；home 需要 `git pull --ff-only` 后由用户执行
  `sudo nixos-rebuild switch --flake .#home`（sudo 需要密码）。
- home 构建曾遇到一个与本仓库无关的 `nss-cacert` 失败：home 的
  `modules/core/pki.nix` 把 NSS 3.131.1 已从 certdata 移除的
  `emSign ECC Root CA - G3` 写进 `security.pki.caCertificateBlacklist`，导致
  `buildcatrust` 报 “blocklist 中的证书不存在”。已在 `merge-home` 的 `4bcd859`
  移除该条；修复后 home 与 laptop 的 `system.build.toplevel` **均构建成功**。
  合并/切换命令（laptop 的 `main` 已包含 `4bcd859` 与 `7ab0e6a`，只需推送）：

  ```sh
  # laptop
  cd ~/.nixos-config
  git push origin main

  # home（用户执行）
  cd ~/.nixos-config && git pull --ff-only
  sudo nixos-rebuild switch --flake .#home
  ```
