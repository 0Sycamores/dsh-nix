# 验收与切换（当前）

桌面阶段的历史记录在
[docs/history/2026-10-31-desktop-acceptance.md](history/2026-10-31-desktop-acceptance.md)。
当前阶段是 Web/CLI；桌面仍用 `scripts/verify-desktop.sh`，Web 用
`scripts/verify-web.sh` 或 `scripts/serve-web.sh`。

## Web/CLI 阶段（2026-10-31）

### nixos-config 接线

- 删除本地自封装 `pkgs/dsh` 与 `sycamore.dsh`；终端 `dsh` 改由 `programs.dsh` 提供。
- `modules/development/dsh.nix`：overlay + `programs.dsh.{enable,environmentFiles,settings}`；
  home 主机另设 `home-manager.sharedModules = [ homeModules.dsh ]`，不装桌面包。
- `modules/development/dsh-desktop.nix`：只设 `programs.dsh-desktop.enable`，并 import
  `homeModules.default`（桌面模块内部 import 共享模块）；laptop 同时启用两者。
- 声明式 settings 从 `programs.dsh-desktop.settings` 迁到 `programs.dsh.settings`。
- 本地提交：`dsh-nix` 已 push；`nixos-config` 当前 `aeb1657` + lock `e9c9f55`（未 push）。

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
- [x] 预览版说明无法继续（已修复，方案改为不声明）：home patch 曾固定
  `ui-settings-general.welcomeNoticeVersion = 2026-08-13.1`，而运行时要求
  `2026-09-28.1`；home 层优先级高于 UI 写入，Continue 报“暂时无法保存确认状态”。
  nixos-config `aeb1657` 删除该声明，并让 `programs.dsh` 断言禁止再声明
  `ui-onboarding` / `welcomeNoticeVersion`；确认状态改由 UI 自己持久化。删除后的
  HM patch 已构建确认不含该行；下次 switch 后首次会看到一次说明，点 Continue 即可。
  临时用当前版本 patch 的浏览器对话已验收（见下一条），但“无声明 + UI 持久化”还需
  在下次 switch 后点一次 Continue 复核。
- 临时状态：`~/.dsh/cordis.patch.yml` 目前指向新构建的 HM generation
  （`/nix/store/rn879…-home-manager-generation/home-files/.dsh/cordis.patch.yml`，不含
  welcome 行），不属于当前 `/run/current-system`。下次 `nixos-rebuild switch` 会把它
  归一到新 generation；不要把这个 symlink 当成系统状态的一部分。
- [x] laptop Web 浏览器对话：用户在新标签页发送 `pwd`；Host 调用 bash 工具，返回
  `/home/sycamore/Projects/dsh-nix`，assistant 复述该路径并完成 turn（session
  `f85071c5…`，2026-10-31 14:31）。测试用 Web surface 已停止（3080 关闭）。
- [ ] home 切换与手动 Web：用户明确「home 先不着急」，本轮暂缓（不算失败）。home 当前仍是旧
  generation（`df24z8…`，2026-09-29），`nixos-config` checkout 在 `04da93b`。
  laptop 主分支已合并 home 的本机提交并包含 pki 修复与 welcome 删除（当前 `aeb1657`/`e9c9f55`），只差
  `git push origin main`；home 需要 `git pull --ff-only` 后由用户执行
  `sudo nixos-rebuild switch --flake .#home`（sudo 需要密码）。
- home 构建曾遇到一个与本仓库无关的 `nss-cacert` 失败：home 的
  `modules/core/pki.nix` 把 NSS 3.131.1 已从 certdata 移除的
  `emSign ECC Root CA - G3` 写进 `security.pki.caCertificateBlacklist`，导致
  `buildcatrust` 报 “blocklist 中的证书不存在”。已在 `merge-home` 的 `4bcd859`
  移除该条；修复后 home 与 laptop 的 `system.build.toplevel` **均构建成功**。
  合并/切换命令（laptop 的 `main` 已包含 `4bcd859`、`7ab0e6a`、`aeb1657` 与 `e9c9f55`，只需推送）：

  ```sh
  # laptop
  cd ~/.nixos-config
  git push origin main

  # home（用户执行）
  cd ~/.nixos-config && git pull --ff-only
  sudo nixos-rebuild switch --flake .#home
  ```
