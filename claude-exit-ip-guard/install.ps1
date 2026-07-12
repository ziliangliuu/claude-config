# -----------------------------------------------------------------------------
# Claude Code 出口 IP 校验 一键安装（Windows PowerShell 5.1 / 7+）· 幂等，可重复运行
# 用法：在本文件夹目录下执行
#         powershell -ExecutionPolicy Bypass -File .\install.ps1
# 做的事：
#   (1) 期望出口 IP：已存在则沿用，缺失则写入默认值（$DefaultExitIp）
#   (2) 多源探测当前出口 IP，与期望值对比并打印
#   (3) 运行中层：拷 check-exit-ip-prompt.ps1 到 ~/.claude/hooks/，去重合并 UserPromptSubmit 钩子
#   (4) 启动层：把 claude-guard.ps1 装进 $PROFILE（先按 BEGIN/END 标记删旧块再写，去重）
# -----------------------------------------------------------------------------
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$DefaultExitIp = "198.65.8.45"          # 期望出口 IP 默认值（首次安装写入）
$HookTimeout   = 20                      # UserPromptSubmit 钩子超时（秒），给多源探测留余量
$hooksDir  = Join-Path $HOME ".claude\hooks"
$ipFile    = Join-Path $hooksDir "expected-exit-ip"
$beginMark = "# === Claude Code 出口 IP 校验（不匹配则阻止启动）BEGIN ==="
$endMark   = "# === Claude Code 出口 IP 校验 END ==="

# PowerShell 5.1 旧环境默认可能不含 TLS 1.2，先启用，否则 https 请求恒失败
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

function Get-ExitIp {
    # 多源：按顺序尝试，取第一个返回合法 IPv4 的服务
    $services = @(
        "https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com",
        "https://ipinfo.io/ip",  "https://checkip.amazonaws.com", "https://api.ip.sb/ip"
    )
    foreach ($svc in $services) {
        try {
            $resp = (Invoke-RestMethod -Uri $svc -TimeoutSec 4).ToString().Trim()
            if ($resp -match '^(\d{1,3}\.){3}\d{1,3}$') { return $resp }
        } catch { }
    }
    return $null
}

New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null

# (1) 期望出口 IP：已有沿用，避免覆盖别的机器已设好的值
$existing = Get-Content $ipFile -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) { $existing = $existing.Trim() }
if ($existing) {
    $expectedIp = $existing
    Write-Host "i  期望出口 IP 已存在，沿用：$expectedIp" -ForegroundColor Cyan
} else {
    $expectedIp = $DefaultExitIp
    $expectedIp | Out-File -Encoding utf8 $ipFile
    Write-Host "OK 已写入默认期望出口 IP：$expectedIp -> $ipFile" -ForegroundColor Green
}
Write-Host "   （换线路/换 IP 只需改这一个文件，两层共用）"

