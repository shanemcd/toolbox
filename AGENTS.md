# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an Ansible collection for provisioning Shane's personal development environment. The project includes:
- Automated Fedora ISO generation with kickstart for unattended installations
- Bootable container image (bootc) based on Fedora Kinoite for atomic desktop deployments
- Ansible roles for configuring KDE, flatpaks, fonts, Emacs, and other tools
- VM testing infrastructure using QEMU and virt-install

## Architecture

### Project Structure

```
toolbox/
├── ansible_collections/shanemcd/toolbox/
│   ├── playbooks/          # Ansible playbooks (run via shanemcd.toolbox.<name>)
│   └── roles/              # Ansible roles for specific configuration tasks
├── mybox/
│   ├── Containerfile       # Bootable container image definition (Fedora Kinoite + packages)
│   └── install-cursor.sh   # Cursor IDE installation script
└── context/                # ISO build artifacts (gitignored, created by make targets)
```

### Key Concepts

**Bootable Container (bootc)**: The `mybox/Containerfile` builds a customized Fedora Kinoite image that can be deployed using `bootc switch`. This provides an immutable, atomic desktop environment. Package installations go in the Containerfile; runtime configuration is handled by Ansible playbooks.

**Ansible Collection Pattern**: All playbooks are accessed via the collection namespace `shanemcd.toolbox.<playbook_name>`. This allows running playbooks without needing to specify full paths.

**ISO Generation**: The `fedora_iso` role downloads the latest Fedora Everything netinst ISO, injects a kickstart file for automated installation, and produces a custom ISO. The kickstart references the bootable container image for the final system.

**Container Runtime Flexibility**: ISO generation supports both Docker (recommended, no sudo needed) and Podman (requires sudo for UEFI boot image creation due to loop device requirements).

## Running Playbooks

All playbooks use `uvx` to run ansible-playbook without requiring a system Ansible installation:

```bash
uvx --from ansible-core ansible-playbook shanemcd.toolbox.<playbook_name>
```

### Available Playbooks

- `make_fedora_iso` - Generate custom Fedora ISO with kickstart (mkksiso-based, pulls image from registry)
- `make_bootc_iso` - Generate ISO with embedded container using bootc-image-builder (offline installation)
- `install_flatpaks` - Install flatpaks from vars/main.yml
- `list_flatpaks` - List currently installed flatpaks
- `fonts` - Install custom fonts
- `emacs` - Clone .emacs.d and install packages (including nerd-icons and vterm)
- `kde` - Configure KDE Plasma favorites via D-Bus API
- `authorized_keys` - Configure SSH authorized keys
- `jetkvm_tailscale` - Configure JetKVM with Tailscale
- `tailscale_up` - Install Tailscale and join tailnet with auth key
- `inception` - Meta-playbook for full system setup

## Common Commands

### ISO Generation (bootc-image-builder)

Use bootc-image-builder to embed the container image directly in the ISO for offline installation:

```bash
make bootc-iso
# Output: output/bootiso/install.iso
```

To use all available disks (omits `ignoredisk` directive):
```bash
make bootc-iso BOOTC_USE_ALL_DISKS=yes
```

With custom parameters:
```bash
ansible-playbook shanemcd.toolbox.make_bootc_iso -v -K \
  -e bootc_iso_build_context=/path/to/output \
  -e bootc_iso_force=yes \
  -e bootc_iso_user_password=$PASSWORD \
  -e bootc_iso_target_disk_id=nvme-Samsung_SSD_... \
  -e bootc_iso_use_all_disks=yes
```

Test with virt-install (requires 24GB+ RAM for installation):
```bash
make virt-install-bootc
```

### ISO Generation (mkksiso)

Use mkksiso when network access is available during installation (pulls container from registry):

Using Docker (recommended):
```bash
make context/custom.iso
# or
CONTAINER_RUNTIME=docker make context/custom.iso
```

Using Podman (requires sudo password):
```bash
ANSIBLE_EXTRA_ARGS="-K" make context/custom.iso
```

With custom parameters:
```bash
ansible-playbook shanemcd.toolbox.make_fedora_iso -v \
  -e fedora_iso_build_context=/path/to/context \
  -e fedora_iso_force=yes \
  -e fedora_iso_kickstart_password=$PASSWORD \
  -e fedora_iso_target_disk_id=nvme-Samsung_SSD_... \
  -e container_runtime=docker
```

### VM Testing

Boot test ISO in QEMU (installs then reboots to test):
```bash
make qemu
```

Create libvirt VM:
```bash
make virt-install          # Non-interactive
make virt-install-console  # With console
```

Manage VMs:
```bash
make virt-start            # Start existing VM
make virt-destroy          # Remove VM (preserves disk)
```

### Tailscale

Join a machine to your tailnet:
```bash
# Generate a one-off auth key at https://login.tailscale.com/admin/settings/keys
# Then run:
uvx --from ansible-core ansible-playbook shanemcd.toolbox.tailscale_up \
  -i <inventory> \
  -e tailscale_auth_key=tskey-auth-...
```

With optional parameters:
```bash
uvx --from ansible-core ansible-playbook shanemcd.toolbox.tailscale_up \
  -i <inventory> \
  -e tailscale_auth_key=tskey-auth-... \
  -e tailscale_advertise_tags=tag:server \
  -e tailscale_accept_routes=true \
  -e tailscale_ssh=true \
  -e tailscale_hostname=my-custom-hostname
```

