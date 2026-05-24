# ============================================================
# 记忆宫殿 (Memory Palace) — 一键安装脚本 (Windows)
# 支持 Windows 10/11 + PowerShell 5.1+
#
# 使用方法:
#   右键 install.ps1 → 使用 PowerShell 运行
#   或: powershell -ExecutionPolicy Bypass -File install.ps1
# ============================================================
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "记忆宫殿 — 安装中..."

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  记忆宫殿 (Memory Palace)" -ForegroundColor Cyan
Write-Host "  AI 助手的长期记忆系统 — 一键安装" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. 检测操作系统
# ============================================================
Write-Host "[1/6] 检测操作系统..." -ForegroundColor Green
Write-Host "  ✓ Windows $([Environment]::OSVersion.Version)" -ForegroundColor Green

# ============================================================
# 2. 检测 sqlite3
# ============================================================
Write-Host "[2/6] 检测 sqlite3..." -ForegroundColor Green

$sqlite3 = Get-Command sqlite3 -ErrorAction SilentlyContinue
if (-not $sqlite3) {
    Write-Host "  sqlite3 未安装，正在自动安装..." -ForegroundColor Yellow

    # 尝试 winget
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "  使用 winget 安装 sqlite3..." -ForegroundColor Yellow
        winget install sqlite.sqlite --accept-package-agreements --silent
        # 刷新环境变量
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    else {
        Write-Host "  winget 不可用，尝试 chocolatey..." -ForegroundColor Yellow
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if ($choco) {
            choco install sqlite -y
        }
        else {
            Write-Host "  -------------------------------------------------------" -ForegroundColor Red
            Write-Host "  无法自动安装 sqlite3。请手动操作:" -ForegroundColor Red
            Write-Host "  1. 访问 https://www.sqlite.org/download.html" -ForegroundColor Red
            Write-Host "  2. 下载 sqlite-tools-win32-x64-*.zip" -ForegroundColor Red
            Write-Host "  3. 解压后将 sqlite3.exe 放入 C:\Windows\System32\" -ForegroundColor Red
            Write-Host "  4. 重新运行此脚本" -ForegroundColor Red
            Write-Host "  -------------------------------------------------------" -ForegroundColor Red
            exit 1
        }
    }

    # 重新检测
    $sqlite3 = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (-not $sqlite3) {
        Write-Host "  安装失败，请手动安装 sqlite3 后重试" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  ✓ sqlite3 已就绪" -ForegroundColor Green

# ============================================================
# 3. 创建目录
# ============================================================
$INSTALL_DIR = "$env:USERPROFILE\memory-palace"
Write-Host "[3/6] 创建目录: $INSTALL_DIR" -ForegroundColor Green
New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\hooks", "$INSTALL_DIR\归档" | Out-Null
Write-Host "  ✓ 目录已创建" -ForegroundColor Green

# ============================================================
# 4. 定位源文件
# ============================================================
Write-Host "[4/6] 定位源文件..." -ForegroundColor Green

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = Get-Location }

# 检查是否在仓库目录中
if (-not (Test-Path "$SCRIPT_DIR\init.sql")) {
    Write-Host "  → 从 GitHub 下载最新版本..." -ForegroundColor Yellow
    $TMP_DIR = Join-Path $env:TEMP "memory-palace-$(Get-Random)"
    try {
        Invoke-WebRequest -Uri "https://github.com/Tino-Tian/-Memory-Palace-AI-/archive/refs/heads/main.zip" -OutFile "$env:TEMP\mp.zip"
        Expand-Archive -Path "$env:TEMP\mp.zip" -DestinationPath $TMP_DIR -Force
        $EXTRACTED = Get-ChildItem $TMP_DIR | Select-Object -First 1
        $SCRIPT_DIR = $EXTRACTED.FullName
        Remove-Item "$env:TEMP\mp.zip" -Force
    } catch {
        Write-Host "  无法下载仓库，请手动 git clone 后运行 .\install.ps1" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  ✓ 源文件: $SCRIPT_DIR" -ForegroundColor Green

# ============================================================
# 5. 复制项目文件
# ============================================================
Write-Host "[5/6] 复制项目文件..." -ForegroundColor Green

$fileCount = 0

# 核心文件
foreach ($f in @("init.sql", "SKILL.md", "LICENSE", ".gitignore")) {
    $src = Join-Path $SCRIPT_DIR $f
    if (Test-Path $src) {
        Copy-Item $src "$INSTALL_DIR\$f" -Force
        $fileCount++
    }
}

# hooks
foreach ($h in @("startup.sh", "startup.ps1", "stop.sh", "session-end.sh", "save-session.sh", "resume.sh")) {
    $src = Join-Path $SCRIPT_DIR "hooks\$h"
    if (Test-Path $src) {
        Copy-Item $src "$INSTALL_DIR\hooks\$h" -Force
        $fileCount++
    }
}

# commands
$cmdSrc = Join-Path $SCRIPT_DIR "commands"
if (Test-Path $cmdSrc) {
    Copy-Item $cmdSrc "$INSTALL_DIR\commands" -Recurse -Force
}

# migrations
$migSrc = Join-Path $SCRIPT_DIR "migrations"
if (Test-Path $migSrc) {
    New-Item -ItemType Directory -Force -Path "$INSTALL_DIR\migrations" | Out-Null
    Copy-Item "$migSrc\*.sql" "$INSTALL_DIR\migrations\" -Force
}

# 清理临时下载
if ($TMP_DIR -and (Test-Path $TMP_DIR)) {
    Remove-Item $TMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "  ✓ 共写入 $fileCount 个文件" -ForegroundColor Green

# ============================================================
# 6. 初始化数据库 + 运行迁移
# ============================================================
Write-Host "[6/6] 初始化数据库..." -ForegroundColor Green

& sqlite3 "$INSTALL_DIR\palace.db" ".read $INSTALL_DIR\init.sql"

# 运行迁移（如果是旧库升级）
$migDir = "$INSTALL_DIR\migrations"
if (Test-Path $migDir) {
    Get-ChildItem "$migDir\*.sql" | ForEach-Object {
        & sqlite3 "$INSTALL_DIR\palace.db" ".read $($_.FullName)" 2>$null
    }
}

Write-Host "  ✓ 数据库已就绪 ($INSTALL_DIR\palace.db)" -ForegroundColor Green

# ============================================================
# 完成
# ============================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  ✓✓✓ 记忆宫殿安装完成！" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "安装位置: $INSTALL_DIR" -ForegroundColor Green
Write-Host ""
Write-Host "已安装的文件:" -ForegroundColor Green
Get-ChildItem "$INSTALL_DIR\*.md", "$INSTALL_DIR\*.sql", "$INSTALL_DIR\hooks\*" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  $($_.Name)" -ForegroundColor White
}
Write-Host ""
Write-Host "接下来怎么做？" -ForegroundColor Green
Write-Host "  ┌─────────────────────────────────────────────────────────────┐"
Write-Host "  │  Claude Code (WSL):  下次启动对话时自动加载               │"
Write-Host "  │  Claude Code (原生): 在 settings.json 中配置钩子:         │"
Write-Host "  │      powershell -File $INSTALL_DIR\hooks\startup.ps1       │"
Write-Host "  │  ChatGPT 用户:       将 $INSTALL_DIR\SKILL.md 内容粘贴到  │"
Write-Host "  │                      自定义指令/Custom Instructions         │"
Write-Host "  │  Cursor 用户:        将 SKILL.md 加入项目规则文件          │"
Write-Host "  │  其他 AI 平台:       将 SKILL.md 写入 system prompt         │"
Write-Host "  └─────────────────────────────────────────────────────────────┘"
Write-Host ""
Write-Host "按任意键退出..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
