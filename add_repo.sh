#!/usr/bin/env bash

set -e

REPO="$1"

if [ -z "$REPO" ]; then
  echo "Usage: $0 '<apt-repo-line>'"
  echo "Example: $0 'deb http://archive.ubuntu.com/ubuntu focal main'"
  exit 1
fi

FILE="/etc/apt/sources.list.d/add-repo-script-entry-$(date +%s).list"

echo "Adding repository: $REPO"
echo "$REPO" | sudo tee "$FILE" > /dev/null

echo "Updating package lists..."
sudo apt update

echo "Repository added successfully."
