# 我的电脑配置需求集

> 这个目录收集了一组「配置需求」文档，用于在**新电脑**上让 Claude Code 照着复现同样的配置。
> 到了新电脑，把整个目录拷过去，让那边的 Claude Code 先读本 README，再按需执行对应文档即可。

## 目录内容

| 配置 | 文档 | 一句话说明 |
|------|------|-----------|
| 启动 IP 校验 | [`claude-exit-ip-guard/需求.md`](./claude-exit-ip-guard/需求.md) | 两层防护：启动前 + 运行中每次发消息前校验出口 IP，不是 `YOUR_EXIT_IP` 就阻止 |
| 网络分流 + 防泄露 | [`Clash网络配置需求.md`](./Clash网络配置需求.md) | Clash TUN+规则模式：国内直连、非国内走 VPN；浏览器防 WebRTC 泄露 |

`claude-exit-ip-guard/` 里还含两个可直接安装的脚本：`claude-guard.sh`（macOS/Linux）、`claude-guard.ps1`（Windows）。

## 在新电脑上怎么用

对新电脑的 Claude Code 说：**「读一下这个目录的 README 和各需求文档，帮我在这台电脑上配好。」**
它会按文档里的步骤 + 验证方法逐项落地。每份文档都自带「验证方法」和「已知的坑」，照着走即可。

## ⚠️ 每台机器的差异点（新电脑上这些值大概率不同，需现场探测，别照抄旧值）

1. **操作系统 / Shell**
   - macOS 默认 zsh（`~/.zshrc`）；Linux 常见 bash（`~/.bashrc`）；Windows 用 PowerShell（`$PROFILE`）。
   - IP 校验脚本按系统选对应文件安装（见 `claude-exit-ip-guard/需求.md`）。

2. **claude 可执行文件路径**
   - 本机是 `~/.npm-global/bin/claude`，别的电脑可能是 `/usr/local/bin`、`%APPDATA%\npm` 等。
   - 用 `command -v claude`（mac/Linux）或 `Get-Command claude`（Windows）现场确认。

3. **Clash 客户端与配置路径**
   - 本机是 Clash Verge Rev，配置在
     `~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/`，
     mihomo API 走 `/tmp/verge/verge-mihomo.sock`。
   - 别的电脑可能是 ClashX / Clash for Windows / 别的目录 / TCP 端口 `127.0.0.1:9097`。先探测。

4. **订阅 / 节点 / 代理组名**
   - 出口 IP（`YOUR_EXIT_IP`）、节点名、带 emoji 的代理组名都来自具体订阅，**换订阅就会变**。
   - Clash 配置先用 API `/proxies`、`/rules` 列出真实组名和规则，再对号操作。
   - IP 校验里的期望 IP 若换了线路/节点，也要同步改脚本里的 `expected_ip`。

5. **浏览器**
   - WebRTC 防泄露按实际浏览器选方案：Chrome/Edge 装扩展，Firefox 改 `about:config`。

## 核心原则（跨机器通用，别踩的坑）

- Claude Code 的**启动**拦截：**用 shell 函数包装**，不要用 SessionStart 钩子（`continue:false` 拦不住启动）。
- Claude Code 的**运行中**拦截：用 `UserPromptSubmit` 钩子，它的 `decision:block` 能真正拦住每次提交（覆盖长开窗口、中途断网）。
- Clash 改模式：**GUI 里改并重启验证**，只用 API 改 `mode` 不持久、会回退。
- 选择组**不能是 REJECT**，否则对应流量被拒。
- WebRTC 防泄露**在浏览器层做**，别指望 Clash 规则堵 STUN（堵不干净）。
