#!/bin/bash

# ===============================================
# Wireproxy 自動安裝腳本
# 兼容 Linux (amd64/arm64) 和 macOS (amd64/arm64)
# ===============================================

REPO="whyvl/wireproxy"
INSTALL_DIR="/usr/local/bin"

# --- 1. 檢查所需的依賴 ---
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "🔴 錯誤: 需要 $1 才能運行此腳本。請先安裝。"
        exit 1
    fi
}
check_dependency "curl"
check_dependency "tar"

# --- 2. 確定 OS 和 架構 ---
echo "➡️ 正在檢測系統信息..."
case "$(uname -s)" in
    Linux*)     OS=linux;;
    Darwin*)    OS=darwin;;
    *)          echo "🔴 錯誤: 不支援的作業系統: $(uname -s)"; exit 1;;
esac

case "$(uname -m)" in
    x86_64)     ARCH=amd64;;
    arm64|aarch64) ARCH=arm64;;
    *)          echo "🔴 錯誤: 不支援的架構: $(uname -m)"; exit 1;;
esac

FILENAME="wireproxy_${OS}_${ARCH}"
echo "系統類型: ${OS} / ${ARCH}"

# --- 3. 獲取最新版本號 ---
echo "➡️ 正在查詢 ${REPO} 的最新版本..."
# 使用 GitHub API 獲取最新的 tag_name
LATEST_VERSION=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)

if [ -z "$LATEST_VERSION" ]; then
    echo "🔴 錯誤: 無法從 GitHub 獲取最新版本號。請檢查網路連線或儲存庫名稱。"
    exit 1
fi

echo "✅ 找到最新版本: $LATEST_VERSION"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_VERSION/${FILENAME}.tar.gz"

# --- 4. 下載、解壓縮並安裝 ---
echo "➡️ 正在從 ${DOWNLOAD_URL} 下載..."
if ! curl -L "$DOWNLOAD_URL" -o "/tmp/${FILENAME}.tar.gz"; then
    echo "🔴 錯誤: 下載失敗。"
    exit 1
fi

# 臨時解壓縮目錄
TEMP_DIR=$(mktemp -d)

echo "➡️ 正在解壓縮並移動到 ${INSTALL_DIR}..."
if ! tar -xzf "/tmp/${FILENAME}.tar.gz" -C "$TEMP_DIR"; then
    echo "🔴 錯誤: 解壓縮失敗。"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 尋找解壓後的 'wireproxy' 二進制文件
BINARY_PATH=$(find "$TEMP_DIR" -type f -name "wireproxy" -print -quit)

if [ -z "$BINARY_PATH" ]; then
    echo "🔴 錯誤: 在解壓文件中找不到 'wireproxy' 二進制文件。"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 嘗試安裝，因為安裝到 /usr/local/bin 需要 root 權限，所以使用 sudo
if ! sudo mv "$BINARY_PATH" "$INSTALL_DIR/wireproxy"; then
    echo "🔴 錯誤: 移動文件到 ${INSTALL_DIR} 失敗。請檢查您的權限或手動執行 'sudo mv ...'。"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 設置可執行權限
sudo chmod +x "$INSTALL_DIR/wireproxy"

# 清理臨時文件
rm -rf "$TEMP_DIR"
rm "/tmp/${FILENAME}.tar.gz"

echo ""
echo "✨ 恭喜！Wireproxy $LATEST_VERSION 已成功安裝到 $INSTALL_DIR/wireproxy"
echo "---"
wireproxy -v 2>/dev/null
