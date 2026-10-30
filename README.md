# dsh-nix

DSH 桌面端（DeepSeek Harness desktop shell）的 Nix/NixOS 打包 —— **个人自用、非官方**。

- 基线：`dsh-v0.2.2-alpha.2`
- 目标：NixOS / x86_64-linux / Wayland
- 状态：Gate 1 通过（密封离线构建、`packages.dsh-desktop` 可启动）；Gate 2（HM 模块与 nixos-config 接线）进行中
- 许可：MIT（见 [LICENSE](LICENSE)、[NOTICE](NOTICE)）

## 用法

```sh
nix build github:0Sycamores/dsh-nix#dsh-desktop   # 或本地 `nix build .#dsh-desktop`
nix run   .#dsh-desktop                            # 直接启动（调试）
```

这是**未封装的上游载荷**：Electron 外壳 + 官方 dsh 生产运行时树。数据目录默认 `~/.dsh`
（与终端 dsh 共享；桌面 profile 为 `profiles/desktop`）。

Home Manager 用户：

```nix
{
  inputs.dsh-nix.url = "github:0Sycamores/dsh-nix";
  # ...
  home-manager.sharedModules = [ inputs.dsh-nix.homeModules.default ];

  programs.dsh-desktop = {
    enable = true;
    environmentFiles = [ "/run/secrets/rendered/dsh_env" ];
    settings = {
      agent-default-model = {
        provider = "sycamore";
        model = "deepseek-v4.1-flash";
        reasoningEffort = "max";
      };
      permission.defaultPreset = "danger-full-access";
    };
    # 过渡期旧 pkgs/dsh 仍提供终端 dsh；切换时置 true。
    cli.enable = false;
  };
}
```

`programs.dsh-desktop.settings` 会生成 `~/.dsh/cordis.patch.yml`（home 层 patch，对所有
profile 生效，优先于 profile 层）；旧 `settings.yaml` 的键名（如 `ui-onboarding`）会重映射。
`cli.enable = true` 时提供一个复用桌面 payload 官方 Node/CLI 的终端 `dsh`。

## 文档

- [docs/desktop-build.md](docs/desktop-build.md)：载荷流水线、Linux 适配与 Gate 0 结论
- [docs/nix-implementation.md](docs/nix-implementation.md)：密封离线构建结构、hash 与更新流程
