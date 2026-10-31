# dsh-nix

DSH（DeepSeek Harness）的 Linux/NixOS 打包 —— **个人自用、非官方**。提供桌面端和共享同一份
运行时的终端/Web CLI。

- 基线：`dsh-v0.2.2-alpha.2`
- 目标：NixOS / x86_64-linux / Wayland
- 状态：桌面端 Gate 0/1/2/3 已在 `laptop` 验收；CLI/Web 包与 Home Manager 模块已实现，
  home 手动 Web 验收见 [docs/acceptance.md](docs/acceptance.md)
- 许可：MIT（见 [LICENSE](LICENSE)、[NOTICE](NOTICE)）

## 两个包

| 包 | 内容 | 用途 |
|---|---|---|
| `dsh-desktop` | Electron 外壳 + 共享运行时 | 桌面窗口 |
| `dsh` | 只引用共享运行时的薄 wrapper，无 Electron | 终端 `dsh`；`dsh web` 浏览器界面 |

两者共用同一份 `dsh-desktop-runtime`（harness 应用 + 官方 Node/Python 依赖），因此版本不会
漂移。取舍记录见 [ADR 0001](docs/adr/0001-one-runtime-three-surfaces.md)。

```sh
nix build .#dsh-desktop && ./result/bin/dsh-desktop
nix build .#dsh && ./result/bin/dsh --version
./result/bin/dsh web --help
```

运行时自带的官方 Node/Python 依赖 NixOS 的 `nix-ld`（`programs.nix-ld.enable = true;`）；
Electron dist 已由 nixpkgs 打好补丁，不需要 nix-ld。

## NixOS 接线

桌面主机（laptop）：

```nix
{
  inputs.dsh-nix.url = "github:0Sycamores/dsh-nix";

  # 让 pkgs.dsh / pkgs.dsh-desktop 可用；也可以显式设置两个模块的 package 选项。
  nixpkgs.overlays = [ inputs.dsh-nix.overlays.default ];

  # default = 桌面模块，它内部 import 了 programs.dsh 共享模块。
  home-manager.sharedModules = [ inputs.dsh-nix.homeModules.default ];
  programs.nix-ld.enable = true;
}
```

只跑 Web/终端的主机（home）：

```nix
{
  nixpkgs.overlays = [ inputs.dsh-nix.overlays.default ];
  home-manager.sharedModules = [ inputs.dsh-nix.homeModules.dsh ];
  programs.nix-ld.enable = true;
}
```

Home Manager 侧：

```nix
programs.dsh = {
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
};

# 仅桌面主机需要；要求上面 programs.dsh.enable = true。
programs.dsh-desktop.enable = true;
```

`programs.dsh` 是共享设置的**唯一写入者**：它生成 `~/.dsh/cordis.patch.yml`（home 层 patch，
对所有 profile 生效，优先于 profile 层），并安装一个会 source `environmentFiles`、固定
`DSH_HOME` 的 `dsh` wrapper。桌面模块只读这些值，不再写设置文件。旧 `settings.yaml` 的键名
（如 `ui-onboarding`）会按上游迁移表重映射。

`programs.dsh-desktop` 只提供 Electron 外壳、launcher 和 desktop entry；它需要
`programs.dsh.enable = true`。推荐通过桌面入口或 `~/.local/bin/dsh-desktop` 启动（会注入
环境文件），不要直接调包里的 `dsh-desktop`。

## Web（手动启动）

Web 界面**不装 systemd 服务、不自启**。需要时在目标主机手动启动，用 tmux 跨 SSH 存活：

```sh
tmux new -As dsh-web 'dsh web --no-open --host "$(tailscale ip -4)" --port 3080'
```

终端会打印带进程 token 的 URL（如 `http://100.64.0.1:3080/?token=…`），在 tailnet 内的
浏览器打开即可。只绑 loopback 或 tailnet，不接公网 vhost；token URL 等同登录凭据，不要外传。
完整运行手册、会话锁/并发说明与故障排查见 [docs/web.md](docs/web.md)。

## 开发与质量门

```sh
nix develop                     # 固定工具链（node/pnpm/python3/shellcheck/nixfmt/curl/...）
bash scripts/check.sh           # 廉价门禁：可执行位/shellcheck/nixfmt/flake eval/轻量 checks/verify 自测
bash scripts/check.sh --full    # 额外构建 dsh + dsh-desktop，并跑 verify-web smoke
```

`--full` 会构建约 1.3G 的桌面端，日常不必。CI（[.github/workflows/ci.yml](.github/workflows/ci.yml)）
只跑廉价门禁。

`checks` 里的 `hm-module` 用 dummy 包渲染 Home Manager 输出（含 desktop entry 必须是普通文件
的回归检查），`dsh`/`dsh-desktop` 构建重包，`runtime-lockfile` 校验 lockfile 与 patch hash；
`scripts/verify-web.sh` 用临时 `DSH_HOME` 验证 token URL → 303 → 200。agent 入口见
[AGENTS.md](AGENTS.md)。

## 文档

- [docs/web.md](docs/web.md)：Web surface 手动启动、安全边界与验收
- [docs/desktop-build.md](docs/desktop-build.md)：载荷流水线、Linux 适配与 Gate 0 结论
- [docs/nix-implementation.md](docs/nix-implementation.md)：密封离线构建、共享 runtime 与更新流程
- [docs/upstream-audit.md](docs/upstream-audit.md)：上游发布形态与 Linux 适配相关的审计摘要
- [docs/acceptance.md](docs/acceptance.md)：nixos-config 切换与验收清单
- [docs/audit.md](docs/audit.md)：独立审计与已知限制
- [GLOSSARY.md](GLOSSARY.md)：surface / profile / payload / runtime 等术语
- [docs/adr/](docs/adr/)：架构决策记录