# (2) 探测当前出口 IP 并对比
Write-Host "-- 探测当前出口 IP --------------------"
$curIp = Get-ExitIp
if ($curIp) {
    if ($curIp -eq $expectedIp) {
        Write-Host "OK 当前出口 IP = $curIp，与期望一致。" -ForegroundColor Green
    } else {
        Write-Host "!  当前出口 IP = $curIp，与期望 [$expectedIp] 不一致。" -ForegroundColor Yellow
        Write-Host "   若这条线路才是你要的，请改：`"$curIp`" | Out-File -Encoding utf8 $ipFile"
    }
} else {
    Write-Host "!  所有 IP 探测服务均无响应，暂时取不到当前出口 IP（不影响安装，用时再校验）。" -ForegroundColor Yellow
}
Write-Host "--------------------------------------"

# (3) 运行中层：拷 hook + 去重合并 settings.json 的 UserPromptSubmit
Copy-Item ".\check-exit-ip-prompt.ps1" (Join-Path $hooksDir "check-exit-ip-prompt.ps1") -Force
$settingsPath = Join-Path $HOME ".claude\settings.json"
$newHook = [PSCustomObject]@{
    hooks = @([PSCustomObject]@{
        type    = "command"
        shell   = "powershell"
        command = '& "$env:USERPROFILE\.claude\hooks\check-exit-ip-prompt.ps1"'
        timeout = $HookTimeout
    })
}
if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    $cfg = Get-Content -Raw -Encoding UTF8 $settingsPath | ConvertFrom-Json
} else {
    $cfg = [PSCustomObject]@{}
}
if (-not ($cfg.PSObject.Properties.Name -contains "hooks")) {
    $cfg | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{}) -Force
}
# 过滤掉本脚本自己装的旧钩子（command 含 check-exit-ip-prompt.ps1），保留其它 UserPromptSubmit 钩子
$keptUps = @()
if ($cfg.hooks.PSObject.Properties.Name -contains "UserPromptSubmit") {
    foreach ($grp in @($cfg.hooks.UserPromptSubmit)) {
        $mine = $false
        foreach ($h in @($grp.hooks)) {
            if ($h.command -and ($h.command -like "*check-exit-ip-prompt.ps1*")) { $mine = $true }
        }
        if (-not $mine) { $keptUps += $grp }
    }
}
$keptUps += $newHook
$cfg.hooks | Add-Member -NotePropertyName UserPromptSubmit -NotePropertyValue @($keptUps) -Force
# 用无 BOM 的 UTF-8 写 JSON，避免带 BOM 导致解析器报错
[System.IO.File]::WriteAllText($settingsPath, ($cfg | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK 已合并 UserPromptSubmit 钩子到 $settingsPath（去重保留其它钩子；备份 settings.json.bak）" -ForegroundColor Green

# (4) 启动层：装进 $PROFILE，先按标记删旧块再写（幂等去重）
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
$profileLines = @(Get-Content -Encoding UTF8 $PROFILE -ErrorAction SilentlyContinue)
$clean = New-Object System.Collections.Generic.List[string]
$skip = $false
foreach ($line in $profileLines) {
    if ($line -like "*Claude Code 出口 IP 校验*BEGIN ===*") { $skip = $true }
    if (-not $skip) { $clean.Add($line) }
    if ($line -like "*Claude Code 出口 IP 校验 END ===*") { $skip = $false }
}
if ($skip) { Write-Host "!  $PROFILE 里检测到未闭合的旧块（有 BEGIN 无 END），请手动检查。" -ForegroundColor Yellow }
# 去掉尾部空行，保证与追加块之间只隔一个空行（多次运行不累积空行）
while ($clean.Count -gt 0 -and $clean[$clean.Count - 1].Trim() -eq "") { $clean.RemoveAt($clean.Count - 1) }
if (($profileLines | Where-Object { $_ -like "*Claude Code 出口 IP 校验*BEGIN ===*" }).Count -gt 0) {
    Write-Host "🧹 已清理 $PROFILE 中的旧 IP 校验块（去重）" -ForegroundColor Cyan
}
Set-Content -Path $PROFILE -Value $clean -Encoding utf8
Add-Content -Path $PROFILE -Value "" -Encoding utf8
Add-Content -Path $PROFILE -Value (Get-Content -Raw -Encoding UTF8 ".\claude-guard.ps1") -Encoding utf8
Write-Host "OK 已把启动层函数写入 $PROFILE（先清旧块再写，去重）" -ForegroundColor Green

Write-Host ""
Write-Host "完成。请【新开一个 PowerShell 窗口】使启动层生效；运行中钩子在【新开的 claude 会话】里生效。" -ForegroundColor Green
Write-Host "   验证：新开 PowerShell 执行  Get-Command claude  应显示 CommandType = Function。"
if (-not $curIp) { } elseif ($curIp -ne $expectedIp) {
    Write-Host "   注意：当前出口 IP 与期望不一致，敲 claude 会被拦。确认线路后按上面命令更新期望 IP。" -ForegroundColor Yellow
}
