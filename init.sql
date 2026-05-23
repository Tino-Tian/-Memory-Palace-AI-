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
