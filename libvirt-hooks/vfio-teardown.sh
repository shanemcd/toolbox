#!/bin/bash
# Script to rebind GPU to nvidia after VM stops
# Using managed='no' so we handle all driver binding

set -x

echo "Restoring GPU: unbinding from vfio-pci, binding to nvidia"

# Auto-detect NVIDIA GPU PCI addresses and device IDs
NVIDIA_VGA=$(lspci -D | grep -i "NVIDIA" | grep -i "VGA" | awk '{print $1}')
NVIDIA_AUDIO=$(lspci -D | grep -i "NVIDIA" | grep -i "Audio" | awk '{print $1}')

if [ -z "$NVIDIA_VGA" ]; then
    echo "ERROR: No NVIDIA VGA device found"
    exit 1
fi

# Get vendor:device IDs
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

# Remove GPU from vfio-pci
echo "$NVIDIA_VENDOR $NVIDIA_DEVICE" > /sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null || true
if [ -n "$NVIDIA_AUDIO" ]; then
    echo "$NVIDIA_VENDOR $NVIDIA_AUDIO_DEVICE" > /sys/bus/pci/drivers/vfio-pci/remove_id 2>/dev/null || true
fi
echo "$NVIDIA_VGA" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
if [ -n "$NVIDIA_AUDIO" ]; then
    echo "$NVIDIA_AUDIO" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || true
fi

# Unload vfio-pci
modprobe -r vfio-pci 2>/dev/null || true

# Load nvidia modules and bind GPU
modprobe nvidia nvidia_modeset nvidia_drm nvidia_uvm i2c_nvidia_gpu
echo "$NVIDIA_VGA" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || true
if [ -n "$NVIDIA_AUDIO" ]; then
    echo "$NVIDIA_AUDIO" > /sys/bus/pci/drivers/snd_hda_intel/bind 2>/dev/null || true
fi

# Wait for driver to initialize
sleep 2

# Only restart display manager if single GPU (it was stopped during startup)
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
    echo "Dual-GPU detected - display manager was kept running"
fi
