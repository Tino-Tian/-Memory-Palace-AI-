#!/usr/bin/env bash
# 记忆宫殿 — Stop 钩子（每次回答完成后触发）
# 做低频心跳检测：每 10 分钟最多提醒一次保存
# 不阻塞对话，不强制 Claude 继续回复

STAMP_FILE="/tmp/memory-palace-stop-stamp"
MIN_INTERVAL=600  # 10 分钟

now=$(date +%s)
last=0
if [ -f "$STAMP_FILE" ]; then
    last=$(cat "$STAMP_FILE" 2>/dev/null || echo 0)
fi

elapsed=$((now - last))

# 不到 10 分钟，静默跳过
if [ "$elapsed" -lt "$MIN_INTERVAL" ]; then
    exit 0
fi

# 更新时间戳
echo "$now" > "$STAMP_FILE"

# 检查当前会话是否有值得保存的内容
# 如果对话索引有今天的记录，说明本会话产生了内容
DB="$HOME/memory-palace/palace.db"
if [ -f "$DB" ]; then
    TODAY_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM conversation_index WHERE date=date('now');" 2>/dev/null || echo 0)
    ENTRY_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM entries WHERE date=date('now');" 2>/dev/null || echo 0)
    if [ "$TODAY_COUNT" -gt 0 ] || [ "$ENTRY_COUNT" -gt 0 ]; then
        echo "[记忆宫殿] 本会话已有内容产生。如需保存现场，随时用 /宫殿 保存现场"
    fi
fi

exit 0
