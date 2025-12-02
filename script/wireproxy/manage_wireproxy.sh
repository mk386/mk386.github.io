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
# ------------------------------------------------------------------------------
WGConfig = /etc/wireproxy/wireguard.conf

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
