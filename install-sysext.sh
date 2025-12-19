#!/bin/bash
# Install a local sysext .raw file
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-sysext.raw>"
    exit 1
fi

RAW_FILE="$1"

if [[ ! -f "$RAW_FILE" ]]; then
    echo "Error: File not found: $RAW_FILE"
    exit 1
fi

if [[ ! "$RAW_FILE" == *.raw ]]; then
    echo "Error: File must have .raw extension"
    exit 1
fi

# Extract sysext name from filename (e.g., cursor-1.2.3-43-x86-64.raw -> cursor)
BASENAME=$(basename "$RAW_FILE")
SYSEXT_NAME="${BASENAME%%-[0-9]*}"

# Fallback if pattern doesn't match
if [[ -z "$SYSEXT_NAME" || "$SYSEXT_NAME" == "$BASENAME" ]]; then
    SYSEXT_NAME="${BASENAME%.raw}"
fi

echo "Installing sysext: $SYSEXT_NAME"

# First-time setup
if [[ ! -d /var/lib/extensions ]]; then
    echo "Creating /var/lib/extensions..."
    sudo install -d -m 0755 -o 0 -g 0 /var/lib/extensions
    sudo restorecon -RFv /var/lib/extensions
fi

# Enable service if not already
if ! systemctl is-enabled systemd-sysext.service &>/dev/null; then
    echo "Enabling systemd-sysext.service..."
    sudo systemctl enable systemd-sysext.service
fi

# Copy the sysext
echo "Copying $RAW_FILE to /var/lib/extensions/${SYSEXT_NAME}.raw..."
sudo cp "$RAW_FILE" "/var/lib/extensions/${SYSEXT_NAME}.raw"
sudo restorecon "/var/lib/extensions/${SYSEXT_NAME}.raw"

# Merge
echo "Merging sysexts..."
sudo systemctl restart systemd-sysext.service

echo ""
echo "Done! Status:"
systemd-sysext status
