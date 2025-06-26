#!/bin/bash

# Default values
USERNAME="user"
PORT="3128"
PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

# Parse command line arguments
while getopts "u:p:P:" opt; do
  case $opt in
    u) USERNAME="$OPTARG" ;;
    p) PASSWORD="$OPTARG" ;;
    P) PORT="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done

# Validate port number
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "Error: Port must be a number between 1 and 65535" >&2
  exit 1
fi

# Install dependencies
echo "Updating system and installing dependencies..."
sudo apt update
sudo apt install -y snapd net-tools

# Install core and gost
echo "Installing core and gost..."
sudo snap install core
sudo snap install gost

# Create gost secrets file
echo "Creating gost secrets configuration..."
SECRETS_DIR="/var/snap/gost/common"
SECRETS_FILE="$SECRETS_DIR/gost-secrets.txt"

# Create directory if it doesn't exist
sudo mkdir -p "$SECRETS_DIR"

sudo bash -c "cat > $SECRETS_FILE" << EOF
# period for live reloading
reload      10s

# username password
$USERNAME   $PASSWORD
EOF

# Set proper permissions for secrets file
sudo chmod 600 "$SECRETS_FILE"
sudo chown root:root "$SECRETS_FILE"

# Test gost command
echo "Testing gost command..."
TEST_COMMAND="/snap/bin/gost -L=http://:$PORT?secrets=$SECRETS_FILE -D"
# Run command with timeout to ensure it exits
sudo timeout 10 $TEST_COMMAND >/dev/null 2>&1 & TEST_PID=$!
echo "Test process PID: $TEST_PID"
sleep 8  # Allow time for startup
if netstat -tuln | grep -q ":$PORT "; then
  echo "Command successful: $TEST_COMMAND"
else
  TEST_OUTPUT=$(sudo $TEST_COMMAND 2>&1)
  echo "Error: Gost command failed with error: $TEST_OUTPUT" >&2
  echo "Try running manually: sudo $TEST_COMMAND" >&2
  # Clean up test process
  sudo pkill -9 -f "/snap/bin/gost" 2>/dev/null
  sudo pkill -9 -f "/snap/gost/" 2>/dev/null
  exit 1
fi

# Clean up test process
echo "Cleaning up test process..."
sudo pkill -9 -f "/snap/bin/gost" 2>/dev/null && echo "Killed /snap/bin/gost processes"
sudo pkill -9 -f "/snap/gost/" 2>/dev/null && echo "Killed /snap/gost/ processes"
# Retry loop to ensure port is free
for i in {1..5}; do
  sleep 3  # Increased wait time
  if ! netstat -tuln | grep -q ":$PORT "; then
    echo "Port $PORT is free"
    break
  fi
  echo "Port $PORT still in use, retrying cleanup ($i/5)..."
  sudo pkill -9 -f "/snap/bin/gost" 2>/dev/null && echo "Killed /snap/bin/gost processes"
  sudo pkill -9 -f "/snap/gost/" 2>/dev/null && echo "Killed /snap/gost/ processes"
  # Log running gost processes for debugging
  ps aux | grep '[g]ost' || echo "No gost processes found"
done

# Final port check
if netstat -tuln | grep -q ":$PORT "; then
  echo "Error: Port $PORT is still in use after cleanup attempts." >&2
  ps aux | grep '[g]ost' >&2
  echo "Try killing processes manually and re-running the script." >&2
  exit 1
fi

# Create systemd service file
echo "Creating systemd service configuration..."
sudo bash -c "cat > /etc/systemd/system/gost.service" << EOF
[Unit]
Description=Gost Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/snap/bin/gost -L=http://:$PORT?secrets=$SECRETS_FILE -D
Restart=on-failure
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to apply changes
sudo systemctl daemon-reload

# Enable and start the service
echo "Enabling and starting gost service..."
sudo systemctl enable gost.service
sudo systemctl start gost.service

# Check service status
echo "Checking gost service status..."
sudo systemctl status gost.service --no-pager

# Display configuration details
echo -e "\nGost installation completed!"
echo "Configuration details:"
echo "Username: $USERNAME"
echo "Password: $PASSWORD"
echo "Port: $PORT"
echo "Secrets file: $SECRETS_FILE"
echo "Logs can be viewed with: sudo journalctl -u gost.service -f"
echo -e "\nYou can check the service status using: sudo systemctl status gost.service"

