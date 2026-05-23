#!/usr/bin/env bash
# ============================================================
# 记忆宫殿 (Memory Palace) — 一键安装脚本
# 支持 macOS / Linux
#
# 使用方法:
#   bash install.sh
#   或
#   curl -fsSL <url> | bash
# ============================================================
set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=========================================="
echo "  记忆宫殿 (Memory Palace)"
echo "  AI 助手的长期记忆系统 — 一键安装"
echo "==========================================${NC}"
echo ""

# ============================================================
# 1. 检测操作系统
# ============================================================
echo -e "${GREEN}[1/6]${NC} 检测操作系统..."

OS="unknown"
case "$(uname -s)" in
    Darwin*)  OS="macOS";;
    Linux*)   OS="Linux";;
    MINGW*|MSYS*|CYGWIN*)
        echo -e "${RED}检测到 Windows Git Bash。${NC}"
        echo -e "${RED}请使用 PowerShell 运行 install.ps1 脚本。${NC}"
        exit 1
        ;;
    *)
        echo -e "${RED}不支持的操作系统: $(uname -s)${NC}"
        exit 1
        ;;
esac
echo -e "  ${GREEN}✓${NC} $OS"

# ============================================================
# 2. 检测 sqlite3
# ============================================================
echo -e "${GREEN}[2/6]${NC} 检测 sqlite3..."

if ! command -v sqlite3 &>/dev/null; then
    echo -e "${YELLOW}  sqlite3 未安装，正在自动安装...${NC}"
    case "$OS" in
        macOS)
            echo -e "${RED}  macOS 系统自带 sqlite3，如缺失请运行: xcode-select --install${NC}"
            exit 1
            ;;
        Linux)
            if command -v apt &>/dev/null; then
                sudo apt update -qq && sudo apt install -y -qq sqlite3
            elif command -v yum &>/dev/null; then
                sudo yum install -y sqlite3
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y sqlite3
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm sqlite3
            elif command -v apk &>/dev/null; then
                sudo apk add sqlite3
            else
                echo -e "${RED}  无法自动安装 sqlite3，请手动安装后重试${NC}"
                exit 1
            fi
            echo -e "  ${GREEN}✓${NC} sqlite3 安装完成"
            ;;
    esac
else
    echo -e "  ${GREEN}✓${NC} sqlite3 $(sqlite3 --version | head -1)"
fi

# ============================================================
# 3. 创建目录
# ============================================================
echo -e "${GREEN}[3/6]${NC} 创建目录..."

INSTALL_DIR="$HOME/memory-palace"
mkdir -p "$INSTALL_DIR/hooks" "$INSTALL_DIR/归档"
echo -e "  ${GREEN}✓${NC} $INSTALL_DIR"

# ============================================================
# 4. 写入项目文件
# ============================================================
echo -e "${GREEN}[4/6]${NC} 写入项目文件..."

# --- .gitignore ---
cat <<'GITIGNORE' > "$INSTALL_DIR/.gitignore"
# 个人记忆数据 — 绝对不能上传
palace.db

