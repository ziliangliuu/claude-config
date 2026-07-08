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
    $expectedIp = "YOUR_EXIT_IP"
    $logDir = Join-Path $HOME ".claude\hooks"
    $log    = Join-Path $logDir "check-exit-ip.log"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

    # PowerShell 5.1 旧环境默认可能不含 TLS 1.2，先启用，否则 https 请求恒失败被误拦
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    $ip = $null
    try { $ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 8).ToString().Trim() } catch { }

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $shownLog = if ($ip) { $ip } else { "EMPTY" }
    "$stamp  wrapper  detected_ip=[$shownLog]  expected=[$expectedIp]" |
        Out-File -FilePath $log -Append -Encoding utf8

    if ($ip -ne $expectedIp) {
        $shown = if ($ip) { $ip } else { "未知" }
        Write-Host "X 网络校验未通过：当前出口 IP 为 [$shown]，要求为 [$expectedIp]。" -ForegroundColor Red
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
