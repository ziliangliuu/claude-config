﻿# UserPromptSubmit hook（Windows PowerShell）：每次提交消息前校验出口 IP。
# 用途：覆盖「窗口长时间开着、运行中网络切换」的盲区。VPN 断了就拦下本次提交。
# 安装：放到 %USERPROFILE%\.claude\hooks\ 下，并在 settings.json 注册 UserPromptSubmit（见 需求.md）。
# 期望出口 IP 从单一来源文件读取（与启动层 claude-guard.ps1 共用同一文件）
$ipFile = Join-Path $HOME ".claude\hooks\expected-exit-ip"
$expectedIp = Get-Content $ipFile -ErrorAction SilentlyContinue | Select-Object -First 1
if ($expectedIp) { $expectedIp = $expectedIp.Trim() }
if (-not $expectedIp) {
    '{"decision":"block","reason":"未配置期望出口 IP，已拦截。请先配置 ~/.claude/hooks/expected-exit-ip。"}'
    exit 0
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$ip = $null
try { $ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5).ToString().Trim() } catch { }

$logDir = Join-Path $HOME ".claude\hooks"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$shownLog = if ($ip) { $ip } else { "EMPTY" }
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  prompt-check  detected_ip=[$shownLog]  expected=[$expectedIp]" |
    Out-File -FilePath (Join-Path $logDir "check-exit-ip.log") -Append -Encoding utf8

if ($ip -eq $expectedIp) { exit 0 }

$shown = if ($ip) { $ip } else { "未知" }
$reason = "网络校验未通过：当前出口 IP 为 [$shown]，要求为 [$expectedIp]。VPN 可能已断开或切换，本次消息已拦截，请恢复到正确网络后重试。"
@{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress
exit 0
