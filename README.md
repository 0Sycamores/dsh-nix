# dsh-nix

DSH 桌面端（DeepSeek Harness desktop shell）的 Nix/NixOS 打包 —— **个人自用、非官方**。

- 基线：`dsh-v0.2.2-alpha.2`
- 目标：NixOS / x86_64-linux / Wayland
- 状态：Gate 0/1/2/3 代码与文档完成；切换命令与验收步骤见 [docs/acceptance.md](docs/acceptance.md)
- 许可：MIT（见 [LICENSE](LICENSE)、[NOTICE](NOTICE)）

## 用法

```sh
nix build github:0Sycamores/dsh-nix#dsh-desktop   # 或本地 `nix build .#dsh-desktop`
nix run   .#dsh-desktop                            # 直接启动（调试）
```

这是**未封装的上游载荷**：Electron 外壳 + 官方 dsh 生产运行时树。数据目录默认 `~/.dsh`
（与终端 dsh 共享；桌面 profile 为 `profiles/desktop`）。

依赖：官方预编译的 runtime Node/Python 依赖 NixOS 的 `nix-ld`（`programs.nix-ld.enable = true;`）；
Electron dist 已由 nixpkgs 打好补丁，不需要 nix-ld。

NixOS 侧（主机配置）：

```nix
{
  inputs.dsh-nix.url = "github:0Sycamores/dsh-nix";

  # 让 `pkgs.dsh-desktop` 可用；也可以不用 overlay，改为在 HM 里显式设置
  # `programs.dsh-desktop.package = inputs.dsh-nix.packages.${system}.dsh-desktop;`。
  nixpkgs.overlays = [ inputs.dsh-nix.overlays.default ];
  home-manager.sharedModules = [ inputs.dsh-nix.homeModules.default ];
  programs.nix-ld.enable = true;
}
```

Home Manager 侧：

```nix
programs.dsh-desktop = {
  enable = true;
  environmentFiles = [ "/run/secrets/rendered/dsh_env" ];

  # 注意：patch 行是“整行替换该 id 的 config”，必须写全需要的键。
  settings = {
    agent-default-model = {
      provider = "sycamore";
      model = "deepseek-v4.1-flash";
      reasoningEffort = "max";
    };
    permission = {
      defaultPreset = "danger-full-access";
      presets = {
        read-only = { sandbox = "read-only"; approval = "ask"; };
        workspace-write = { sandbox = "workspace-write"; approval = "ask"; };
        danger-full-access = { sandbox = "danger-full-access"; approval = "never"; };
      };
    };
  };

  # 过渡期旧 pkgs/dsh 仍提供终端 dsh；切换时置 true。
  cli.enable = false;
};
```

`programs.dsh-desktop.settings` 会生成 `~/.dsh/cordis.patch.yml`（home 层 patch，对所有
profile 生效，优先于 profile 层）；旧 `settings.yaml` 的键名（如 `ui-onboarding`）会按上游
迁移表重映射。首次启动时上游会把旧的 `~/.dsh/settings.yaml` 重命名导入 profile，因此
**过渡期不要反复交替运行旧 CLI 与桌面端**；需要并存时给旧 CLI 单独的 `DSH_HOME`。
建议通过桌面入口或 `~/.local/bin/dsh-desktop`（会 source `environmentFiles`）启动，
不要直接调 profile 里的 `dsh-desktop`（不会注入环境文件）。

`cli.enable = true` 时提供一个复用桌面 payload 官方 Node/CLI 的终端 `dsh`。

## 文档

- [docs/desktop-build.md](docs/desktop-build.md)：载荷流水线、Linux 适配与 Gate 0 结论
- [docs/nix-implementation.md](docs/nix-implementation.md)：密封离线构建结构、hash 与更新流程
- [docs/upstream-audit.md](docs/upstream-audit.md)：上游发布形态与 Linux 适配相关的审计摘要
- [docs/acceptance.md](docs/acceptance.md)：nixos-config 切换与切换后的验收清单
- [docs/audit.md](docs/audit.md)：独立审计（Gate 3）的发现与处理记录
