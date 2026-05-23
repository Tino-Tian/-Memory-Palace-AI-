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

### 3.2 归类（递归语义分析）

归类不是机械的关键词匹配。你需要像人一样"读懂"这段对话到底在讲什么，然后沿着类目树逐层往下走，每一步判断：它属于哪个现有分支？还是需要在当前层级开辟一个新分支？

按以下流程进行：

**第一步：语义分析**

先通读这段对话内容，提炼出它的核心主题。比如"特朗普五月访华跟习近平聊了什么"——核心主题是"国际政治人物之间的外交交流"，涉及人物是特朗普和习近平。

注意：不是看关键词，是看内容在讲什么。同一段话可能涉及多个主题，那就各自拆分归入。

**第二步：从根开始递归匹配**

从根类目（如"工作""生活"）出发，按以下逻辑逐层往下走：

```
对于当前层级，列出它的所有子类目：
  ├─ 内容能放入某个现有子类吗？
  │   ├─ 能 → 进入该子类，继续递归（重复第二步）
  │   └─ 不能 → 当前层级就是"分叉点"
  │       ├─ 内容还能进一步细分吗？
  │       │   ├─ 能 → 在当前层级下创建一个新子类目，然后进入新子类继续递归
  │       │   └─ 不能 → 内容直接归入当前层级
```

**第三���：举个完整例子**

假设类目树现有：

```
生活
└── 国际大事
    ├── 国家负责人讲话
    ├── 国际冲突
    └── 外交动向
```

现在有一段内容是"特朗普五月访华，跟习近平就贸易问题谈了三个小时"。

分析过程：
1. 根层级：属于"生活"还是"工作"？→ 生活
2. 打开"生活"：看到"国际大事""科技/AI资讯""财经"等子类 → 属于"国际大事"
3. 进入"国际大事"：看到"国家负责人讲话""国际冲突""外交动向"三个子类
   - "国家负责人讲话"——不对，这是两国领导人会晤，不是单方面讲话
   - "国际冲突"——不对，这是合作交流
   - "外交动向"——接近，但"外交动向"比较宽泛，而这条内容聚焦在两个具体人物身上
4. 判断：现有子类都不完全匹配 → 当前层级（国际大事）是分叉点 → 内容可以按"人物"维度进一步细分 → 在"国际大事"下创建新子类"特朗普"
5. 内容归入：生活/国际大事/特朗普

如果后续又聊了"特朗普跟金正恩在新加坡会面"，分析流程变成：
1. 生活 → 国际大事 → 直接归入"特朗普"（已有，匹配）

如果聊的是"拜登宣布退出2028大选"：
1. 生活 → 国际大事 → 现有子类都不完全匹配 → 判断这是"按人物分"的类目，拜登也是政治人物 → 创建"拜登"子类

如果聊的是"联合国通过了一项气候决议"：
1. 生活 → 国际大事 → 不属于个人行为，属于机构决议 → 现有子类都不匹配 → 考虑创建"联合国"或"国际组织"子类（根据后续是否经常聊到此类话题来决定命名的宽窄）

**第四步：命名新类目的原则**

- 简短、通用——能被同类话题复用，而不是只适用于这一次对话
- 命名反映的是"话题维度"而非"一次性事件"——用"特朗普"而非"特朗普5月访华"
- 如果拿不准该建在哪一层，宁可建在偏深的一层（子类可以随时往上提）

**第五步：创建新类目的 SQL**

```bash
sqlite3 ~/memory-palace/palace.db "
INSERT INTO categories (parent_id, name, path, is_preset)
VALUES (
  (SELECT id FROM categories WHERE path='父级的完整路径'),
  '新类目名称',
  '父级的完整路径/新类目名称',
  0
);
"
```

**第六步：兜底规则**

如果内容完全无法匹配任何现有门类（连"工作"和"生活"都分不进去），暂时放入"杂项"（需要先确保杂项类目存在）。下次归档时提醒用户确认这些杂项内容的归属。

### 3.3 写入记忆

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

### 3.4 时间衰减

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

### 3.5 更新类目活跃时间

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

**`/宫殿 新建类目 <路径>`** — 手动创建类目（按 3.2 第五步的 SQL）

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
- **记忆只给 Agent 看** — 摘要内容不考虑人类可读性，精简高效即可
- **类目自然生长** — 跟随对话节奏动态扩展，不要一次性建完
- **每次开工前必报预估并分解步骤** — 哪怕只有一个步骤也要列出。格式：步骤表（每步含最短/最长时间）+ 总计时间和 Token 范围。任务结束后报实际耗时和实际 Token。（详见工作流程规则）
- 如果当前对话没有产生值得保存的内容（纯闲聊），跳过后三步（3.3-3.5）
