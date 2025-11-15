# GPU Passthrough Hooks

This directory contains libvirt hook scripts for GPU passthrough, supporting both single-GPU and dual-GPU setups.

## How It Works

The hooks automatically detect your GPU configuration:

### Dual-GPU Setup (iGPU + Discrete GPU)

When the VM `fedora-mybox` starts:
1. Hooks detect multiple GPUs
2. Host continues using iGPU for display
3. Libvirt automatically binds discrete GPU to vfio-pci
4. VM starts with GPU passthrough
5. **Host display stays on** (using iGPU)

When the VM stops:
1. Libvirt automatically unbinds GPU from vfio-pci
2. Host display continues working normally

### Single-GPU Setup (Only Discrete GPU)

When the VM `fedora-mybox` starts:
1. Hooks detect single GPU
2. Display manager (SDDM) stops
3. GPU unbinds from NVIDIA driver
4. GPU binds to vfio-pci
5. VM starts with GPU passthrough
6. **Host display goes black** (access via SSH)

When the VM stops:
1. GPU unbinds from vfio-pci
2. GPU rebinds to NVIDIA driver
3. Display manager restarts
4. **Host display comes back**

## Installation

```bash
cd libvirt-hooks
./install.sh
```

## Usage

**GPU passthrough is controlled by VM naming:**
VMs with names ending in `-gpu` automatically trigger GPU passthrough hooks.

### Start VM with GPU passthrough

```bash
GPU_PASSTHROUGH=yes make virt-install
# Creates VM named "fedora-mybox-gpu"
# Adds --hostdev arguments for GPU PCI devices (01:00.0 and 01:00.1)
# Hooks will unbind NVIDIA GPU and pass to VM when VM starts
```

### Start VM without GPU passthrough

```bash
make virt-install
# Creates VM named "fedora-mybox"
# Hooks are skipped, NVIDIA GPU stays on host
```

### What Happens

**With dual-GPU (recommended):**
- Host display stays on (using iGPU)
- NVIDIA GPU passed to VM
- Both host and VM usable simultaneously

**With single-GPU:**
- Host display goes black when VM starts
- NVIDIA GPU passed to VM
- Host display returns when VM stops

## Troubleshooting

If your display doesn't come back after VM stops (single-GPU only):
```bash
# Via SSH to the host:
sudo /etc/libvirt/hooks/vfio-teardown.sh
```

View hook logs:
```bash
sudo journalctl -u libvirtd -f
```

Check which mode the hooks are using:
```bash
lspci | grep -i "VGA compatible controller"
# 2+ results = dual-GPU mode
# 1 result = single-GPU mode
```

## Files

- `qemu` - Main hook called by libvirt
- `vfio-startup.sh` - Handles GPU binding before VM starts
- `vfio-teardown.sh` - Handles GPU cleanup after VM stops
- `install.sh` - Installs hooks to `/etc/libvirt/hooks/`

## Requirements

- IOMMU enabled (`intel_iommu=on iommu=pt`)
- NVIDIA driver loaded on host
- For single-GPU: SSH access to host (for when display is black)
- VM name must be `fedora-mybox` (or edit `qemu` script)

## Dual-GPU Setup (Recommended)

For the best experience, enable your CPU's integrated graphics (iGPU) in BIOS:
- Look for "Primary Display" or "Initial Display Output"
- Look for "iGPU Multi-Monitor" or "Integrated Graphics"
- Enable both iGPU and discrete GPU

This allows the host to use iGPU while the VM uses the discrete GPU - no display blackout!
