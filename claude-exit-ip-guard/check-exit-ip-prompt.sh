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

ip="$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')"

printf '%s  prompt-check  detected_ip=[%s]  expected=[%s]\n' \
    "$(date '+%F %T')" "${ip:-EMPTY}" "$EXPECTED_IP" >> "$HOME/.claude/hooks/check-exit-ip.log" 2>/dev/null

[ "$ip" = "$EXPECTED_IP" ] && exit 0

reason="网络校验未通过：当前出口 IP 为 [${ip:-未知}]，要求为 [${EXPECTED_IP}]。VPN 可能已断开或切换，本次消息已拦截，请恢复到正确网络后重试。"
printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
