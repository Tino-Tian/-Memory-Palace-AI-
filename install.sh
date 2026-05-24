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
echo -e "${GREEN}[1/7]${NC} 检测操作系统..."

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
echo -e "${GREEN}[2/7]${NC} 检测 sqlite3..."

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
echo -e "${GREEN}[3/7]${NC} 创建目录..."

INSTALL_DIR="$HOME/memory-palace"
mkdir -p "$INSTALL_DIR/hooks" "$INSTALL_DIR/归档"
echo -e "  ${GREEN}✓${NC} $INSTALL_DIR"

# ============================================================
# 4. 定位源文件目录
# ============================================================
echo -e "${GREEN}[4/7]${NC} 定位源文件..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null)"

# 如果无法获取脚本目录（curl | bash 模式），克隆仓库
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/init.sql" ]; then
    TMP_DIR=$(mktemp -d)
    echo -e "  ${YELLOW}→${NC} 从 GitHub 下载最新版本..."
    git clone --depth 1 https://github.com/Tino-Tian/-Memory-Palace-AI-.git "$TMP_DIR" 2>/dev/null || {
        echo -e "${RED}无法下载仓库，请手动 git clone 后运行 bash install.sh${NC}"
        exit 1
    }
    SCRIPT_DIR="$TMP_DIR"
fi

echo -e "  ${GREEN}✓${NC} 源文件: $SCRIPT_DIR"

# ============================================================
# 5. 复制项目文件
# ============================================================
echo -e "${GREEN}[5/7]${NC} 写入项目文件..."

# 核心文件和目录
cp "$SCRIPT_DIR/init.sql" "$INSTALL_DIR/init.sql"
cp "$SCRIPT_DIR/SKILL.md" "$INSTALL_DIR/SKILL.md"
cp "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/LICENSE" 2>/dev/null || true
cp "$SCRIPT_DIR/.gitignore" "$INSTALL_DIR/.gitignore" 2>/dev/null || true

# hooks
mkdir -p "$INSTALL_DIR/hooks"
for h in startup.sh stop.sh session-end.sh save-session.sh resume.sh; do
    [ -f "$SCRIPT_DIR/hooks/$h" ] && cp "$SCRIPT_DIR/hooks/$h" "$INSTALL_DIR/hooks/$h" && chmod +x "$INSTALL_DIR/hooks/$h"
done

# slash commands
if [ -d "$SCRIPT_DIR/commands" ]; then
    mkdir -p "$INSTALL_DIR/commands"
    cp -r "$SCRIPT_DIR/commands/" "$INSTALL_DIR/commands/"
fi

# migrations
if [ -d "$SCRIPT_DIR/migrations" ]; then
    mkdir -p "$INSTALL_DIR/migrations"
    cp "$SCRIPT_DIR/migrations/"*.sql "$INSTALL_DIR/migrations/" 2>/dev/null || true
fi

# 清理临时克隆
if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi

FILE_COUNT=$(find "$INSTALL_DIR" -type f | wc -l | xargs)
echo -e "  ${GREEN}✓${NC} 共写入 ${FILE_COUNT} 个文件"

# ============================================================
# 6. 初始化数据库
# ============================================================
echo -e "${GREEN}[6/7]${NC} 初始化数据库..."

sqlite3 "$INSTALL_DIR/palace.db" < "$INSTALL_DIR/init.sql"
echo -e "  ${GREEN}✓${NC} 数据库已就绪 ($INSTALL_DIR/palace.db)"

# 运行迁移（如果是旧库升级）
for migration in "$INSTALL_DIR/migrations/"*.sql; do
    [ -f "$migration" ] && sqlite3 "$INSTALL_DIR/palace.db" < "$migration" 2>/dev/null || true
done

# ============================================================
# 7. 自动配置 AI 平台
# ============================================================
echo -e "${GREEN}[7/7]${NC} 配置 AI 平台..."

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

# SessionStart 钩子（启动时加载索引）
cfg['hooks'].setdefault('SessionStart', [])
startup_cmd = 'bash \$HOME/memory-palace/hooks/startup.sh'
startup_exists = any(
    h.get('hooks', [{}])[0].get('command', '') == startup_cmd
    for h in cfg['hooks']['SessionStart']
)
if not startup_exists:
    cfg['hooks']['SessionStart'].append({
        'matcher': '',
        'hooks': [{'type': 'command', 'command': startup_cmd}]
    })

# Stop 钩子（每次回答后心跳检测）
cfg['hooks'].setdefault('Stop', [])
stop_cmd = 'bash \$HOME/memory-palace/hooks/stop.sh'
stop_exists = any(
    h.get('hooks', [{}])[0].get('command', '') == stop_cmd
    for h in cfg['hooks']['Stop']
)
if not stop_exists:
    cfg['hooks']['Stop'].append({
        'hooks': [{'type': 'command', 'command': stop_cmd}]
    })

# SessionEnd 钩子（退出时自动归档）
cfg['hooks'].setdefault('SessionEnd', [])
end_cmd = 'bash \$HOME/memory-palace/hooks/session-end.sh'
end_exists = any(
    h.get('hooks', [{}])[0].get('command', '') == end_cmd
    for h in cfg['hooks']['SessionEnd']
)
if not end_exists:
    cfg['hooks']['SessionEnd'].append({
        'hooks': [{'type': 'command', 'command': end_cmd}]
    })

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
" 2>/dev/null && CLAUDE_CONFIGURED=true
            if $CLAUDE_CONFIGURED; then
                echo -e "  ${GREEN}✓${NC} Claude Code 已自动配置 SessionStart/Stop/SessionEnd 钩子"
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

# 安装 slash commands
mkdir -p "$HOME/.claude/commands"
cp -r "$INSTALL_DIR/commands/" "$HOME/.claude/commands/" 2>/dev/null && \
    echo -e "  ${GREEN}✓${NC} Slash commands 已安装到 ~/.claude/commands/"

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
echo -e "${GREEN}下一步:${NC}"
echo "  1. 重启 Claude Code，记忆宫殿即生效"
echo "  2. 在对话中试试: /宫殿 状态"
echo ""
echo -e "${YELLOW}提示:${NC} 已将 SKILL.md 安装在 $INSTALL_DIR/"
echo -e "${YELLOW}      如使用 ChatGPT/Cursor 等其他 AI，将 SKILL.md 放入项目规则即可${NC}"
echo ""
