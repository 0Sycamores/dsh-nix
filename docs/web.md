# Web surface（手动启动）

DSH 的浏览器界面由 `web` profile 提供。本仓库**不安装 systemd 服务、不自启**：需要时在
目标主机上手动启动，用 tmux 让它跨 SSH 会话存活。

## 启动

在 home（或任何装了 `programs.dsh` 的主机）上：

```sh
tmux new -As dsh-web 'dsh web --no-open --host "$(tailscale ip -4)" --port 3080'
```

- `--host` 只接受本机一个具体 IPv4/IPv6 地址，**不接受** `0.0.0.0` / `::`。
- 用 tailnet IP 时，laptop、手机等 tailnet 成员可直接访问；不经过 nginx、不占公网端口。
- 只想在 laptop 本地浏览器用：省略 `--host`（默认 `127.0.0.1`）。
- `--no-open` 避免在服务器上尝试打开浏览器。

终端会打印类似：

```
dsh web: http://100.64.0.1:3080/?token=…
```

把整条 URL 复制到浏览器。浏览器用进程 token 换取签名 cookie，然后重定向到干净地址。

## 停止 / 查看

```sh
tmux attach -t dsh-web     # 看输出、拿最新 token URL
tmux kill-session -t dsh-web
```

直接按 Ctrl-C 也可以；tmux 会话随之结束。没有开机自启，重启主机后需要再执行启动命令。

## 数据与并发

- 使用与桌面/终端相同的 `~/.dsh`（`DSH_HOME`），所以会话历史、凭据和
  `~/.dsh/cordis.patch.yml` 共享。
- 同一个 session 不能同时在两个 Host 里打开：桌面端开着某个会话时，web 里再打开会提示
  “This session is already in use…”。换一个会话，或先关闭另一个 surface 即可；不同会话
  可以并行。
- 重启 web 进程会换一个新的进程 token，旧 URL/旧 cookie 失效；`~/.dsh` 里的历史不受影响。
- `DSH_WEB_URL` 会以干净地址（不含 token）暴露给 Agent 的 bash 环境，用于运行时上下文。

## 安全边界

- Web GUI 拥有宿主机的完整工具执行权限，**只绑 loopback 或 tailnet**，不要接公网 vhost，
  也不要把 tailnet IP 直接转发到公网。
- tailnet 内是 WireGuard 加密的明文 HTTP；DSH 自己不做 TLS。需要 TLS 时用
  `--tls-cert/--tls-key` 或一个只监听 tailnet 的反代，并同时设置 `--trusted-host`。
- token URL 等同登录凭据，不要贴到聊天/日志/工单里；`printUrl: false` 可关闭打印，但那样
  只能自己从别处拿 URL。
- 用具体 IP 访问时 Host/Origin 校验直接通过；用 MagicDNS 名称访问需要额外的
  `--trusted-host home.<tailnet>`，否则浏览器请求会被 fence 拒绝。

## 验收

自动化（本仓库，任意主机）：

```sh
bash scripts/verify-web.sh                 # 构建 .#dsh 并用临时 DSH_HOME 跑 smoke
bash scripts/verify-web.sh --package /nix/store/…-dsh-0.2.2-alpha.2
```

它验证 token URL 返回 303、cookie 交换后首页 200、页面含注入的 `__DSH_BOOT__`，不会读写
真实 `~/.dsh`，也不会打开浏览器。

手动验收（home 主机）：

1. 按上面的 tmux 命令启动；确认打印的是 tailnet IP 的 URL。
2. 在 laptop 浏览器打开 URL，页面加载；发一条消息，确认模型与 bash 工具可用。
3. `ss -ltnp | grep 3080` 只显示 `<tailnet-ip>:3080`，没有 `0.0.0.0` / `[::]`。
4. 关掉浏览器标签、重启 web，重新打开新 token URL，历史会话仍在。
5. laptop 上桌面端正常启动；桌面与 web 同时运行时，同一会话只在一个 surface 打开。

## 故障排查

| 现象 | 处理 |
|---|---|
| `dsh: command not found` | `programs.dsh.enable = true` 后重新 `nixos-rebuild switch`；确认 `home.packages` 里有 `dsh` |
| `--host` 报 wildcard rejected | 用 `tailscale ip -4` 的具体地址，或省略 `--host` 用 loopback |
| 端口被占 | 换 `--port 3081`，或先停掉旧进程 |
| 浏览器 403 / Host rejected | 用 bind IP 访问；若必须用域名，加 `--trusted-host <authority>` |
| 找不到 token URL | `tmux attach -t dsh-web`；不要从旧日志里复用已失效的 URL |
| tailnet 打不开 | `tailscale status` 确认两端在线；`--host` 必须是本机 tailnet 地址 |
| 预览版说明点「继续」报“暂时无法保存确认状态” | home patch 里的 `ui-settings-general.welcomeNoticeVersion` 与当前 `WELCOME_NOTICE_VERSION` 不一致（0.2.2-alpha.2 是 `2026-09-28.1`）；home 层优先级高于 UI 写入，必须把声明值改成当前版本，或删掉这一行让 UI 自行持久化。改完重启 Web（或重新 switch 生成 patch） |
