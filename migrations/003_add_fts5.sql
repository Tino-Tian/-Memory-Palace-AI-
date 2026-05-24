-- 迁移 003：添加 FTS5 全文搜索
CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
    content,
    keywords,
    content='entries',
    content_rowid='id'
);

-- 同步触发器
CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
    INSERT INTO entries_fts(rowid, content, keywords) VALUES (new.id, new.content, new.keywords);
END;

CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, content, keywords) VALUES('delete', old.id, old.content, old.keywords);
END;

CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
    INSERT INTO entries_fts(entries_fts, rowid, content, keywords) VALUES('delete', old.id, old.content, old.keywords);
    INSERT INTO entries_fts(rowid, content, keywords) VALUES (new.id, new.content, new.keywords);
END;

-- 重建现有数据索引（如果 entries 表中已有数据）
INSERT INTO entries_fts(entries_fts) VALUES('rebuild');

SELECT '迁移 003 完成：FTS5 全文搜索已启用' AS status;
