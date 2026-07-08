#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code 状态栏 一键安装（macOS / Linux）
# 用法：在本文件夹目录下执行  bash install.sh
# 做三件事：查依赖 → 拷脚本到 ~/.claude/hooks/ → 合并 statusLine 进 settings.json
# ─────────────────────────────────────────────────────────────────────────────
set -e
cd "$(dirname "$0")"

# ① 依赖检查（状态栏脚本运行需要 jq、curl）
for cmd in jq curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ 缺少依赖：$cmd。macOS 执行 brew install $cmd，Linux 用对应包管理器安装后重试。"
        exit 1
    fi
done

# ② 安装脚本
mkdir -p "$HOME/.claude/hooks"
cp statusline.sh "$HOME/.claude/hooks/statusline.sh"
chmod +x "$HOME/.claude/hooks/statusline.sh"

# ③ 合并 settings.json（只写 statusLine 字段，保留其余已有配置；先备份）
SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_JSON='{"type":"command","command":"SHOW_WEEKLY=1 bash ~/.claude/hooks/statusline.sh","padding":0}'
if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.bak"
    tmp=$(mktemp)
    jq --argjson sl "$STATUSLINE_JSON" '.statusLine = $sl' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "已合并 statusLine 到 $SETTINGS（原文件备份为 settings.json.bak）"
else
    mkdir -p "$HOME/.claude"
    echo "{\"statusLine\": $STATUSLINE_JSON}" | jq . > "$SETTINGS"
    echo "已创建 $SETTINGS"
fi

# ④ 自测：喂一份模拟 stdin，确认脚本能正常渲染
echo "── 自测输出 ──────────────────────────"
NOW=$(date +%s)
printf '{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":12,"context_window_size":1000000},"workspace":{"current_dir":"%s"},"rate_limits":{"five_hour":{"used_percentage":7,"resets_at":%s},"seven_day":{"used_percentage":5,"resets_at":%s}}}' \
    "$HOME" "$((NOW + 10680))" "$((NOW + 100800))" \
    | SHOW_WEEKLY=1 bash "$HOME/.claude/hooks/statusline.sh"
echo "──────────────────────────────────────"
echo "✅ 安装完成。新开一个 claude 会话即可看到状态栏。"
