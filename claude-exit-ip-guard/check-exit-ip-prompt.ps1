# UserPromptSubmit hook（Windows PowerShell）：每次提交消息前校验出口 IP。
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

# 合法 IPv4 校验（逐段 0-255，过滤 999.999.999.999 之类；用 [0-9] 而非 \d 以免匹配全角数字）
function Test-ValidIPv4([string]$s) {
    if ($s -notmatch '^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$') { return $false }
    foreach ($o in $Matches[1..4]) { if ([int]$o -gt 255) { return $false } }
    return $true
}

# 多个出口 IP 回显服务。**并发**请求全部服务（HttpClient 异步），全部完成/超时后按优先级取
# 首个合法 IPv4，最坏耗时≈单个超时（而非 6 个累加），避免逼近钩子 timeout 造成放行。
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
try { Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue } catch { }
$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(4)
$tasks = foreach ($svc in $ipServices) { $client.GetStringAsync($svc) }
try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks, 5000) } catch { }
for ($k = 0; $k -lt $ipServices.Count; $k++) {
    if ($tasks[$k].Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
        $resp = $tasks[$k].Result.Trim()
        if (Test-ValidIPv4 $resp) { $ip = $resp; $usedService = $ipServices[$k]; break }
    }
}
$client.Dispose()

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
