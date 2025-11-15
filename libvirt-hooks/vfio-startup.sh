#!/bin/bash
# Script to unbind GPU from nvidia and bind to vfio-pci before VM starts

set -x

echo "Unbinding NVIDIA GPU from host for VM passthrough"

# Always stop display manager to cleanly unload nvidia modules
systemctl stop sddm.service
sleep 2

# Unbind GPU from current driver (if bound)
echo "0000:01:00.0" > /sys/bus/pci/devices/0000:01:00.0/driver/unbind 2>/dev/null || true
echo "0000:01:00.1" > /sys/bus/pci/devices/0000:01:00.1/driver/unbind 2>/dev/null || true

# Unload NVIDIA modules (ignore errors if already unloaded)
modprobe -r nvidia_drm 2>/dev/null || true
modprobe -r nvidia_modeset 2>/dev/null || true
modprobe -r nvidia_uvm 2>/dev/null || true
modprobe -r nvidia 2>/dev/null || true
modprobe -r i2c_nvidia_gpu 2>/dev/null || true

# Load vfio-pci
modprobe vfio-pci

# Bind GPU to vfio-pci
echo "10de 2705" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
echo "10de 22bb" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true

# Count number of VGA controllers
VGA_COUNT=$(lspci | grep -i "VGA compatible controller" | wc -l)

# If we have iGPU, restart display manager on it
if [ "$VGA_COUNT" -gt 1 ]; then
    echo "Multiple GPUs detected - restarting display manager on iGPU"
    systemctl start sddm.service
fi
