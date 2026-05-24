#!/usr/bin/env bash
# 记忆宫殿 — 会话快照保存
# 用法: save-session.sh <session-id>
# 前置条件: brief 和 full 文件已由 Claude 写好了
#    ~/.claude/projects/-Users-mac/memory/session-resume-brief.md
#    ~/.claude/projects/-Users-mac/memory/session-resume-full.md

SESSION_ID="${1:-unknown}"

python3 <<PYEOF
import json, os, sqlite3

session_id = '${SESSION_ID}'
home = os.path.expanduser('~')
db_path = f'{home}/memory-palace/palace.db'
brief_file = f'{home}/.claude/projects/-Users-mac/memory/session-resume-brief.md'
full_file = f'{home}/.claude/projects/-Users-mac/memory/session-resume-full.md'
settings_file = f'{home}/.claude/settings.json'

# 读取文件
def read_file(path):
    if os.path.exists(path):
        with open(path) as f:
            return f.read()
    return ''

brief = read_file(brief_file)
full = read_file(full_file)

if not brief.strip():
    print('错误：brief 文件为空')
    exit(1)

# 1. 写入 SQLite
conn = sqlite3.connect(db_path)
conn.execute('''
    INSERT INTO session_snapshots (session_id, brief, full_content, status)
    VALUES (?, ?, ?, 'pending')
''', (session_id, brief, full))
conn.commit()
conn.close()
print('已写入数据库')

# 2. 注册一次性恢复钩子
if os.path.exists(settings_file):
    with open(settings_file) as f:
        s = json.load(f)

    s.setdefault('hooks', {}).setdefault('SessionStart', [])

    already = any(
        'resume.sh' in h.get('hooks', [{}])[0].get('command', '')
        for h in s['hooks']['SessionStart']
    )

    if not already:
        s['hooks']['SessionStart'].append({
            'matcher': '',
            'hooks': [{
                'type': 'command',
                'command': '\$HOME/memory-palace/hooks/resume.sh'
            }]
        })
        with open(settings_file, 'w') as f:
            json.dump(s, f, indent=2, ensure_ascii=False)
        print('已注册一次性恢复钩子')
    else:
        print('恢复钩子已存在，跳过')
else:
    print('settings.json 不存在，无法注册钩子')

print(f'会话快照保存完成: {session_id}')
PYEOF