### Bootable Container

Build and push container image:
```bash
make mybox                 # Build image
make push-mybox            # Push to registry
make push-mybox-manifest   # Create multi-arch manifest
```

Update running system:
```bash
make bootc-switch-mybox    # Switch to new image version
```

Full workflow:
```bash
make update-mybox          # Build, push, switch
```

## Key Implementation Details

### KDE Favorites Management

The `kde` role uses KDE's official D-Bus API (`org.kde.ActivityManager.ResourcesLinking`) to manage application favorites, NOT direct SQLite manipulation. This is the proper, supported method that:
- Works during active Plasma sessions
- Is fully idempotent
- Lets Plasma handle database/config synchronization
- Uses `LinkResourceToActivity` and `UnlinkResourceFromActivity` methods

Favorites are defined in `roles/kde/vars/main.yml` as a list of application identifiers (e.g., `applications:emacs.desktop`, `preferred://browser`).

### Emacs Configuration

The `emacs` role:
1. Clones `.emacs.d` from GitHub
2. Runs Emacs in batch mode with `vterm-always-compile-module` set to auto-compile vterm
3. Loads init.el (which runs org-babel to load config)
4. Installs nerd-icons fonts non-interactively

This ensures vterm compilation happens automatically without prompts during provisioning.

### bootc-image-builder ISO Build Process

The `bootc_iso` role uses bootc-image-builder to create ISOs with embedded container images (for offline installation):

1. Renders TOML config with kickstart content (partitioning, users, etc.)
2. Pulls the mybox container image
3. Runs bootc-image-builder which:
   - Creates an anaconda installer with the container embedded at `/run/install/repo/container`
   - Generates base kickstart for `ostreecontainer` deployment
   - Merges custom kickstart content
4. Produces bootable ISO at `output/bootiso/install.iso` (~15GB with 14GB container)

**Key insight**: System configuration (keyboard, locale, timezone) must be baked into the container image, not the kickstart. The kickstart only affects the installer environment.

**Requirements**: 24GB+ RAM during installation to extract the large container image.

### Fedora ISO Build Process (mkksiso)

The `fedora_iso` role uses mkksiso to inject a kickstart into the Fedora netinst ISO. The container image is pulled from the registry during installation (requires network):

1. Fetches latest Fedora version from downloads API
2. Downloads Fedora Everything netinst ISO
3. Renders kickstart template with password, target disk, and bootc image reference
4. Builds Containerfile using chosen runtime (Docker or Podman)
5. Uses `mkksiso` inside container to inject kickstart into ISO
6. Produces bootable UEFI ISO at `context/custom.iso`

Target disk ID must match actual hardware (find with `ls -l /dev/disk/by-id/`). For VMs, use serial number set in qemu/virt-install config (e.g., `virtio-f1ce90`).

### Makefile Architecture Detection

The Makefile detects host architecture and sets appropriate QEMU settings:
- `aarch64`/`arm64` → Uses `qemu-system-aarch64` with ARM-specific machine and EFI firmware
- `x86_64` → Uses `qemu-system-x86_64` with default settings
- Auto-detects KVM/HVF acceleration based on host OS

## Important Variables

### bootc ISO Generation (bootc-image-builder)

Ansible variables:
- `bootc_iso_image` - Container image to embed (default: quay.io/shanemcd/mybox)
- `bootc_iso_tag` - Image tag (default: latest-{arch})
- `bootc_iso_build_context` - Output directory for ISO (required)
- `bootc_iso_force` - Overwrite existing ISO (yes/no)
- `bootc_iso_user_password` - Plain text password (will be hashed)
- `bootc_iso_user_password_hash` - Pre-hashed password (takes precedence)
- `bootc_iso_use_all_disks` - Use all available disks, omit ignoredisk (default: no)
- `bootc_iso_target_disk_id` - Disk identifier for installation (ignored if use_all_disks=yes)
- `bootc_iso_kernel_args` - Kernel boot arguments
- `bootc_iso_installer_mode` - "graphical" (default) or "text --non-interactive"

Makefile variables:
- `BOOTC_USE_ALL_DISKS` - Set to "yes" to use all disks (default: no)

### ISO Generation (mkksiso)
- `fedora_iso_build_context` - Directory for ISO build artifacts
- `fedora_iso_force` - Overwrite existing ISO (yes/no)
- `fedora_iso_kickstart_password` - Root password for installed system
- `fedora_iso_target_disk_id` - Disk identifier for installation target
- `container_runtime` - Use "docker" or "podman"

### Bootable Container
- `MYBOX_IMAGE` - Container image name (default: quay.io/shanemcd/mybox)
- `MYBOX_VERSION` - Image tag (default: current date YYYYMMDD)

### VM Configuration
- `VM_NAME` - Libvirt VM name (default: fedora-mybox)
- `VM_MEMORY` - RAM in MB (default: 10000)
- `VM_VCPUS` - CPU count (default: 4)

## Dependencies

### For ISO Generation (Docker)
- `docker` + `ansible-core` + `community.docker` collection
- Python: `passlib`, `requests`, `docker`

### For ISO Generation (Podman)
- `podman` + `ansible-core` + `containers.podman` collection
- Python: `passlib`

### For VM Testing
- QEMU (`qemu-system-{arch}`) or virt-install/libvirt
- For ARM: EFI firmware at `/opt/homebrew/share/qemu/edk2-aarch64-code.fd`
