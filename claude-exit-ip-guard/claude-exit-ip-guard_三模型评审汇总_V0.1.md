# 《claude-exit-ip-guard》三模型独立评审汇总

> 评审对象:`claude-exit-ip-guard/`(Claude Code 出口 IP 两层校验)+ 根 `README.md`
> 评审方式:3 个不同厂商顶尖大模型各自独立、同一评审提纲、互不可见 → 主控汇总 + 对抗核查
> 评审员:**A = OpenAI(codex CLI, gpt-5.6-sol)**、**B = Google(Antigravity `agy`, Gemini 3.5 Flash High)**、**C = Anthropic(Claude Agent, Fable 5)**
> 汇总日期:2026-07-12 · 主控:Claude(Opus 4.8)

---

## 一、总评

| 评审员 | 评分 | 一句话 |
|---|---|---|
| A · OpenAI codex | **4.5/10** | 设计方向合理、mac 理想环境能装起来,但「清理干净、Windows 对等、真正 fail-closed」均未兑现 |
| B · Gemini | **4/10** | 主要压在「PS5.1 无 -TimeoutSec 致命 Bug」上 —— 经核查该条**不成立**,评分明显偏低 |
| C · Claude Fable 5 | **7/10** | 方案正确、去重是真做了且较细,两平台主路径能装通;有若干 fail-open 窗口与 Windows profile 分裂坑 |

**主控裁定(对抗核查后):基本满足但有需收口的实质问题。** mac/Linux 主路径确实做到了「幂等去重 + 两层安装 + 单点配置」(与前几轮隔离实测一致);但 ①README「把环境清理好」措辞过满,②Windows 侧有已确认与存疑的实缺陷且未在真机验证过。三家评分差异主要源于对「Windows/未知旧环境/fail-open」这些边界的权重不同,以及 B 的一条幻觉。

---

## 二、按评审提纲的结论

- **① 需求是否合理**:三家一致认为**合理**。shell 函数包装(而非 SessionStart)+ UserPromptSubmit 钩子 + 多源探测 + 单文件期望 IP,是达成目标成本最低的轻量设计,且文档诚实声明了「自我约束、可被绕过」的边界。

- **② 需求是否被实现**:**mac/Linux 主路径满足;「清理环境」措辞过满;Windows 判定不满足/存疑。**
  - 满足:四脚本共读同一 `expected-exit-ip`、两层安装、重复运行去重、保留其它钩子 —— C 与主控此前隔离实测均确认。
  - 过满:去重只清「本项目 BEGIN/END 标记块」+「当前 shell 的那一个 rc」,清不掉无标记的旧 `claude()`、其它 shell 的 rc、其它 PowerShell 版本的 `$PROFILE`。README「把环境清理好」应改为「对本项目自身幂等去重」。
  - Windows:双 BOM(已确认)、`"shell":"powershell"` 钩子字段与执行策略(存疑,需真机)等,未在真 Windows 验证过。

- **③ 实现逻辑遗漏与偏差**:见下表,主要是 fail-open 窗口、编码、备份、正则、平台不对等。

---

## 三、跨模型共识 Top 问题(排序)

