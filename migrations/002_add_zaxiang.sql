-- 迁移 002：补充"杂项"默认类目
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES (NULL, '杂项', '杂项');

SELECT '迁移 002 完成：杂项类目已添加' AS status;
