#!/usr/bin/env bash
# 记忆宫殿 — 一次性恢复钩子
# 启动时自动检测待恢复的快照，注入上下文后自动卸载

python3 <<'PYEOF'
import json, os, sqlite3

home = os.path.expanduser('~')
db_path = f'{home}/memory-palace/palace.db'
settings_file = f'{home}/.claude/settings.json'

# 检查是否有 pending 快照
if not os.path.exists(db_path):
    exit(0)

conn = sqlite3.connect(db_path)
cur = conn.execute(
    "SELECT id, session_id, brief FROM session_snapshots WHERE status='pending' ORDER BY id DESC LIMIT 1"
)
row = cur.fetchone()
conn.close()

if not row:
    exit(0)

snap_id, session_id, brief = row

print('=== 上次工作现场恢复 ===')
print('')
print(brief)
print('')
print('（完整记录可让我读取 session-resume-full.md 获取）')
print('=== 恢复完毕 ===')

# 只标记本次读取的那一条为已加载
conn = sqlite3.connect(db_path)
conn.execute("UPDATE session_snapshots SET status='loaded' WHERE id=?", (snap_id,))
conn.commit()
conn.close()

# 清理 brief 文件
brief_file = f'{home}/.claude/projects/-Users-mac/memory/session-resume-brief.md'
if os.path.exists(brief_file):
    os.remove(brief_file)

# 从 settings.json 中移除自身 hook
if os.path.exists(settings_file):
    with open(settings_file) as f:
        s = json.load(f)

    if 'hooks' in s and 'SessionStart' in s['hooks']:
        original_count = len(s['hooks']['SessionStart'])
        s['hooks']['SessionStart'] = [
            h for h in s['hooks']['SessionStart']
            if 'resume.sh' not in str(h)
        ]
        # 清理空 hook 组
        s['hooks']['SessionStart'] = [
            h for h in s['hooks']['SessionStart']
            if h.get('hooks')
        ]
        if not s['hooks']['SessionStart']:
            del s['hooks']['SessionStart']

        if len(s['hooks']['SessionStart']) != original_count:
            with open(settings_file, 'w') as f:
                json.dump(s, f, indent=2, ensure_ascii=False)
PYEOF
