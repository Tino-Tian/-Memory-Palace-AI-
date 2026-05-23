#!/usr/bin/env bash
# 记忆宫殿 — 启动钩子
# 每次会话开始时运行，加载活跃记忆索引 + 执行时间衰减清理

DB="$HOME/memory-palace/palace.db"
ARCHIVE_DIR="$HOME/memory-palace/归档"

# 1. 时间衰减清理
sqlite3 "$DB" "UPDATE entries SET level='digest' WHERE level='raw' AND date <= date('now','-3 days');" 2>/dev/null || true

# 2. 7天+ digest 打包归档
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM entries WHERE level='digest' AND date <= date('now','-7 days');" 2>/dev/null || echo 0)
if [ "$COUNT" -gt 0 ]; then
    mkdir -p "$ARCHIVE_DIR"
    WEEK=$(date +%Y-W%V)
    sqlite3 "$DB" ".headers on" -csv "SELECT id, category_id, date, level, content, keywords, conversation_id FROM entries WHERE level='digest' AND date <= date('now','-7 days');" 2>/dev/null \
        | gzip > "$ARCHIVE_DIR/$WEEK.db.gz"
    sqlite3 "$DB" "DELETE FROM entries WHERE level='digest' AND date <= date('now','-7 days');" 2>/dev/null || true
fi

# 3. 输出活跃记忆索引（这些文本会注入到 Claude 的上下文中）
echo "=== 记忆宫殿：活跃索引 ==="
echo ""
echo "▸ 活跃类目（近 3 天）："
sqlite3 "$DB" "SELECT '  ' || path FROM categories WHERE last_active >= date('now','-3 days') ORDER BY path;" 2>/dev/null || echo "  （无）"
echo ""
echo "▸ 近 3 天记忆条目："
sqlite3 "$DB" "SELECT '  [' || e.date || '] ' || c.path || ' | ' || e.keywords FROM entries e JOIN categories c ON e.category_id = c.id WHERE e.date >= date('now','-3 days') ORDER BY e.date DESC;" 2>/dev/null || echo "  （无）"
echo ""
echo "=== 索引加载完毕 ==="