| # | 严重度·家数 | 问题 | 定位 | 主控核查 |
|---|---|---|---|---|
| 1 | 高·1(A) | 两个 `.ps1` 是**双 BOM**(`EF BB BF EF BB BF`),第二个 BOM 会成为正文首行的 U+FEFF | claude-guard.ps1:1、check-exit-ip-prompt.ps1:1 | **成立**(xxd 实测双 BOM);落在注释行,功能影响有限但确为缺陷,应剥成单 BOM |
| 2 | 高·3(A/C/B含) | 钩子**错误/超时是 fail-open**(退出非0非2 或超时→放行),与文档「异常时两层 fail-closed」矛盾。缺失配置那条其实已正确 fail-closed | check-exit-ip-prompt.*、需求.md fail-closed 叙述 | **部分成立**:缺配置=fail-closed(对);脚本报错/超时=fail-open(文档过承诺) |
| 3 | 高·2(A/C) | 「清理环境」只清本项目标记块 + 当前 shell 单个 rc,清不掉无标记旧函数/其它 shell/其它 PS 版本 profile;README 措辞过满 | README:14-25、install.sh:97-115、install.ps1:107-121 | **成立**(措辞层面);但重复装**本项目**能去重,属实 |
| 4 | 中·2(A/C) | Windows **PS5.1 与 pwsh7 的 `$PROFILE` 是不同文件**;固定用 `powershell` 安装只写 5.1 的 profile,日常用 7 的用户启动层静默失效 | README:23-24、install.ps1:107 | **成立**,文档零提示 |
| 5 | 中·2(A/C/B) | 多源**串行**探测最坏 6×3=18s,逼近钩子 20s 上限;一旦触顶又回到 #2 的放行 | install.sh:16、install.ps1:15、需求.md:134 | **成立**,余量偏窄 |
| 6 | 中·1(A) | IPv4 正则 `^(\d{1,3}\.){3}\d{1,3}$` 接受 `999.999.999.999` | 四脚本 + 两 installer 正则 | **成立**;但方向 fail-closed,影响小 |
| 7 | 中·2(A/C) | `settings.json.bak` 单槽,重复安装会用「已改过」的覆盖原始备份 | install.sh:77、install.ps1:81 | **成立**,minor |
| 8 | 中·3(A/B/C) | 安装器发现当前 IP≠期望仍打印「完成」,不强制确认 → AI 机械执行可能留错 IP,两层「装了但恒拦」 | install.sh:56-67、install.ps1:54-66 | **成立**;但自动把当前 IP 设为期望有风险(可能固化未连 VPN 的错误出口),宜「提示+要求确认」 |
| 9 | 中·1(A) | `"shell":"powershell"` 钩子字段是否受支持 + 执行策略 Restricted 是否拦 hook | 需求.md:182、install.ps1 生成的 settings | **存疑**:A 疑不支持、C 称查证支持 —— 必须真 Windows 验证;建议命令改 `powershell -ExecutionPolicy Bypass -File` 兜底 |
| 10 | 低·1(C) | 启动层成功提示打到 **stdout**(未 `>&2`),污染 `claude -p ... \| jq` 管道 | claude-guard.sh:48 | **成立**,minor |
| 11 | 低·2(C/A) | `expected-exit-ip`:PS 侧 `Out-File utf8` 带 BOM、`.sh` 侧 `tr` 不剥 BOM;多行时 sh 拼接、ps 取首行,跨端不对等 | claude-guard.sh:9 vs .ps1:14 | **成立**,边角 |
| 12 | 低·1(C) | 文档自相矛盾:需求.md 手动步骤荐 `Add-Content`,install.ps1 注释又说避开它;install.ps1 用 `🧹` 违反「Win 用 OK/X」自述 | 需求.md:89 vs install.ps1:122/120 | **成立**,minor |

### ❌ 核查判定为「不成立」的发现
- **B·① 「PS 5.1 的 `Invoke-RestMethod` 无 `-TimeoutSec`,致命 Bug,整个校验瘫痪」** → **不成立**。`-TimeoutSec` 自 PowerShell 3.0 起即为 `Invoke-RestMethod`/`Invoke-WebRequest` 的正式参数,Windows PowerShell 5.1 支持。B 的 4/10 主要建立在此条之上,故其评分与「Windows 完全不可用」结论不采信。

---

## 四、调度者补充判断(对抗核查小结)

1. **核心需求裁定**:mac/Linux「拉下来 → `bash install.sh` → 清理(本项目自身)+ 装好两层」**闭环成立**;Windows 因双 BOM(确认)+ 钩子字段/执行策略(存疑,无真机)**暂不能判定满足**。
2. **最该改的措辞**:README/需求.md 把「把环境清理好」收敛为「对本项目做幂等去重安装(靠 BEGIN/END 标记),不保证清理其它来源的旧 `claude()`」——避免过承诺。
3. **最该修的代码**:两个 `.ps1` 的双 BOM(确认);其余按成本分档见下。
4. **B 的登录**:`agy` 首次探活触发了重新认证(重试即通),本次三家均在场、无缺席补位。

