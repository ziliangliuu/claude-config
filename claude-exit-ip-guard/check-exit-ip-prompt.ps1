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

# 多个出口 IP 回显服务，按顺序尝试，取第一个返回合法 IPv4 的结果（多源容错，
# 避免单一服务临时抽风/超时导致取不到 IP 而误拦消息）。全部失败才判定探测不到。
$ipServices = @(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
    "https://ipinfo.io/ip"
    "https://checkip.amazonaws.com"
    "https://api.ip.sb/ip"
)
$ip = $null
$usedService = "NONE"
foreach ($svc in $ipServices) {
    try {
        $resp = (Invoke-RestMethod -Uri $svc -TimeoutSec 3).ToString().Trim()
        if ($resp -match '^(\d{1,3}\.){3}\d{1,3}$') { $ip = $resp; $usedService = $svc; break }
    } catch { }
}

$logDir = Join-Path $HOME ".claude\hooks"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$shownLog = if ($ip) { $ip } else { "EMPTY" }
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  prompt-check  detected_ip=[$shownLog]  expected=[$expectedIp]  source=[$usedService]" |
    Out-File -FilePath (Join-Path $logDir "check-exit-ip.log") -Append -Encoding utf8

if ($ip -eq $expectedIp) { exit 0 }

if (-not $ip) {
    $reason = "网络校验未通过：所有 IP 探测服务均无响应（共尝试 $($ipServices.Count) 个），无法确认当前出口 IP。请检查网络后重试。"
} else {
    $reason = "网络校验未通过：当前出口 IP 为 [$ip]，要求为 [$expectedIp]。VPN 可能已断开或切换，本次消息已拦截，请恢复到正确网络后重试。"
}
@{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress
exit 0
