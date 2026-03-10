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
RESOLVED_CONF="/etc/systemd/resolved.conf"
DNS_SERVER="10.1.200.241"

# --- Argument Validation ---
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 <new_hostname> <IP_octet_value>"
    echo "Example: $0 awesome-node1 69"
    exit 1
fi

NEW_HOSTNAME=$1
YYY=$2

# Basic validation to ensure YYY is a number
if ! [[ "$YYY" =~ ^[0-9]+$ ]]; then
    echo "Error: The second argument (IP suffix) must be a numeric value."
    exit 1
fi

TARGET_IP="10.1.200.$YYY"
GATEWAY="10.1.200.1"

echo "=========================================="
echo "Starting Configuration Script"
echo "New Hostname: $NEW_HOSTNAME"
echo "New IP Address: $TARGET_IP/23"
echo "Gateway: $GATEWAY"
echo "DNS: $DNS_SERVER"
echo "=========================================="

# 1. Set Hostname Permanently
echo "[Step 1] Setting hostname to: $NEW_HOSTNAME"
# Update /etc/hostname
echo "$NEW_HOSTNAME" | sudo tee /etc/hostname > /dev/null
# Update /etc/hosts (Replace localhost entry or add new entry)
# We ensure the hostname resolves to 127.0.1.1 or the new IP
if grep -q "localhost" /etc/hosts; then
    # Backup current hosts
    sudo cp /etc/hosts /etc/hosts.bak
    # Replace the line containing the old hostname with the new one, or add it if missing
    # Strategy: Remove any line with the OLD hostname (if known) and add the new one.
    # Since we don't know the OLD hostname easily, we append the new mapping to 127.0.1.1
    # Or better: Update the line that maps 127.0.1.1 to the hostname
    sudo sed -i "s/127.0.1.1 .*/127.0.1.1       $NEW_HOSTNAME $NEW_HOSTNAME.localdomain/" /etc/hosts
    # If the line doesn't exist, we add it
    if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
        echo "127.0.1.1       $NEW_HOSTNAME $NEW_HOSTNAME.localdomain" | sudo tee -a /etc/hosts > /dev/null
    fi
else
    echo "127.0.1.1       $NEW_HOSTNAME $NEW_HOSTNAME.localdomain" | sudo tee -a /etc/hosts > /dev/null
fi

# Apply hostname immediately (optional, reboot is safer but this works for current session)
sudo hostnamectl set-hostname "$NEW_HOSTNAME"
echo "[OK] Hostname updated."

# 2. Modify SSH Config (PermitRootLogin yes)
# Checks if the line exists, if not adds it; if it exists, ensures it is set to 'yes'
if grep -q "^PermitRootLogin" "$SSH_CONFIG"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
else
    echo "PermitRootLogin yes" >> "$SSH_CONFIG"
fi
echo "[OK] SSH Config updated."

# 3. Disable Cloud Init
sudo touch "$CLOUD_INIT_FLAG"
echo "[OK] Cloud-init disabled."

# 4. Configure DNS (systemd-resolved)
if grep -q "^DNS=" "$RESOLVED_CONF"; then
    sudo sed -i 's/^DNS=.*/DNS='$DNS_SERVER'/' "$RESOLVED_CONF"
else
    echo "DNS=$DNS_SERVER" | sudo tee -a "$RESOLVED_CONF" > /dev/null
fi
echo "[OK] Resolved.conf updated."
sudo systemctl restart systemd-resolved

# 5. Configure Network (Netplan)
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

# Backup original file
cp "$NETPLAN_PATH" "${NETPLAN_PATH}.bak"

# A. Ensure dhcp4 is set to 'no'
# If 'dhcp4: yes' exists, change it to 'no'. If 'dhcp4: no' exists, do nothing.
# This handles cases where DHCP was enabled.
if grep -q "dhcp4: yes" "$NETPLAN_PATH"; then
    sudo sed -i 's/dhcp4: yes/dhcp4: no/' "$NETPLAN_PATH"
    echo "  -> Disabled DHCP4."
elif ! grep -q "dhcp4: no" "$NETPLAN_PATH"; then
    # If neither exists, insert it under the interface
    sudo sed -i "/$INTERFACE_NAME:/a\      dhcp4: no" "$NETPLAN_PATH"
    echo "  -> Added dhcp4: no."
fi

# B. Remove OLD IP lines (Pattern: lines starting with spaces, dash, then 10.1.200)
sudo sed -i '/^[[:space:]]*- 10\.1\.200\./d' "$NETPLAN_PATH"

# C. Remove OLD Route lines
sudo sed -i '/via: 10\.1\.200\.1/d' "$NETPLAN_PATH"
sudo sed -i '/to: default/d' "$NETPLAN_PATH"

# D. Handle 'addresses' section
# Check if 'addresses:' line exists
if grep -q "^      addresses:" "$NETPLAN_PATH"; then
    # Line exists, insert IP after it
    NEW_ADDRESS="      - $TARGET_IP/23"
    sudo sed -i "/^      addresses:/a $NEW_ADDRESS" "$NETPLAN_PATH"
else
    # Line does not exist, we need to insert it.
    # We insert 'addresses:' and the IP right after the 'dhcp4: no' line (or interface name if dhcp4 is missing)
    # Strategy: Insert after 'dhcp4: no'
    if grep -q "dhcp4: no" "$NETPLAN_PATH"; then
        sudo sed -i "/dhcp4: no/a\      addresses:\n        - $TARGET_IP/23" "$NETPLAN_PATH"
    else
        # Fallback: insert after interface name
        sudo sed -i "/$INTERFACE_NAME:/a\      dhcp4: no\n      addresses:\n        - $TARGET_IP/23" "$NETPLAN_PATH"
    fi
    echo "  -> Created 'addresses' section."
fi

echo "[OK] Netplan config updated with IP 10.1.200.$YYY/23"

# 6. Apply Netplan
echo "Applying netplan configuration..."
sudo netplan try --timeout 30 || {
    echo "Warning: 'netplan try' failed or timed out. Rolling back..."
    sudo cp "${NETPLAN_PATH}.bak" "$NETPLAN_PATH"
    exit 1
}

sudo netplan apply
echo "[OK] Netplan applied successfully."

echo "=========================================="
echo "Configuration Complete!"
echo "Hostname: $NEW_HOSTNAME"
echo "IP: $TARGET_IP"
echo "Note: A reboot is recommended to fully apply the hostname change."
echo "=========================================="
