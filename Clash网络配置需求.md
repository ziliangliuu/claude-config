# 网络配置需求（Clash 分流 + WebRTC 防泄露）

> 本文件是给「其他电脑上的 Claude Code」看的配置说明。目标导向——不同电脑的客户端、
> 订阅、节点名、路径可能不同，请先探测实际值再操作，不要照抄本文里的具体名字/路径。

## 总目标

1. **分流**：在「虚拟网卡(TUN)模式 + 规则模式」下，**所有中国境内流量直连、所有非中国流量走 VPN**。
2. **防 WebRTC IP 泄露**：浏览器不能暴露真实公网 IP。

---

## 配置项 A：Clash TUN + 规则分流

### 背景
- 常见客户端：Clash Verge Rev（内核 mihomo）、ClashX、Clash for Windows 等。先确认用的是哪个。
- Clash Verge Rev 的 mihomo 本地 API：可通过 unix socket 访问（macOS 常见路径
  `/tmp/verge/verge-mihomo.sock`；也可能是 TCP `127.0.0.1:9097`）。用它**只读检查**状态。
  - 读模式：`curl -s --unix-socket <sock> http://localhost/configs`
  - 读代理组：`curl -s --unix-socket <sock> http://localhost/proxies`
  - 读规则：`curl -s --unix-socket <sock> http://localhost/rules`

### 要达成的三个状态
1. **TUN（虚拟网卡）开启**。Clash Verge Rev 在 `verge.yaml` 里是 `enable_tun_mode: true`；
   或在客户端界面确认 TUN/虚拟网卡已打开。
2. **代理模式 = 规则(rule)**，不是 global，也不是 direct。
3. **各选择组指向正确**：国内类组（"国内服务""私有网络"等）→ `DIRECT`；
   非国内类组和兜底（"非中国""漏网之鱼"）→ 指向一个**可用节点组**（绝不能是 `REJECT`）。
   > 组名是订阅自带的、带 emoji 的中文名，各订阅不同。先用 `/proxies` 列出真实组名再判断。

### ⚠️ 关键坑（务必遵守，否则重启回退）
- **不要只用 mihomo API 改 mode**。API 的 `PATCH /configs {"mode":"rule"}` 只改**运行时**，
  客户端的持久化文件里 mode 仍是旧值（如 direct），**重启客户端 / 订阅自动更新后会回退**，
  分流整体失效。
- **持久化只能在客户端 GUI 里做**：在界面点选「规则」模式；把被设成 `REJECT` 的选择组
  在界面里点成「自动选择」或某个具体节点。GUI 操作才会写回持久化配置（如 `profiles.yaml`）。
- 改完**必须重启一次客户端验证不回退**。

### 验证分流是否正确（只读、可自动化）
```bash
# 国外服务：应返回代理节点出口 IP（走 VPN）
curl -s --max-time 12 https://api.ipify.org
# 国内服务：应返回你的真实公网 IP、且归属中国（直连）
curl -s --max-time 12 https://myip.ipip.net
# 交叉验证
curl -s --max-time 12 https://www.cip.cc | head -3
```
两个 IP **不同** = 分流正确（国外走代理、国内直连）。两个相同都为代理 IP = 还在全局模式。

---

## 配置项 B：WebRTC 真实 IP 防泄露

### 关键教训（别走弯路）
- **不要试图用 Clash 规则堵 WebRTC**。曾尝试把 STUN（`DOMAIN-KEYWORD,stun` + 
  `DST-PORT,3478/19302/5349`）强制走代理，规则确实加载成功，但**仍会泄露**——WebRTC 的
  STUN 服务器和端口形态太多，规则按域名/端口挡是打地鼠，总有漏网路径拿到真实 IP。
- **WebRTC 泄露只能在浏览器层彻底解决。**

### 做法（推荐，最彻底）
1. 浏览器安装 WebRTC 防泄露扩展：
   - Chrome / Edge：扩展商店装 **WebRTC Leak Shield**（或 WebRTC Control）。
   - Firefox：地址栏 `about:config` → 把 `media.peerconnection.enabled` 改为 `false`（无需装扩展）。
2. WebRTC Leak Shield 选 **Strict protection**（完全禁用 WebRTC，最大防泄露）→ 点 **Apply**。
   - 代价：浏览器**网页版**的视频/语音通话、P2P 可能失效。若这些都用桌面客户端(App)，则无影响。
   - 若确需某个网页通话：改选 **Balanced protection**（减少泄露、保留功能，但不如 Strict 彻底）。
3. Clash 保持在**规则模式**（这样国内网站照常打开）。

### 验证
浏览器打开 `https://browserleaks.com/webrtc`：应**不再显示真实公网 IP**（Strict 下通常无 IP 或仅代理 IP）。

---

## 快速验收清单

- [ ] TUN / 虚拟网卡：已开
- [ ] 代理模式：规则(rule)，且 GUI 已固化、重启不回退
- [ ] 选择组：非国内/兜底组指向可用节点（非 REJECT）
- [ ] 分流实测：国外=代理 IP，国内=真实中国 IP，两者不同
- [ ] WebRTC：browserleaks 不再泄露真实 IP
- [ ] 国内网站可正常打开

---

## 相关

- 启动 Claude Code 的出口 IP 校验（另一独立需求）见同目录 `claude-exit-ip-guard/`。
