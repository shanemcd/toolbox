#!/bin/bash
# Script to unbind GPU from nvidia and bind to vfio-pci before VM starts
# Using managed='no' so we handle all driver binding

set -x

echo "Preparing GPU passthrough: unbinding from nvidia, binding to vfio-pci"

# Auto-detect NVIDIA GPU PCI addresses and device IDs
NVIDIA_VGA=$(lspci -D | grep -i "NVIDIA" | grep -i "VGA" | awk '{print $1}')
NVIDIA_AUDIO=$(lspci -D | grep -i "NVIDIA" | grep -i "Audio" | awk '{print $1}')

if [ -z "$NVIDIA_VGA" ]; then
    echo "ERROR: No NVIDIA VGA device found"
    exit 1
fi

# Get vendor:device IDs (format: 10de:2705)
NVIDIA_VGA_ID=$(lspci -n -s "$NVIDIA_VGA" | awk '{print $3}')
NVIDIA_VENDOR=$(echo "$NVIDIA_VGA_ID" | cut -d: -f1)
NVIDIA_DEVICE=$(echo "$NVIDIA_VGA_ID" | cut -d: -f2)

echo "Found NVIDIA VGA: $NVIDIA_VGA (ID: $NVIDIA_VENDOR $NVIDIA_DEVICE)"

if [ -n "$NVIDIA_AUDIO" ]; then
    NVIDIA_AUDIO_ID=$(lspci -n -s "$NVIDIA_AUDIO" | awk '{print $3}')
    NVIDIA_AUDIO_DEVICE=$(echo "$NVIDIA_AUDIO_ID" | cut -d: -f2)
    echo "Found NVIDIA Audio: $NVIDIA_AUDIO (ID: $NVIDIA_VENDOR $NVIDIA_AUDIO_DEVICE)"
fi

# Count number of VGA controllers
VGA_COUNT=$(lspci | grep -i "VGA compatible controller" | wc -l)

# Stop display manager to cleanly unload nvidia modules
systemctl stop sddm.service
sleep 2

# Unbind GPU from nvidia driver
echo "$NVIDIA_VGA" > /sys/bus/pci/devices/$NVIDIA_VGA/driver/unbind 2>/dev/null || true
if [ -n "$NVIDIA_AUDIO" ]; then
    echo "$NVIDIA_AUDIO" > /sys/bus/pci/devices/$NVIDIA_AUDIO/driver/unbind 2>/dev/null || true
fi

# Unload NVIDIA modules
modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia i2c_nvidia_gpu 2>/dev/null || true

# Load vfio-pci and bind GPU
modprobe vfio-pci
echo "$NVIDIA_VENDOR $NVIDIA_DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
if [ -n "$NVIDIA_AUDIO" ]; then
    echo "$NVIDIA_VENDOR $NVIDIA_AUDIO_DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
fi

# If we have dual-GPU, restart display manager on iGPU
if [ "$VGA_COUNT" -gt 1 ]; then
    echo "Dual-GPU detected - restarting display manager on iGPU"
    systemctl start sddm.service
fi
