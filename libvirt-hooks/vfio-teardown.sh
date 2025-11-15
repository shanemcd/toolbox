#!/bin/bash
# Script to rebind GPU to host after VM stops

set -x

echo "Rebinding NVIDIA GPU to host after VM shutdown"

# Count number of VGA controllers
VGA_COUNT=$(lspci | grep -i "VGA compatible controller" | wc -l)

# Remove GPU from vfio-pci IDs (ignore errors)
echo "10de 2705" > /sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null || true
echo "10de 22bb" > /sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null || true

# Unbind from vfio-pci (ignore errors)
echo "0000:01:00.0" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
echo "0000:01:00.1" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true

# Unload vfio-pci (ignore errors)
modprobe -r vfio-pci 2>/dev/null || true

# Reload NVIDIA modules (ignore errors)
modprobe nvidia 2>/dev/null || true
modprobe nvidia_modeset 2>/dev/null || true
modprobe nvidia_drm 2>/dev/null || true
modprobe nvidia_uvm 2>/dev/null || true
modprobe i2c_nvidia_gpu 2>/dev/null || true

# Explicitly bind GPU to nvidia driver
echo "0000:01:00.0" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
echo "0000:01:00.1" > /sys/bus/pci/drivers/snd_hda_intel/bind 2>/dev/null || true

# Wait for driver to initialize
sleep 1

# Only restart display manager if single GPU (it was stopped)
if [ "$VGA_COUNT" -eq 1 ]; then
    echo "Single GPU detected - restarting display manager"

    # Rebind EFI framebuffer (ignore errors)
    echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind 2>/dev/null || true

    # Rebind VTconsoles (ignore errors)
    echo 1 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null || true
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true

    # Wait a moment
    sleep 2

    # Restart display manager
    systemctl start sddm.service
else
    echo "Multiple GPUs detected - display manager kept running"
fi
