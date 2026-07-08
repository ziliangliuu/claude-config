# === Claude Code 出口 IP 校验（不匹配则阻止启动）BEGIN ===
# 适用：macOS / Linux 的 zsh 或 bash。
# 安装：把本段内容追加到 ~/.zshrc（zsh）或 ~/.bashrc（bash），然后【新开终端】。
# 原理：定义与命令同名的函数 claude；启动前先查出口 IP，不符则 return 1 不启动；
#       相符时用 `command claude` 走 PATH 调用真正的可执行文件（避免函数递归）。
claude() {
    # 期望出口 IP 从单一来源文件读取（启动层与运行中层共用，改 IP 只改这一个文件）
    local expected_ip
    expected_ip="$(cat "$HOME/.claude/hooks/expected-exit-ip" 2>/dev/null | tr -d '[:space:]')"
    if [ -z "$expected_ip" ]; then
        printf '\033[31m❌ 未配置期望出口 IP（~/.claude/hooks/expected-exit-ip 缺失或为空），已阻止启动。\033[0m\n' >&2
        return 1
    fi
    local log="$HOME/.claude/hooks/check-exit-ip.log"
    local ip
    ip="$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')"

    mkdir -p "$(dirname "$log")" 2>/dev/null
    printf '%s  wrapper  detected_ip=[%s]  expected=[%s]\n' \
        "$(date '+%F %T')" "${ip:-EMPTY}" "$expected_ip" >> "$log" 2>/dev/null

    if [ "$ip" != "$expected_ip" ]; then
        printf '\033[31m❌ 网络校验未通过：当前出口 IP 为 [%s]，要求为 [%s]。\033[0m\n' "${ip:-未知}" "$expected_ip" >&2
        printf '\033[33m   已阻止启动 Claude Code，请切换到出口 IP 为 %s 的网络/代理后重试。\033[0m\n' "$expected_ip" >&2
        return 1
    fi

    printf '\033[32m✅ 出口 IP 检查通过（%s），正在启动 Claude Code…\033[0m\n' "$ip"
    command claude "$@"
}
# === Claude Code 出口 IP 校验 END ===
