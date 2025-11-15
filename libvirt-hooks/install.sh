#!/bin/bash
# Install libvirt hooks for single-GPU passthrough

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing libvirt hooks for single-GPU passthrough..."

# Create hooks directory if it doesn't exist
sudo mkdir -p /etc/libvirt/hooks

# Install hook scripts
sudo cp "$SCRIPT_DIR/qemu" /etc/libvirt/hooks/qemu
sudo cp "$SCRIPT_DIR/vfio-startup.sh" /etc/libvirt/hooks/vfio-startup.sh
sudo cp "$SCRIPT_DIR/vfio-teardown.sh" /etc/libvirt/hooks/vfio-teardown.sh

# Make scripts executable
sudo chmod +x /etc/libvirt/hooks/qemu
sudo chmod +x /etc/libvirt/hooks/vfio-startup.sh
sudo chmod +x /etc/libvirt/hooks/vfio-teardown.sh

# Restart libvirtd to pick up new hooks
sudo systemctl restart libvirtd

echo "✓ Libvirt hooks installed successfully!"
echo ""
echo "IMPORTANT: When you start the VM 'fedora-mybox', your display will go black."
echo "Access your host via SSH to manage the VM or wait for the VM to shut down."
echo ""
echo "To start the VM with GPU passthrough:"
echo "  GPU_PASSTHROUGH=yes make virt-install"
echo ""
echo "After VM shuts down, your display will automatically come back."
