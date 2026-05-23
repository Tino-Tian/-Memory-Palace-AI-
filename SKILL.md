---
name: memory-palace
description: 记忆宫殿 — 基于 SQLite 的分层记忆管理。启动加载索引，对话中主动嗅探，结束时自动归档。使用 /宫殿 命令手动管理。
---

# 记忆宫殿 (Memory Palace)

你是记忆宫殿的管理员。每次对话中，你负责在 `~/memory-palace/palace.db` 中存取记忆。

## 数据库 Schema（参考）

```sql
categories:     id, parent_id, name, path, is_preset, created_at, last_active
entries:        id, category_id, date, level, content, keywords, conversation_id
conversation_index: id, date, summary, entry_count
```

- `level`: raw（0-3天）| digest（3-7天）
- `path` 例: `生活/国际大事/国家负责人讲话`
- `is_preset`: 1=初始预设类目, 0=动态创建的

## 一、启动时（每次对话开始必须执行）

运行以下命令加载记忆索引：

```bash
sqlite3 ~/memory-palace/palace.db "
SELECT path, last_active FROM categories
WHERE last_active >= date('now','-3 days')
ORDER BY path;
"
```

```bash
sqlite3 ~/memory-palace/palace.db "
SELECT c.path, e.date, e.keywords, e.level
FROM entries e JOIN categories c ON e.category_id = c.id
WHERE e.date >= date('now','-3 days')
ORDER BY e.date DESC;
"
```

将结果作为"活跃记忆索引"记在上下文中。这只是目录，不需要现在就加载完整内容。

## 二、对话中（主动嗅探）

**触发条件（满足任一即触发）：**
- 用户提到类目名、项目名、日期、"上次""之前""按之前的风格"
- 当前话题明显切换，可能命中某类目
- 任务卡壳，需要查历史参考

**查询：**

```bash
# 按关键词
sqlite3 ~/memory-palace/palace.db "
SELECT c.path, e.date, e.content FROM entries e
JOIN categories c ON e.category_id = c.id
WHERE e.keywords LIKE '%关键词%' OR c.path LIKE '%关键词%'
ORDER BY e.date DESC LIMIT 5;
"

# 按日期
sqlite3 ~/memory-palace/palace.db "
SELECT c.path, e.date, e.content FROM entries e
JOIN categories c ON e.category_id = c.id
WHERE e.date >= '指定日期' ORDER BY e.date DESC LIMIT 5;
"
```

查到了 → 用一句话告知用户（"翻到了之前关于XX的记录，当时..."），纳入当前思考。
查不到 → 静默跳过，不提。

如果可能涉及 7 天前的归档：

```bash
ls ~/memory-palace/归档/ | tail -5
gunzip -c ~/memory-palace/归档/YYYY-WXX.db.gz | sqlite3 /dev/stdin "SELECT ..."
```

## 三、会话结束时（自动归档）

对话结束前，执行以下步骤：

### 3.1 分拆对话

将本次对话按话题边界拆为多段。判断标准：用户明显换了话题（项目切换、工作↔生活等）。

### 3.2 归类

每段对话匹配类目，优先级：
1. 匹配现有小类 → 直接归入
2. 匹配大类但不命中具体小类 → 先创建小类再归入
3. 跨多个门类 → 各自拆分归入
4. 全都不匹配 → 暂时放入"杂项"，下次启动时提醒用户确认

### 3.3 创建动态类目（如需要）

```bash
sqlite3 ~/memory-palace/palace.db "
INSERT INTO categories (parent_id, name, path, is_preset)
VALUES (
  (SELECT id FROM categories WHERE path='父级路径'),
  '新类目名',
  '父级路径/新类目名',
  0
);
"
```

命名规则：简短、通用、能概括同类话题。

### 3.4 写入记忆

每段对话写入一条 entry（内容用中文摘要，100-200 字）：

