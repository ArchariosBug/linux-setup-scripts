#!/usr/bin/env bash

set -e

PACKAGE_URL="$1"

if [ -z "$PACKAGE_URL" ]; then
  echo "Usage: $0 '<package-url-or-local-deb>'"
  echo "Example: $0 'https://package.deb'"
  exit 1
fi

# Get the filename from the URL
PACKAGE_FILE="/tmp/$(basename "$PACKAGE_URL")"

echo "Downloading package from: $PACKAGE_URL"
wget -O "$PACKAGE_FILE" "$PACKAGE_URL"

echo "Installing package..."
sudo dpkg -i "$PACKAGE_FILE" || sudo apt-get install -f -y

echo "Cleaning up..."
rm -f "$PACKAGE_FILE"

echo "Package installed successfully."
