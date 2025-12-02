這是一個專為 Debian/Ubuntu 設計的 Robust 腳本。它包含完整的錯誤處理、架構偵測 (amd64/arm64)，並嚴格遵循你指定的路徑結構。

為了滿足「引用 WireGuard 配置」的需求，由於 `wireproxy` 原生不支援 `include` 指令，此腳本採用的策略是：**產生一個標準的 `wireproxy.conf`，並在其中清楚標示 WireGuard 區塊與 Service 區塊**。

### 腳本功能特點：

1.  **架構自動偵測**：自動判斷是 x86\_64 還是 ARM64 下載對應 Binary。
2.  **安全性**：建立專屬 `wireproxy` 系統帳戶，並鎖定設定檔權限 (600)。
3.  **Systemd 整合**：建立標準 Service，並確保網路啟動後才執行。
4.  **乾淨移除**：Uninstall 模式會徹底清除 Binary、使用者、設定檔與服務。

### 腳本內容 (`manage_wireproxy.sh`)

你可以將以下內容存為 `manage_wireproxy.sh`，然後給予執行權限 (`chmod +x manage_wireproxy.sh`)。

```bash
#!/bin/bash

# ==============================================================================
# Wireproxy Management Script (Install/Uninstall) for Debian/Ubuntu
# Repository: https://github.com/whyvl/wireproxy
# ==============================================================================

# --- Configuration Variables ---
APP_NAME="wireproxy"
INSTALL_DIR="/usr/local/bin"
BINARY_PATH="${INSTALL_DIR}/${APP_NAME}"

CONFIG_DIR="/etc/wireproxy"
CONFIG_FILE="${CONFIG_DIR}/wireproxy.conf"
# Note: wireproxy does not natively support 'include', so we treat this path 
# as a reference or a place where users might mistakenly look.
# The script will consolidate configs into CONFIG_FILE.
WG_REF_FILE="${CONFIG_DIR}/wireguard.conf" 

SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
SYS_USER="wireproxy"

# GitHub Release URL (Latest)
BASE_URL="https://github.com/whyvl/wireproxy/releases/latest/download"

# --- Helper Functions ---
log_info() { echo -e "\033[32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[33m[WARN]\033[0m $1"; }
log_err()  { echo -e "\033[31m[ERROR]\033[0m $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_err "Please run as root (sudo)."
        exit 1
    fi
}

detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  DOWNLOAD_ARCH="amd64" ;;
        aarch64) DOWNLOAD_ARCH="arm64" ;;
        arm64)   DOWNLOAD_ARCH="arm64" ;;
        *)       log_err "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
}

# --- Task: Install ---
do_install() {
    log_info "Starting installation..."
    
    # 1. Install Dependencies
    log_info "Checking dependencies..."
    if ! command -v curl &> /dev/null || ! command -v tar &> /dev/null; then
        apt-get update && apt-get install -y curl tar
    fi

    # 2. Download and Install Binary
    detect_arch
    local filename="wireproxy_linux_${DOWNLOAD_ARCH}.tar.gz"
    local url="${BASE_URL}/${filename}"
    
    log_info "Downloading ${filename}..."
    tmp_dir=$(mktemp -d)
    if curl -L -s -o "${tmp_dir}/${filename}" "$url"; then
        tar -xzf "${tmp_dir}/${filename}" -C "$tmp_dir"
        # Find binary (handling slight variations in tar structure)
        if [ -f "${tmp_dir}/wireproxy" ]; then
            mv "${tmp_dir}/wireproxy" "$BINARY_PATH"
        else
            # Try to find it if it's inside a folder
            find "$tmp_dir" -name "wireproxy" -type f -exec mv {} "$BINARY_PATH" \;
        fi
        
        if [ ! -f "$BINARY_PATH" ]; then
            log_err "Failed to extract binary."
            rm -rf "$tmp_dir"
            exit 1
        fi
        
        chmod +x "$BINARY_PATH"
        rm -rf "$tmp_dir"
        log_info "Binary installed to $BINARY_PATH"
    else
        log_err "Download failed. Check your internet connection."
        rm -rf "$tmp_dir"
        exit 1
    fi

    # 3. Create System User
    if ! id "$SYS_USER" &>/dev/null; then
        useradd -r -s /bin/false -M "$SYS_USER"
        log_info "Created system user: $SYS_USER"
    fi

    # 4. Create Configuration
    mkdir -p "$CONFIG_DIR"
    
    # Generate dummy wireguard.conf for reference (User requested structure)
    if [ ! -f "$WG_REF_FILE" ]; then
        cat > "$WG_REF_FILE" <<EOF
# --- WireGuard Configuration Reference ---
# Copy the content below into the [Interface] and [Peer] sections 
# of $CONFIG_FILE.
#
# [Interface]
# PrivateKey = <YOUR_PRIVATE_KEY>
# Address = 10.10.10.2/32
# DNS = 1.1.1.1
#
# [Peer]
# PublicKey = <SERVER_PUBLIC_KEY>
# Endpoint = 1.2.3.4:51820
# AllowedIPs = 0.0.0.0/0
# PersistentKeepalive = 25
EOF
        log_info "Created reference file at $WG_REF_FILE"
    fi

    # Generate main wireproxy.conf if not exists
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
# ==============================================================================
# Wireproxy Configuration File
# Path: $CONFIG_FILE
# Docs: https://github.com/whyvl/wireproxy
# ==============================================================================

# ------------------------------------------------------------------------------
# SECTION 1: WireGuard Configuration
# (Paste your standard WireGuard Interface and Peer settings here)
# ------------------------------------------------------------------------------
[Interface]
# PrivateKey is required
PrivateKey = ChangeMePrivateKeyExample1234567890=
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
# Server Public Key
PublicKey = ChangeMePublicKeyExample1234567890=
# Server Endpoint (IP:Port)
Endpoint = 127.0.0.1:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

# ------------------------------------------------------------------------------
# SECTION 2: Wireproxy Daemon Configuration
# ------------------------------------------------------------------------------

# SOCKS5 Proxy Server
# Note: By default, no authentication is enabled.
[Socks5]
BindAddress = 127.0.0.1:1080
# Username = myuser
# Password = mypassword

# HTTP Proxy Server (Optional - Uncomment to enable)
# [Http]
# BindAddress = 127.0.0.1:3128

EOF
        log_info "Created default config at $CONFIG_FILE"
    else
        log_warn "Config file already exists at $CONFIG_FILE. Skipping creation."
    fi

    # Set permissions (Critical for private keys)
    chown -R "$SYS_USER":"$SYS_USER" "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    chmod 600 "$CONFIG_FILE"

    # 5. Create Systemd Service
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Wireproxy Daemon (WireGuard user-space client)
Documentation=https://github.com/whyvl/wireproxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SYS_USER
Group=$SYS_USER
# Run in foreground, systemd handles logging
ExecStart=$BINARY_PATH --config $CONFIG_FILE
Restart=on-failure
RestartSec=5s

# Security Hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=yes
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF
    log_info "Created systemd service at $SERVICE_FILE"

    # 6. Enable and Start
    systemctl daemon-reload
    systemctl enable "$APP_NAME"
    
    log_info "Installation complete!"
    echo ""
    echo "NEXT STEPS:"
    echo "1. Edit the config file with your WireGuard keys:"
    echo "   nano $CONFIG_FILE"
    echo "2. Start the service:"
    echo "   systemctl start $APP_NAME"
    echo "3. Check status:"
    echo "   systemctl status $APP_NAME"
}

# --- Task: Uninstall ---
do_uninstall() {
    log_info "Starting uninstallation..."

    # 1. Stop and Disable Service
    if systemctl is-active --quiet "$APP_NAME"; then
        systemctl stop "$APP_NAME"
        log_info "Service stopped."
    fi
    if systemctl is-enabled --quiet "$APP_NAME"; then
        systemctl disable "$APP_NAME"
        log_info "Service disabled."
    fi

    # 2. Remove Files
    if [ -f "$SERVICE_FILE" ]; then
        rm "$SERVICE_FILE"
        log_info "Removed service file."
    fi

    if [ -f "$BINARY_PATH" ]; then
        rm "$BINARY_PATH"
        log_info "Removed binary."
    fi

    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        log_info "Removed config directory."
    fi

    # 3. Remove User
    if id "$SYS_USER" &>/dev/null; then
        userdel "$SYS_USER"
        log_info "Removed system user."
    fi

    # 4. Reload Systemd
    systemctl daemon-reload
    log_info "Uninstallation complete. System is clean."
}

# --- Main Logic ---
check_root

case "$1" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        echo "  install   : Install wireproxy, setup config, and enable service."
        echo "  uninstall : Remove wireproxy and all related files completely."
        exit 1
        ;;
esac
```

