-- 迁移 001：修复"科技/AI资讯"路径不一致问题
-- 原名含斜杠导致路径解析歧义，拆为"生活/科技/AI资讯"的正确三层结构

-- 先创建中间层"生活/科技"（如果还不存在）
INSERT OR IGNORE INTO categories (parent_id, name, path)
    VALUES (2, '科技', '生活/科技');

-- 把原名含斜杠的类目迁移到正确路径下
UPDATE categories
SET parent_id = (SELECT id FROM categories WHERE path = '生活/科技'),
    name = 'AI资讯',
    path = '生活/科技/AI资讯'
WHERE path = '生活/科技/AI资讯' AND name = '科技/AI资讯';

-- 验证
SELECT '迁移 001 完成：科技/AI资讯 路径已修复' AS status;
SELECT id, parent_id, name, path FROM categories WHERE path LIKE '生活/科技%';
