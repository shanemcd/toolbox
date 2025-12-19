#!/bin/bash
# Uninstall a sysext
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <sysext-name>"
    echo "Example: $0 cursor"
    exit 1
fi

SYSEXT_NAME="$1"

echo "Uninstalling sysext: $SYSEXT_NAME"

# Remove sysext files
if [[ -f "/var/lib/extensions/${SYSEXT_NAME}.raw" ]]; then
    echo "Removing /var/lib/extensions/${SYSEXT_NAME}.raw..."
    sudo rm -f "/var/lib/extensions/${SYSEXT_NAME}.raw"
fi

# Remove versioned sysext files (from sysupdate)
for f in /var/lib/extensions.d/${SYSEXT_NAME}-*.raw; do
    if [[ -f "$f" ]]; then
        echo "Removing $f..."
        sudo rm -f "$f"
    fi
done

# Remove sysupdate config if present
if [[ -d "/etc/sysupdate.${SYSEXT_NAME}.d" ]]; then
    echo "Removing sysupdate config..."
    sudo rm -f "/etc/sysupdate.${SYSEXT_NAME}.d/${SYSEXT_NAME}.conf"
    sudo rmdir "/etc/sysupdate.${SYSEXT_NAME}.d/" 2>/dev/null || true
fi

# Refresh sysexts
echo "Refreshing sysexts..."
sudo systemctl restart systemd-sysext.service

echo ""
echo "Done! Status:"
systemd-sysext status
