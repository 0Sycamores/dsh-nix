# DSH packaging context

本仓库把 DeepSeek Harness（DSH）打包到 Linux/NixOS。这里的词描述「用户看到的 surface」
以及承载它们的构建产物；同一套 Host 核心可以由不同 surface 启动。

## Surfaces

**Surface**：
一种用户入口——桌面壳、终端 CLI 或 Web GUI——启动后都运行同一套 Host 核心与 profile 机制。
_Avoid_：app、client、frontend（用来指整个 surface 时）

**Web GUI**：
由 `web` profile 提供的浏览器界面，通过带进程 token 的 URL 打开。
_Avoid_：web app、dashboard

**Desktop shell**：
承载 `desktop` profile 的 Electron 窗口；它只提供窗口与桌面集成，Host 跑在运行时自带的 Node 上。

**Terminal CLI**：
在 shell 里运行的 `dsh` 命令，可以启动任意 profile（包括 `web` 与 `tui`）。
_Avoid_：旧 CLI、新 CLI（除非明确指历史包）

## Configuration

**Profile**：
按顺序叠加 patch 层来启动一个 surface 的配置组合，例如 `desktop`、`web`、`tui`、`headless`。

**Home layer**：
对所有 profile 生效的机器级 patch，叠加在 bundle 与 profile 自己的配置之后、命令行 `--patch` 之前。
_Avoid_：global config、user config

**Declarative settings**：
Home Manager 的 `programs.dsh.settings`，用于生成 home layer；它是该文件的唯一写入者。

**Managed profile**：
生命周期由某个 surface 独占的 profile（`desktop` profile 由桌面壳管理，终端不能直接 boot）。

## Packaging

**Payload**：
上游 monorepo 的已构建产物（源码快照、包 tarball、外壳 node_modules），是组装运行时的输入。
_Avoid_：runtime（指 payload 时）

**Runtime output**：
组装好的 harness 应用及其自带的 Node/Python/pnpm 依赖；带逐文件摘要，被所有 surface 共用。
_Avoid_：payload、runtime tree（含义模糊时）

**`dsh` package**：
薄 wrapper，引用 runtime output 提供 `dsh` 命令；不包含 Electron，因此 Web/CLI 闭包更小。
_Avoid_：dsh-cli（包名就是 `dsh`）

**Process token**：
`dsh web` 启动时打印在 URL 里的进程级启动凭据；浏览器用它换取签名 cookie。
_Avoid_：password、API key

**Session lock**：
同一个会话同一时间只能由一个 Host 打开的约束；不同会话可以跨 surface 并行。
