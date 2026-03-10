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

# Logic to update the IP and Gateway in the specific interface block
# This sed command finds the line starting with the interface name, 
# then looks ahead to update the addresses and routes.
# A simpler approach for strict replacement if the file structure is known:

# Remove existing IP lines under the specific interface (if any)
# This is a safe way to ensure we don't have duplicates
sed -i "/$INTERFACE_NAME:/,/routes:/ { /addresses:/ { n; /^[ ]*- /d; } }" "$NETPLAN_PATH"

# Remove existing route lines under the specific interface (if any)
sed -i "/$INTERFACE_NAME:/,/dhcp4:/ { /routes:/ { n; /^[ ]*- /d; } }" "$NETPLAN_PATH"

# Append the new IP address after the "addresses:" line within the eth0 block
# We use a multi-line sed approach to ensure we insert it in the correct hierarchy
# If the file is complex, a Python/Perl script is safer, but here is a robust sed approach:

# Insert the new IP line after 'addresses:'
sed -i "/$INTERFACE_NAME:/,/routes:/ { /^      addresses:/a\      $NEW_ADDRESS" "$NETPLAN_PATH"

# Insert the new route line after 'routes:'
sed -i "/$INTERFACE_NAME:/,/^network:/ { /^      routes:/a\        - to: default\n$GATEWAY" "$NETPLAN_PATH"

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