# 归档的记忆
归档/*.db.gz

# macOS
.DS_Store

# IDE
.vscode/
.idea/
GITIGNORE

# --- hooks/startup.sh ---
cat <<'STARTUP' > "$INSTALL_DIR/hooks/startup.sh"
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

# 3. 输出活跃记忆索引
echo "=== 记忆宫殿：活跃索引 ==="
echo ""
echo "▸ 活跃类目（近 3 天）："
sqlite3 "$DB" "SELECT '  ' || path FROM categories WHERE last_active >= date('now','-3 days') ORDER BY path;" 2>/dev/null || echo "  （无）"
echo ""
echo "▸ 近 3 天记忆条目："
sqlite3 "$DB" "SELECT '  [' || e.date || '] ' || c.path || ' | ' || e.keywords FROM entries e JOIN categories c ON e.category_id = c.id WHERE e.date >= date('now','-3 days') ORDER BY e.date DESC;" 2>/dev/null || echo "  （无）"
echo ""
echo "=== 索引加载完毕 ==="
STARTUP
chmod +x "$INSTALL_DIR/hooks/startup.sh"

# --- init.sql ---
cat <<'INITSQL' > "$INSTALL_DIR/init.sql"
-- 记忆宫殿 — 数据库初始化
-- 运行: sqlite3 ~/memory-palace/palace.db < ~/memory-palace/init.sql

-- 类目树
CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_id INTEGER REFERENCES categories(id),
    name TEXT NOT NULL,
    path TEXT UNIQUE NOT NULL,
    is_preset INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (date('now')),
    last_active TEXT DEFAULT (date('now'))
);

CREATE INDEX IF NOT EXISTS idx_categories_path ON categories(path);
CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories(parent_id);

-- 记忆条目
CREATE TABLE IF NOT EXISTS entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER NOT NULL REFERENCES categories(id),
    date TEXT DEFAULT (date('now')),
    level TEXT DEFAULT 'raw' CHECK(level IN ('raw','digest')),
    content TEXT NOT NULL,
    keywords TEXT,
    conversation_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_entries_category ON entries(category_id);
CREATE INDEX IF NOT EXISTS idx_entries_level ON entries(level);
CREATE INDEX IF NOT EXISTS idx_entries_date ON entries(date);

-- 对话索引
CREATE TABLE IF NOT EXISTS conversation_index (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT DEFAULT (date('now')),
    summary TEXT,
    entry_count INTEGER DEFAULT 0
);

-- ============================================================
-- 预设类目
-- ============================================================

INSERT OR IGNORE INTO categories (id, parent_id, name, path) VALUES (1, NULL, '工作', '工作');
INSERT OR IGNORE INTO categories (id, parent_id, name, path) VALUES (2, NULL, '生活', '生活');

-- 工作大类
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (1, '设计', '工作/设计');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (1, '运营', '工作/运营');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (1, '剪辑', '工作/剪辑');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (1, '短视频', '工作/短视频');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (1, '开发', '工作/开发');

-- 工作小类
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/设计'), 'UI设计', '工作/设计/UI设计');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/设计'), '平面设计', '工作/设计/平面设计');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/运营'), '活动策划', '工作/运营/活动策划');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/运营'), '内容运营', '工作/运营/内容运营');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/短视频'), '脚本', '工作/短视频/脚本');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/短视频'), '拍摄', '工作/短视频/拍摄');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/开发'), '前端', '工作/开发/前端');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='工作/开发'), '后端', '工作/开发/后端');

-- 生活大类
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (2, '科技/AI资讯', '生活/科技/AI资讯');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (2, '国际大事', '生活/国际大事');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (2, '行政动态', '生活/行政动态');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (2, '财经', '生活/财经');
INSERT OR IGNORE INTO categories (parent_id, name, path) VALUES (2, '健康', '生活/健康');

-- 生活小类
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='生活/国际大事'), '国家负责人讲话', '生活/国际大事/国家负责人讲话');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='生活/国际大事'), '国际冲突', '生活/国际大事/国际冲突');
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES ((SELECT id FROM categories WHERE path='生活/国际大事'), '外交动向', '生活/国际大事/外交动向');
INITSQL

# --- LICENSE ---
cat <<'LICENSE' > "$INSTALL_DIR/LICENSE"
MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
LICENSE

# --- SKILL.md ---
cat <<'SKILLMD' > "$INSTALL_DIR/SKILL.md"
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

**第三步：举个完整例子**

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
- **记忆只给 AI 看** — 摘要内容不考虑人类可读性，精简高效即可
- **类目自然生长** — 跟随对话节奏动态扩展，不要一次性建完
- 如果当前对话没有产生值得保存的内容（纯闲聊），跳过后三步（3.3-3.5）
SKILLMD

echo -e "  ${GREEN}✓${NC} 共写入 6 个文件"

# ============================================================
# 5. 初始化数据库
# ============================================================
echo -e "${GREEN}[5/6]${NC} 初始化数据库..."

sqlite3 "$INSTALL_DIR/palace.db" < "$INSTALL_DIR/init.sql"
echo -e "  ${GREEN}✓${NC} 数据库已就绪 ($INSTALL_DIR/palace.db)"

# ============================================================
# 6. 自动配置 AI 平台
# ============================================================
echo -e "${GREEN}[6/6]${NC} 配置 AI 平台..."

CLAUDE_CONFIGURED=false
CC_SETTINGS="$HOME/.claude/settings.json"

if [ -f "$CC_SETTINGS" ]; then
    if grep -q "memory-palace" "$CC_SETTINGS" 2>/dev/null; then
        echo -e "  ${YELLOW}⊘${NC} Claude Code 已配置，跳过"
    else
        if command -v python3 &>/dev/null; then
            python3 -c "
import json
path = '$CC_SETTINGS'
with open(path, 'r') as f:
    cfg = json.load(f)
cfg.setdefault('hooks', {})
cfg.setdefault('hooks', {}).setdefault('SessionStart', [])
# 防止重复
cmd = 'bash $HOME/memory-palace/hooks/startup.sh'
if not any(h.get('command','') == cmd for h in cfg['hooks']['SessionStart']):
    cfg['hooks']['SessionStart'].append({'type': 'command', 'command': cmd})
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
" 2>/dev/null && CLAUDE_CONFIGURED=true
            if $CLAUDE_CONFIGURED; then
                echo -e "  ${GREEN}✓${NC} Claude Code 已自动配置 SessionStart 钩子"
            fi
        fi
        if ! $CLAUDE_CONFIGURED; then
            echo -e "  ${YELLOW}!${NC} 无法自动修改 settings.json，请手动添加启动钩子"
            echo -e "  ${YELLOW}  参考: $INSTALL_DIR/README.md 中的安装说明${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}⊘${NC} 未检测到 Claude Code ($CC_SETTINGS 不存在)"
    echo -e "  ${CYAN}  提示:${NC} 如使用 ChatGPT 等其他 AI，将 SKILL.md 粘贴到系统提示词即可"
fi

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${CYAN}=========================================="
echo "  ✓✓✓ 记忆宫殿安装完成！"
echo "==========================================${NC}"
echo ""
echo -e "${GREEN}安装位置:${NC} $INSTALL_DIR"
echo ""
echo -e "${GREEN}已安装的文件:${NC}"
ls -1 "$INSTALL_DIR"/*.md "$INSTALL_DIR"/*.sql "$INSTALL_DIR"/hooks/*.sh 2>/dev/null | while read f; do
    echo "  $(basename "$f")"
done
echo ""
echo -e "${GREEN}接下来怎么做？${NC}"
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │  Claude Code 用户: 下次启动对话时自动加载                │"
echo "  │  ChatGPT 用户:   将 $INSTALL_DIR/SKILL.md 内容粘贴到    │"
echo "  │                   自定义指令/Custom Instructions           │"
echo "  │  Cursor 用户:    将 SKILL.md 加入项目规则文件              │"
echo "  │  其他 AI 平台:   将 SKILL.md 写入 system prompt             │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo -e "${CYAN}手动管理命令（在 Claude Code 中）:${NC}"
echo "  /宫殿 查找 <关键词>    搜索历史记忆（含归档）"
echo "  /宫殿 树                查看完整类目树"
echo "  /宫殿 状态              查看数据库统计"
echo "  /宫殿 类目 <路径>       查看指定类目下的记忆"
echo ""
