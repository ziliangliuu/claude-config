# === Claude Code 出口 IP 校验（不匹配则阻止启动）BEGIN ===
# 适用：Windows PowerShell 5.1 / PowerShell 7+。
# 安装：把本段内容追加到 PowerShell 配置文件 $PROFILE，然后【新开 PowerShell 窗口】。
#   查看/创建配置文件：
#     notepad $PROFILE            # 不存在会提示新建
#     若报错，先建目录：New-Item -ItemType File -Force -Path $PROFILE
#   若加载被拦（策略限制），执行一次：
#     Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# 原理：定义与命令同名的函数 claude；启动前查出口 IP，不符则直接返回不启动；
#       相符时用 Get-Command -CommandType Application 找到真正的 claude.cmd 调用（避免递归）。
function claude {
    # 期望出口 IP 从单一来源文件读取（启动层与运行中层共用，改 IP 只改这一个文件）
    $ipFile = Join-Path $HOME ".claude\hooks\expected-exit-ip"
    $expectedIp = Get-Content $ipFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($expectedIp) { $expectedIp = $expectedIp.Trim() }
    if (-not $expectedIp) {
        Write-Host "X 未配置期望出口 IP（~/.claude/hooks/expected-exit-ip 缺失或为空），已阻止启动。" -ForegroundColor Red
        return
    }
    $logDir = Join-Path $HOME ".claude\hooks"
    $log    = Join-Path $logDir "check-exit-ip.log"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

    # PowerShell 5.1 旧环境默认可能不含 TLS 1.2，先启用，否则 https 请求恒失败被误拦
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    # 合法 IPv4 校验（逐段 0-255，用 [0-9] 而非 \d 以免匹配全角数字）
    function Test-ValidIPv4([string]$s) {
        if ($s -notmatch '^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$') { return $false }
        foreach ($o in $Matches[1..4]) { if ([int]$o -gt 255) { return $false } }
        return $true
    }

    # 多个出口 IP 回显服务，**并发**发起请求（HttpClient 异步）。命中即放行：谁先完成、且结果
    # 等于期望 IP，立即停止等待——原实现用 WaitAll 阻塞到全部完成/超时，最坏耗时=最慢的那个；
    # 现在最坏耗时=最快命中的那个。只有全程没有命中时（可能被拦截），才等到全部完成/超时，
    # 再按优先级取首个合法 IPv4 用于日志/提示（“判定拦截”要更谨慎，不能让某个慢/挂的服务在
    # 其他服务还没回来时就提前误判）。
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
    $tasks = [System.Threading.Tasks.Task[]](foreach ($svc in $ipServices) { $client.GetStringAsync($svc) })

    $pending = @(0..($tasks.Count - 1))
    $deadline = (Get-Date).AddMilliseconds(5000)
    while ($pending.Count -gt 0) {
        $msLeft = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        if ($msLeft -le 0) { break }
        $pendingTasks = [System.Threading.Tasks.Task[]]@(foreach ($idx in $pending) { $tasks[$idx] })
        $completed = [System.Threading.Tasks.Task]::WaitAny($pendingTasks, $msLeft)
        if ($completed -lt 0) { break }
        $k = $pending[$completed]
        $pending = @($pending | Where-Object { $_ -ne $k })
        if ($tasks[$k].Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
            $resp = $tasks[$k].Result.Trim()
            if ((Test-ValidIPv4 $resp) -and ($resp -eq $expectedIp)) {
                $ip = $resp; $usedService = $ipServices[$k]
                break
            }
        }
    }
    if (-not $ip) {
        for ($k = 0; $k -lt $ipServices.Count; $k++) {
            if ($tasks[$k].Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $resp = $tasks[$k].Result.Trim()
                if (Test-ValidIPv4 $resp) { $ip = $resp; $usedService = $ipServices[$k]; break }
            }
        }
    }
    $client.Dispose()

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $shownLog = if ($ip) { $ip } else { "EMPTY" }
    "$stamp  wrapper  detected_ip=[$shownLog]  expected=[$expectedIp]  source=[$usedService]" |
        Out-File -FilePath $log -Append -Encoding utf8

    if ($ip -ne $expectedIp) {
        if (-not $ip) {
            Write-Host "X 网络校验未通过：所有 IP 探测服务均无响应，无法确认当前出口 IP。" -ForegroundColor Red
        } else {
            Write-Host "X 网络校验未通过：当前出口 IP 为 [$ip]，要求为 [$expectedIp]。" -ForegroundColor Red
        }
        Write-Host "   已阻止启动 Claude Code，请切换到出口 IP 为 $expectedIp 的网络/代理后重试。" -ForegroundColor Yellow
        return
    }

    Write-Host "OK 出口 IP 检查通过（$ip），正在启动 Claude Code…" -ForegroundColor Green

    $real = Get-Command claude.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $real) {
        $real = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $real) {
        Write-Host "找不到 claude 可执行文件，请确认已用 npm 全局安装。" -ForegroundColor Red
        return
    }
    & $real.Source @args
}
# === Claude Code 出口 IP 校验 END ===
