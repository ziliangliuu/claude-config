#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code 出口 IP 校验 一键安装（macOS / Linux）· 幂等，可重复运行
# 用法：在本文件夹目录下执行  bash install.sh
# 做的事：
#   ① 依赖检查（curl 必需；jq 用于安全合并 settings.json，缺失则打印手动片段）
#   ② 配置期望出口 IP：已存在则沿用，缺失则写入默认值（下方 DEFAULT_EXIT_IP）
#   ③ 多源探测当前出口 IP，与期望值对比并打印，便于当场确认线路
#   ④ 运行中层：拷 check-exit-ip-prompt.sh 到 ~/.claude/hooks/，合并 UserPromptSubmit 钩子
#   ⑤ 启动层：把 claude-guard.sh 装进当前 shell 的 rc 文件（先清掉旧块再写，去重）
# ─────────────────────────────────────────────────────────────────────────────
set -e
cd "$(dirname "$0")"

DEFAULT_EXIT_IP="198.65.8.45"           # 期望出口 IP 的默认值（首次安装时写入）
HOOK_TIMEOUT=20                         # UserPromptSubmit 钩子超时（秒），给多源探测留余量
IP_FILE="$HOME/.claude/hooks/expected-exit-ip"
BEGIN_MARK="# === Claude Code 出口 IP 校验（不匹配则阻止启动）BEGIN ==="
END_MARK="# === Claude Code 出口 IP 校验 END ==="

# 多源探测函数（与脚本内实现一致：取首个返回合法 IPv4 的服务）
detect_exit_ip() {
    local services=(
        "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"
        "https://ipinfo.io/ip"  "https://checkip.amazonaws.com" "https://api.ip.sb/ip"
    )
    local svc resp
    for svc in "${services[@]}"; do
        resp="$(curl -s --max-time 4 "$svc" 2>/dev/null | tr -d '[:space:]')"
        if printf '%s' "$resp" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            printf '%s' "$resp"; return 0
        fi
    done
    return 1
}

# ① 依赖检查
if ! command -v curl >/dev/null 2>&1; then
    echo "❌ 缺少依赖：curl。请先安装后重试。"; exit 1
fi
HAS_JQ=1; command -v jq >/dev/null 2>&1 || HAS_JQ=0

mkdir -p "$HOME/.claude/hooks"

# ② 配置期望出口 IP：已有则沿用，避免覆盖别的机器已设好的值
if [ -s "$IP_FILE" ]; then
    EXPECTED_IP="$(tr -d '[:space:]' < "$IP_FILE")"
    echo "ℹ️  期望出口 IP 已存在，沿用：$EXPECTED_IP （文件：$IP_FILE）"
else
    EXPECTED_IP="$DEFAULT_EXIT_IP"
    printf '%s\n' "$EXPECTED_IP" > "$IP_FILE"
    echo "✅ 已写入默认期望出口 IP：$EXPECTED_IP → $IP_FILE"
fi
echo "   （换线路/换 IP 只需改这一个文件，两层共用）"

# ③ 探测当前出口 IP 并对比
echo "── 探测当前出口 IP ──────────────────"
if CUR_IP="$(detect_exit_ip)"; then
    if [ "$CUR_IP" = "$EXPECTED_IP" ]; then
        echo "✅ 当前出口 IP = $CUR_IP，与期望一致。"
    else
        echo "⚠️  当前出口 IP = $CUR_IP，与期望 [$EXPECTED_IP] 不一致。"
        echo "    若当前这条线路才是你要的，请改：echo \"$CUR_IP\" > $IP_FILE"
    fi
else
    echo "⚠️  所有 IP 探测服务均无响应，暂时取不到当前出口 IP（不影响安装，用时再校验）。"
fi
echo "──────────────────────────────────────"

# ④ 运行中层：拷 hook + 合并 settings.json 的 UserPromptSubmit
cp check-exit-ip-prompt.sh "$HOME/.claude/hooks/check-exit-ip-prompt.sh"
chmod +x "$HOME/.claude/hooks/check-exit-ip-prompt.sh"
SETTINGS="$HOME/.claude/settings.json"
HOOK_JSON="{\"hooks\":[{\"type\":\"command\",\"command\":\"bash ~/.claude/hooks/check-exit-ip-prompt.sh\",\"timeout\":$HOOK_TIMEOUT}]}"
if [ "$HAS_JQ" = "1" ]; then
    if [ -f "$SETTINGS" ]; then
        cp "$SETTINGS" "$SETTINGS.bak"
        tmp=$(mktemp)
        jq --argjson h "$HOOK_JSON" '.hooks.UserPromptSubmit = [$h]' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
        echo "✅ 已合并 UserPromptSubmit 钩子到 $SETTINGS（原文件备份为 settings.json.bak）"
    else
        echo "{\"hooks\":{\"UserPromptSubmit\":[$HOOK_JSON]}}" | jq . > "$SETTINGS"
        echo "✅ 已创建 $SETTINGS 并写入 UserPromptSubmit 钩子"
    fi
else
    echo "⚠️  未安装 jq，跳过自动合并 settings.json。请手动把下面这段合并进 $SETTINGS 的 hooks 里："
    echo "    \"UserPromptSubmit\": [$HOOK_JSON]"
fi

# ⑤ 启动层：装进当前 shell 的 rc（先清旧块再写，幂等去重）
case "$(basename "${SHELL:-}")" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) if [ "$(uname)" = "Darwin" ]; then RC="$HOME/.bash_profile"; else RC="$HOME/.bashrc"; fi ;;
    *)    RC="$HOME/.zshrc"; echo "ℹ️  未识别当前 shell，默认装到 $RC" ;;
esac
touch "$RC"
if grep -qF "$BEGIN_MARK" "$RC"; then
    tmp=$(mktemp)
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        index($0,b){skip=1} skip==0{print} index($0,e){skip=0}
    ' "$RC" > "$tmp" && mv "$tmp" "$RC"
    echo "🧹 已清理 $RC 中的旧 IP 校验块（去重）"
fi
printf '\n' >> "$RC"
cat claude-guard.sh >> "$RC"
echo "✅ 已把启动层函数写入 $RC"

echo
echo "🎉 安装完成。请【新开一个终端窗口】使启动层生效；运行中钩子在【新开的 claude 会话】里生效。"
echo "   验证：新开终端执行  type claude  应显示 'claude is a shell function'。"
