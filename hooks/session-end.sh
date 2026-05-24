#!/usr/bin/env bash
# 记忆宫殿 — SessionEnd 钩子（会话正常退出时触发）
# 自动生成会话摘要并保存快照

SESSION_ID="session-$(date +%Y%m%d-%H%M%S)"
DB="$HOME/memory-palace/palace.db"
MEMORY_DIR="$HOME/.claude/projects/-Users-mac/memory"

# 检查今天是否有新产生的记忆条目
if [ -f "$DB" ]; then
    TODAY_ENTRIES=$(sqlite3 "$DB" "SELECT COUNT(*) FROM entries WHERE date=date('now');" 2>/dev/null || echo 0)
    TODAY_CONV=$(sqlite3 "$DB" "SELECT COUNT(*) FROM conversation_index WHERE date=date('now');" 2>/dev/null || echo 0)

    if [ "$TODAY_ENTRIES" -eq 0 ] && [ "$TODAY_CONV" -eq 0 ]; then
        # 没有新内容，跳过
        exit 0
    fi
fi

# 检查是否有 Claude 写好的快照文件
BRIEF_FILE="$MEMORY_DIR/session-resume-brief.md"
FULL_FILE="$MEMORY_DIR/session-resume-full.md"

if [ -f "$BRIEF_FILE" ] && [ -s "$BRIEF_FILE" ]; then
    # 已有快照文件，直接保存
    bash "$HOME/memory-palace/hooks/save-session.sh" "$SESSION_ID" 2>/dev/null
    echo "[记忆宫殿] 会话已自动归档 (${SESSION_ID})"
else
    # 没有快照文件，提醒用户
    echo ""
    echo "[记忆宫殿] 本次会话产生了 $TODAY_ENTRIES 条记忆、$TODAY_CONV 条对话记录"
    echo "[记忆宫殿] 如需保存工作现场供下次恢复，下次退出前先执行 /宫殿 保存现场"
fi

exit 0