### 如何使用此腳本

1.  **儲存腳本**：
    `vim wireproxy_manager.sh` (貼上程式碼)
2.  **給予權限**：
    `chmod +x wireproxy_manager.sh`
3.  **執行安裝**：
    `sudo ./wireproxy_manager.sh install`
4.  **設定配置**：
    腳本執行完後，請務必編輯 `/etc/wireproxy/wireproxy.conf`，填入你的 PrivateKey、Endpoint 等資訊。
5.  **啟動服務**：
    `sudo systemctl start wireproxy`
6.  **移除軟體** (如果需要)：
    `sudo ./wireproxy_manager.sh uninstall`

### 關於配置檔案的設計說明

我在腳本中生成了 `/etc/wireproxy/wireproxy.conf`，其結構如下：

1.  **`[Interface]` & `[Peer]`**：這部分對應你提到的 `wireguard.conf` 內容。由於 `wireproxy` 執行時**只接受一個設定檔參數**，最穩定的作法是將這些內容直接寫在 `wireproxy.conf` 內。
2.  **`[Socks5]`**：這部分是 `wireproxy` 特有的 Daemon 設定，預設綁定 `127.0.0.1:1080`，無密碼。

如果你手上有現成的 WireGuard 設定檔 (例如 `wg0.conf`)，你只需要把裡面的內容複製貼上到 `/etc/wireproxy/wireproxy.conf` 的上半部即可。
