#!/usr/bin/env bash
# 记忆宫殿 — 启动钩子
# 每次会话开始时运行，加载活跃记忆索引 + 执行时间衰减清理

DB="$HOME/memory-palace/palace.db"
ARCHIVE_DIR="$HOME/memory-palace/归档"

# 1. 时间衰减清理
sqlite3 "$DB" "UPDATE entries SET level='digest' WHERE level='raw' AND date <= date('now','-3 days');" 2>/dev/null || true

# 2. 7天+ digest 打包归档（导出为 SQLite 数据库，含表结构）
COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM entries WHERE level='digest' AND date <= date('now','-7 days');" 2>/dev/null || echo 0)
if [ "$COUNT" -gt 0 ]; then
    mkdir -p "$ARCHIVE_DIR"
    WEEK=$(date +%Y-W%V)
    ARCHIVE_DB="$ARCHIVE_DIR/$WEEK.db"
    # 创建归档库（独立 SQLite 文件，带完整表结构）
    sqlite3 "$ARCHIVE_DB" "
        CREATE TABLE entries (id, category_id, date, level, content, keywords, conversation_id);
        CREATE TABLE categories (id, parent_id, name, path, is_preset, created_at, last_active);
    " 2>/dev/null
    # 把要归档的数据复制到归档库
    sqlite3 "$DB" "ATTACH '${ARCHIVE_DB}' AS archive;
        INSERT INTO archive.entries SELECT * FROM entries WHERE level='digest' AND date <= date('now','-7 days');
        INSERT INTO archive.categories SELECT * FROM categories WHERE id IN (SELECT DISTINCT category_id FROM entries WHERE level='digest' AND date <= date('now','-7 days'));" 2>/dev/null
    gzip -f "$ARCHIVE_DB"
    # 从主库删除已归档的数据
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
echo ""
echo "=== 记忆宫殿行为规则（每次会话必须遵守）==="
echo ""
echo "▸ 主动嗅探：用户提到类目名/项目名/\"上次\"\"之前\"\"按之前的风格\"时，自动搜记忆"
echo "▸ 结束归档：每次对话有值得保存的内容时，按 SKILL.md 归类流程写入数据库"
echo "▸ 手动命令：/宫殿 查找|状态|树|类目|归类|新建类目|保存现场"
echo ""
echo "=== 规则加载完毕 ==="
