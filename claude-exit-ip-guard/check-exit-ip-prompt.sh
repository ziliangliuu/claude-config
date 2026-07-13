#!/bin/bash
# UserPromptSubmit hook（macOS/Linux）：每次提交消息前校验出口 IP。
# 用途：覆盖「窗口长时间开着、运行中网络切换」的盲区——启动时的 wrapper 只查一次，
#       这个 hook 在你每次发消息前再查一次，VPN 断了就拦下本次提交。
# 安装：放到 ~/.claude/hooks/ 下，并在 ~/.claude/settings.json 注册 UserPromptSubmit（见 需求.md）。
# 期望出口 IP 从单一来源文件读取（与启动层 claude-guard.sh 共用同一文件）
EXPECTED_IP="$(cat "$HOME/.claude/hooks/expected-exit-ip" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$EXPECTED_IP" ]; then
  printf '{"decision":"block","reason":"未配置期望出口 IP（~/.claude/hooks/expected-exit-ip 缺失或为空），已拦截。请先配置该文件。"}\n'
  exit 0
fi

# 合法 IPv4 校验（逐段 0-255）。用 grep 定形状 + 参数展开逐段范围校验（bash/zsh 通用，
# 不依赖会因 shell 不同而异的 `for o in $1` 词分割）。
_valid_ipv4() {
  printf '%s' "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
  local rest="$1" o
  while [ -n "$rest" ]; do
    o="${rest%%.*}"
    [ "$o" -le 255 ] 2>/dev/null || return 1
    case "$rest" in *.*) rest="${rest#*.}" ;; *) rest="" ;; esac
  done
  return 0
}

# 多个出口 IP 回显服务。**并发**请求全部服务，全部完成后按优先级取首个合法 IPv4：
# 最坏耗时≈单个 --max-time（而非 6 个累加），既容错又避免逼近钩子 timeout 造成放行。
IP_SERVICES=(
  "https://api.ipify.org"
  "https://ifconfig.me/ip"
  "https://icanhazip.com"
  "https://ipinfo.io/ip"
  "https://checkip.amazonaws.com"
  "https://api.ip.sb/ip"
)
d="$(mktemp -d)"
i=0
for svc in "${IP_SERVICES[@]}"; do
  ( curl -s --max-time 3 "$svc" 2>/dev/null | tr -d '[:space:]' > "$d/$i" ) &
  i=$((i + 1))
done
wait
ip=""
used_service=""
j=0
for svc in "${IP_SERVICES[@]}"; do
  resp="$(cat "$d/$j" 2>/dev/null)"
  if _valid_ipv4 "$resp"; then ip="$resp"; used_service="$svc"; break; fi
  j=$((j + 1))
done
rm -rf "$d"

printf '%s  prompt-check  detected_ip=[%s]  expected=[%s]  source=[%s]\n' \
    "$(date '+%F %T')" "${ip:-EMPTY}" "$EXPECTED_IP" "${used_service:-NONE}" >> "$HOME/.claude/hooks/check-exit-ip.log" 2>/dev/null

[ "$ip" = "$EXPECTED_IP" ] && exit 0

if [ -z "$ip" ]; then
  reason="网络校验未通过：所有 IP 探测服务均无响应（共尝试 ${#IP_SERVICES[@]} 个），无法确认当前出口 IP。请检查网络后重试。"
else
  reason="网络校验未通过：当前出口 IP 为 [${ip}]，要求为 [${EXPECTED_IP}]。VPN 可能已断开或切换，本次消息已拦截，请恢复到正确网络后重试。"
fi
printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
