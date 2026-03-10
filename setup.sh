#!/bin/bash

# --- Validation ---
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <last_octet> <hostname> <debug|release>"
    echo "Example: $0 70 my-server debug"
    exit 1
fi

LAST_OCTET="$1"
NEW_HOSTNAME="$2"
MODE="$3"

# Validate Last Octet (must be a number between 1 and 254)
if ! [[ "$LAST_OCTET" =~ ^[0-9]+$ ]] || [ "$LAST_OCTET" -lt 1 ] || [ "$LAST_OCTET" -gt 254 ]; then
    echo "Error: Last octet must be an integer between 1 and 254."
    exit 1
fi

# Validate Mode
if [[ "$MODE" != "debug" && "$MODE" != "release" ]]; then
    echo "Error: Third argument must be 'debug' or 'release'."
    exit 1
fi

# --- Configuration Variables ---
BASE_IP="10.1.200"
TARGET_IP="${BASE_IP}.${LAST_OCTET}"
NETMASK="255.255.254.0"
GATEWAY="10.1.200.1"
INTERFACE="eth0"

# --- 1. Change Hostname ---
echo "[*] Changing hostname to: $NEW_HOSTNAME"
echo "$NEW_HOSTNAME" | sudo tee /etc/hostname > /dev/null

# Update /etc/hosts to reflect the new hostname
# We preserve existing mappings but ensure the new hostname points to localhost/127.0.1.1
sudo sed -i "s/$(hostname)/$NEW_HOSTNAME/g" /etc/hosts
sudo sed -i "s/127.0.1.1.*$/127.0.1.1       $NEW_HOSTNAME $NEW_HOSTNAME.localdomain/g" /etc/hosts

# Apply hostname immediately (optional, requires restart for full app consistency)
sudo hostnamectl set-hostname "$NEW_HOSTNAME"

echo "[+] Hostname updated."

# --- 2. Configure Static IP (Netplan) ---
# Find the netplan config file (usually 00-installer-config.yaml or 50-cloud-init.yaml)
NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)

if [ -z "$NETPLAN_FILE" ]; then
    echo "[!] No existing netplan config found. Creating new one."
    NETPLAN_FILE="/etc/netplan/00-static-ip.yaml"
fi

echo "[*] Configuring static IP: $TARGET_IP on $INTERFACE"

# Create/Overwrite the netplan configuration
# Note: We assume a simple single-interface setup.
sudo cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $TARGET_IP/$NETMASK
      gateway4: $GATEWAY
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF

# Apply the netplan configuration
echo "[*] Applying network configuration..."
sudo netplan apply

# Verify the interface is up (optional safety check)
sudo ip link set $INTERFACE up

echo "[+] Static IP configured."

# --- 3. Install Repository based on Mode ---
echo "[*] Installing repository in $MODE mode..."

REPO_URL=""
if [ "$MODE" == "debug" ]; then
    REPO_URL="https://intrepo.dh2i.com/dists/bionic/debug-v25/repo.deb"
    echo "[*] Downloading Debug repository..."
elif [ "$MODE" == "release" ]; then
    REPO_URL="https://intrepo.dh2i.com/dists/bionic/retail-v25/repo.deb"
    echo "[*] Downloading Release repository..."
fi

REPO_FILE="/tmp/repo.deb"

# Download the package
if ! wget "$REPO_URL" -O "$REPO_FILE"; then
    echo "[!] Error: Failed to download the repository package."
    exit 1
fi

# Install the package
echo "[*] Installing package..."
if ! sudo dpkg -i "$REPO_FILE"; then
    # Attempt to fix broken dependencies if dpkg fails
    echo "[*] Attempting to fix dependencies..."
    sudo apt-get install -f -y
fi

# Remove the downloaded deb file
rm -f "$REPO_FILE"

# Update package lists
echo "[*] Updating apt package lists..."
sudo apt-get update

echo "[+] Setup complete! Machine configured with IP $TARGET_IP, Hostname $NEW_HOSTNAME, and $MODE repo."
