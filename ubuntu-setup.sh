#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration Variables ---
# Change these if your interface name or netplan file name differs
INTERFACE_NAME="eth0"
NETPLAN_FILE="xxx"
NETPLAN_DIR="/etc/netplan/"
SSH_CONFIG="/etc/ssh/sshd_config"
CLOUD_INIT_FLAG="/etc/cloud/cloud-init.disabled"

# --- Argument Validation ---
if [ -z "$1" ]; then
    echo "Error: Missing argument. Usage: $0 <yyy_value>"
    echo "Example: $0 105"
    exit 1
fi

YYY=$1

# Basic validation to ensure YYY is a number
if ! [[ "$YYY" =~ ^[0-9]+$ ]]; then
    echo "Error: The argument must be a numeric value."
    exit 1
fi

echo "Starting configuration with YYY value: $YYY"
echo "Target IP: 10.1.200.$YYY/23"

# 1. Modify SSH Config (PermitRootLogin yes)
# Checks if the line exists, if not adds it; if it exists, ensures it is set to 'yes'
if grep -q "^PermitRootLogin" "$SSH_CONFIG"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
else
    echo "PermitRootLogin yes" >> "$SSH_CONFIG"
fi
echo "[OK] SSH Config updated."

# 2. Disable Cloud Init
sudo touch "$CLOUD_INIT_FLAG"
echo "[OK] Cloud-init disabled."

# 3. Configure Network (Netplan)
NETPLAN_PATH="${NETPLAN_DIR}${NETPLAN_FILE}"

# Check if the netplan file exists, if not create it
if [ ! -f "$NETPLAN_PATH" ]; then
    echo "File $NETPLAN_PATH not found. Creating..."
    # Create a basic template first if it doesn't exist
    cat <<EOF > "$NETPLAN_PATH"
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $INTERFACE_NAME:
      dhcp4: no
      addresses: []
      routes: []
EOF
fi

# Update the specific IP address in the netplan file using sed
# This regex looks for the specific interface block and updates the addresses line
# Note: This assumes the file structure is relatively clean. 
# For complex manual edits, sed can be fragile. 
# We will replace the address line inside the eth0 block.

# Define the new address line
NEW_ADDRESS="      - 10.1.200.$YYY/23"
GATEWAY="      via: 10.1.200.1"

# Backup original file
cp "$NETPLAN_PATH" "${NETPLAN_PATH}.bak"

# A. Remove OLD IP lines (Safe: just removes lines matching the specific IP pattern if they exist)
# We look for lines starting with spaces and a dash, followed by 10.1.200 (the old IP pattern)
# This is safer than range matching
sed -i '/^[[:space:]]*- 10\.1\.200\./d' "$NETPLAN_PATH"

# B. Remove OLD Route lines
# This removes lines containing "via: 10.1.200.1" or "to: default" if they are old routes
sed -i '/via: 10\.1\.200\.1/d' "$NETPLAN_PATH"
sed -i '/to: default/d' "$NETPLAN_PATH"

# C. Insert New IP
NEW_ADDRESS="      - 10.1.200.$YYY/23"
# Insert after the line 'addresses:' inside the eth0 block
# We use a simple match for 'addresses:' which is unique enough in this context
sed -i "/^      addresses:/a $NEW_ADDRESS" "$NETPLAN_PATH"

# D. Insert New Route
# We need to insert the route block under 'routes:'
# Since 'routes:' might have empty brackets [], we insert after the 'routes:' line
sed -i "/^      routes:/a\        - to: default\n        via: 10.1.200.1" "$NETPLAN_PATH"

echo "[OK] Netplan config updated with IP 10.1.200.$YYY/23"

# 4. Apply Netplan
echo "Applying netplan configuration..."
sudo netplan try --timeout 30 || {
    echo "Warning: 'netplan try' failed or timed out. Rolling back..."
    sudo cp "${NETPLAN_PATH}.bak" "$NETPLAN_PATH"
    exit 1
}

sudo netplan apply
echo "[OK] Netplan applied successfully."

echo "Script execution completed."