---

## 五、建议下一步(供选择)

- **A|低成本、当下就能做**:①剥掉两个 `.ps1` 的第二个 BOM;②`claude-guard.sh:48` 成功提示加 `>&2`;③IPv4 正则加 0-255 校验;④`settings.json.bak` 改为不覆盖已有备份(带时间戳或仅首次备份);⑤修文档三处 minor 矛盾(Add-Content/🧹/措辞)。
- **B|中等**:①README/需求.md 把「清理环境」措辞收敛为「本项目幂等去重」,并补「换 shell / 换 PS 版本需另清对应 rc/profile」提示;②钩子 command 改 `powershell -ExecutionPolicy Bypass -File ...` 兜底执行策略;③文档明确写「钩子超时=放行(fail-open),故 timeout 给足余量」,不再声称异常一律 fail-closed;④安装器 IP 不一致时改为更醒目的提示(可选交互确认)。
- **C|需你点头 / 需真机**:①在**真 Windows(PS5.1 与 pwsh7 各一)**上实跑 `install.ps1`,验证 `"shell":"powershell"` 钩子字段、执行策略、`$PROFILE` 分裂、双 BOM 剥离后行为;②是否要把「串行探测」改「并发探测取首个」以压低延迟、彻底避开 fail-open 窗口。

---

# 附:三份独立评审(要点)

> 全文另存于 scratchpad:`out-A-codex.md`、`out-B-gemini.md`;C 见下。以下为各家结论要点,原文未删改语义。

## 报告一 · A(OpenAI codex, 4.5/10)
未完整实现。①设计合理但多源串行探测有延迟隐患、启动层可被 IDE/绝对路径绕过。②清理环境不满足(只清标记块,不清无标记旧函数/其它 rc/其它 PS profile);Windows 因双 BOM + 钩子 shell 字段存疑判定不满足。③列 13 项:hook 非 fail-closed(高)、Windows shell 字段存疑(高)、双 BOM(高)、只清标记块(高)、单 rc/单 profile(中)、IP 不一致仍完成(中)、IPv4 正则不校验(中)、20s 余量窄(中)、settings 合并缺防御(中)、bak 单槽(中)、期望 IP 无校验(低)、手动步骤清理能力不足(低)。

## 报告二 · B(Gemini 3.5 Flash High, 4/10)
5 条:①PS5.1 无 -TimeoutSec 致命 Bug【经核查**不成立**】;②半块 BEGIN/END 静默删用户配置后半段(高)【`.sh` 现已有告警,但无备份、删到 EOF 属实】;③钩子未加 -ExecutionPolicy Bypass(中);④期望 IP 提取对空格/多行/注释敏感(中);⑤`Add-Member` 管道操作兼容性隐患(低,存疑)。

## 报告三 · C(Claude Fable 5, 7/10)
两子目标主路径均实现且去重逐行核过正确。12 条:Windows profile 5.1/7 分裂(中偏高)、UserPromptSubmit 超时 fail-open 未如实告知(中)、rc/$PROFILE 重写无备份+半块删到 EOF(中)、启动层成功提示污染 stdout(中)、新 mac 无 jq 静默降级/损坏 settings 崩死(中)、expected-ip BOM 跨端不匹配(低中)、Add-Content 文档矛盾(低)、🧹 emoji 违自述(低)、只清当前 rc(低)、多行期望 IP 两端不一致(低)、bak 单槽(低)、IPv4 正则+执行策略(低存疑)。明确列出多项「未发现问题」(服务列表一致、共读同一文件、其它钩子保留正确、`shell` 字段查证支持 等)。
