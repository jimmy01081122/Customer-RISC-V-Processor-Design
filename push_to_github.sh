#!/usr/bin/env bash
set -e

# 本地專案資料夾的絕對路徑（改成你的）
PROJECT_PATH="/Users/jimmychang/space/verilog"

# GitHub 上空 repo 的 URL（SSH 或 HTTPS，改成你的）
REMOTE_URL="git@github.com:jimmy01081122/Customer-RISC-V-Processor-Design.git"

# 初次上傳要用的 branch 名稱
BRANCH_NAME="main"

echo "切換到專案資料夾：$PROJECT_PATH"
cd "$PROJECT_PATH"

# 如果還不是 git repository，初始化
if [ ! -d ".git" ]; then
    echo "偵測不到 .git 資料夾，執行 git init..."
    git init
fi

# 設定預設分支名稱
echo "設定分支名稱為 $BRANCH_NAME..."
git branch -M "$BRANCH_NAME" || true

# 設定 remote origin（若已存在就改成新的 URL）
if git remote get-url origin > /dev/null 2>&1; then
    echo "已存在 origin，更新其 URL..."
    git remote set-url origin "$REMOTE_URL"
else
    echo "新增 origin..."
    git remote add origin "$REMOTE_URL"
fi

# 加入所有檔案並 commit
echo "加入所有檔案..."
git add .

# 若沒有任何改動，git commit 會失敗，因此先檢查 staged 狀態
if git diff --cached --quiet; then
    echo "沒有新的變更需要 commit，略過 commit。"
else
    echo "建立初始 commit..."
    git commit -m "Initial commit"
fi

# 推上 GitHub
echo "推送到 GitHub 的 $BRANCH_NAME 分支..."
git push -u origin "$BRANCH_NAME"

echo "完成。"
