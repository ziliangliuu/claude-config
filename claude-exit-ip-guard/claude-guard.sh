# === Claude Code 出口 IP 校验（不匹配则阻止启动）BEGIN ===
# 适用：macOS / Linux 的 zsh 或 bash。
# 安装：把本段内容追加到 ~/.zshrc（zsh）或 ~/.bashrc（bash），然后【新开终端】。
# 原理：定义与命令同名的函数 claude；启动前先查出口 IP，不符则 return 1 不启动；
#       相符时用 `command claude` 走 PATH 调用真正的可执行文件（避免函数递归）。
# 合法 IPv4 校验（逐段 0-255）。注意本文件会被 source 进 zsh，zsh 默认不对 $var 做词分割，
# 故不用 `for o in $1`（那在 zsh 下不切分），改用 grep 定形状 + 参数展开逐段范围校验，bash/zsh 通用。
_claude_valid_ipv4() {
    printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
    local rest="$1" o
    while [ -n "$rest" ]; do
        o="${rest%%.*}"
        [ "$o" -le 255 ] 2>/dev/null || return 1
        case "$rest" in *.*) rest="${rest#*.}" ;; *) rest="" ;; esac
    done
    return 0
}
claude() {
    # 期望出口 IP 从单一来源文件读取（启动层与运行中层共用，改 IP 只改这一个文件）
    local expected_ip
    expected_ip="$(cat "$HOME/.claude/hooks/expected-exit-ip" 2>/dev/null | tr -d '[:space:]')"
    if [ -z "$expected_ip" ]; then
        printf '\033[31m❌ 未配置期望出口 IP（~/.claude/hooks/expected-exit-ip 缺失或为空），已阻止启动。\033[0m\n' >&2
        return 1
    fi
    local log="$HOME/.claude/hooks/check-exit-ip.log"

    # 多个出口 IP 回显服务，**并发**发起请求。命中即放行：谁先完成、且结果等于期望 IP，
    # 立即停止等待、终止其余请求——原实现用 `wait` 阻塞到全部完成，最坏耗时=最慢的那个；
    # 现在最坏耗时=最快命中的那个。只有全程没有命中时（可能被拦截），才等全部完成，
    # 再按优先级取首个合法 IPv4 用于日志/提示（“判定拦截”要更谨慎，不能让某个慢/挂的
    # 服务在其他服务还没回来时就提前误判）。
    # 注意：本文件会被 zsh 或 bash 直接 source（无 shebang），zsh 数组默认从 1 开始、
    # bash 从 0 开始，故有意不对 ip_services 做数字下标访问，只用 `for svc in "${arr[@]}"`
    # 顺序遍历 + 独立整数计数器对应临时文件名，两种 shell 下行为一致。
    local ip_services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
        "https://checkip.amazonaws.com"
        "https://api.ip.sb/ip"
    )
    local ip="" used_service="" svc resp svcname d i=0 j=0 k m total seen_count=0 pid
    d="$(mktemp -d)"
    for svc in "${ip_services[@]}"; do
        (
          resp="$(curl -s --max-time 4 "$svc" 2>/dev/null | tr -d '[:space:]')"
          printf '%s\n%s\n' "$resp" "$svc" > "$d/$i.result"
          : > "$d/$i.done"
        ) &
        echo "$!" > "$d/$i.pid"
        i=$((i + 1))
    done
    total=$i
    while [ "$seen_count" -lt "$total" ]; do
        k=0
        while [ "$k" -lt "$total" ]; do
            if [ ! -f "$d/$k.seen" ] && [ -f "$d/$k.done" ]; then
                : > "$d/$k.seen"
                seen_count=$((seen_count + 1))
                resp="$(sed -n '1p' "$d/$k.result" 2>/dev/null)"
                svcname="$(sed -n '2p' "$d/$k.result" 2>/dev/null)"
                if _claude_valid_ipv4 "$resp" && [ "$resp" = "$expected_ip" ]; then
                    ip="$resp"; used_service="$svcname"
                    m=0
                    while [ "$m" -lt "$total" ]; do
                        if [ ! -f "$d/$m.seen" ]; then
                            pid="$(cat "$d/$m.pid" 2>/dev/null)"
                            [ -n "$pid" ] && kill "$pid" 2>/dev/null
                            [ -n "$pid" ] && disown "$pid" 2>/dev/null
                        fi
                        m=$((m + 1))
                    done
                    seen_count=$total
                    break 2
                fi
            fi
            k=$((k + 1))
        done
        [ "$seen_count" -lt "$total" ] && sleep 0.05
    done
    if [ -z "$ip" ]; then
        j=0
        while [ "$j" -lt "$total" ]; do
            resp="$(sed -n '1p' "$d/$j.result" 2>/dev/null)"
            svcname="$(sed -n '2p' "$d/$j.result" 2>/dev/null)"
            if _claude_valid_ipv4 "$resp"; then ip="$resp"; used_service="$svcname"; break; fi
            j=$((j + 1))
        done
    fi
    rm -rf "$d"

    mkdir -p "$(dirname "$log")" 2>/dev/null
    printf '%s  wrapper  detected_ip=[%s]  expected=[%s]  source=[%s]\n' \
        "$(date '+%F %T')" "${ip:-EMPTY}" "$expected_ip" "${used_service:-NONE}" >> "$log" 2>/dev/null

    if [ "$ip" != "$expected_ip" ]; then
        if [ -z "$ip" ]; then
            printf '\033[31m❌ 网络校验未通过：所有 IP 探测服务均无响应，无法确认当前出口 IP。\033[0m\n' >&2
        else
            printf '\033[31m❌ 网络校验未通过：当前出口 IP 为 [%s]，要求为 [%s]。\033[0m\n' "$ip" "$expected_ip" >&2
        fi
        printf '\033[33m   已阻止启动 Claude Code，请切换到出口 IP 为 %s 的网络/代理后重试。\033[0m\n' "$expected_ip" >&2
        return 1
    fi

    printf '\033[32m✅ 出口 IP 检查通过（%s），正在启动 Claude Code…\033[0m\n' "$ip" >&2
    command claude "$@"
}
# === Claude Code 出口 IP 校验 END ===