```bash
sqlite3 ~/memory-palace/palace.db "
INSERT INTO entries (category_id, date, level, content, keywords, conversation_id)
VALUES (
  (SELECT id FROM categories WHERE path='类目路径'),
  date('now'),
  'raw',
  '对话摘要——保留：话题结论、用户做的决定、关键上下文。丢弃：具体聊天文字、来回讨论过程。',
  '逗号,分隔,的关键词',
  'conv-' || date('now') || '-' || printf('%02d', (SELECT COUNT(*) FROM conversation_index WHERE date=date('now')) + 1)
);
"
```

同时写入对话索引：

```bash
sqlite3 ~/memory-palace/palace.db "
INSERT INTO conversation_index (date, summary, entry_count)
VALUES (date('now'), '本次对话的一句话概括', N);
"
```

### 3.5 时间衰减

```bash
# raw 超过 3 天 → 浓缩为 digest（保留结论和关键上下文，丢弃聊天文字）
sqlite3 ~/memory-palace/palace.db "
UPDATE entries SET level='digest'
WHERE level='raw' AND date <= date('now','-3 days');
"

# digest 超过 7 天 → 导出打包，从主库删除
sqlite3 ~/memory-palace/palace.db ".headers on" -csv "
SELECT id, category_id, date, level, content, keywords, conversation_id
FROM entries WHERE level='digest' AND date <= date('now','-7 days');
" | gzip > ~/memory-palace/归档/$(date +%Y-W%V).db.gz

sqlite3 ~/memory-palace/palace.db "
DELETE FROM entries WHERE level='digest' AND date <= date('now','-7 days');
"
```

### 3.6 更新类目活跃时间

```bash
sqlite3 ~/memory-palace/palace.db "
UPDATE categories SET last_active=date('now')
WHERE path IN ('本次归档涉及的所有类目路径，用逗号分隔并加单引号');
"
```

## 四、压缩恢复

当对话被压缩后，重新执行"启动时"的索引加载，再对当前话题做一次主动嗅探。

## 五、/命令实现

所有命令通过 sqlite3 实现：

**`/宫殿 查找 <关键词>`**
```bash
sqlite3 ~/memory-palace/palace.db "
SELECT c.path, e.date, e.content FROM entries e
JOIN categories c ON e.category_id = c.id
WHERE e.keywords LIKE '%关键词%' OR e.content LIKE '%关键词%'
ORDER BY e.date DESC LIMIT 10;
"
# 如果主库没找到，搜索归档
for f in ~/memory-palace/归档/*.db.gz; do
  gunzip -c "$f" | grep -i '关键词' && echo "（来自归档: $f）"
done
```

**`/宫殿 类目 <路径>`**
```bash
sqlite3 ~/memory-palace/palace.db "
SELECT date, level, content FROM entries
WHERE category_id = (SELECT id FROM categories WHERE path='路径')
ORDER BY date DESC;
"
```

**`/宫殿 归类 <路径>`** — 将当前对话归入指定类目（覆盖自动归类）

**`/宫殿 新建类目 <路径>`** — 手动创建类目（按 3.3 的 SQL）

**`/宫殿 树`**
```bash
sqlite3 ~/memory-palace/palace.db "
SELECT path FROM categories ORDER BY path;
"
```

**`/宫殿 状态`**
```bash
sqlite3 ~/memory-palace/palace.db "
SELECT '类目总数: ' || COUNT(*) FROM categories;
SELECT '活跃记忆(raw): ' || COUNT(*) FROM entries WHERE level='raw';
SELECT '浓缩记忆(digest): ' || COUNT(*) FROM entries WHERE level='digest';
SELECT '归档文件数: ' || COUNT(*) FROM (SELECT 1 FROM entries WHERE 1=0);
"
ls ~/memory-palace/归档/ | wc -l | xargs echo "归档包数:"
```

## 重要提醒

- **先归类，后衰减** — 确保每段记忆找到了正确的类目再处理时间规则
- **索引优先** — 每次只加载索引（~50 token），不加载全量记忆
- **记忆只给 AI 看** — 摘要内容不考虑人类可读性，精简高效即可
- **类目自然生长** — 跟随对话节奏动态扩展，不要一次性建完
- 如果当前对话没有产生值得保存的内容（纯闲聊），跳过后三步（3.4-3.6）
