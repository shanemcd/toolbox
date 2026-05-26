# Shane's Toolbox Ansible Collection

An Ansible collection for provisioning my personal development environment: automated Fedora installations, bootable container images, desktop configuration, and application management.

## Quick Start

Install collection dependencies (required once):

```bash
uvx --from ansible-core ansible-galaxy collection install -r requirements.yml
```

Run any playbook:

```bash
uvx --from ansible-core ansible-playbook shanemcd.toolbox.<playbook_name>
```

## Available Playbooks

### System Setup

| Playbook | Description | Flags |
|---|---|---|
| `inception` | Full environment setup: Oh My Zsh, dotfiles, flatpaks, fonts, Emacs, libvirt | `-K`, 1Password CLI |
| `oh_my_zsh` | Install Oh My Zsh and set zsh as default shell | `-K` |
| `dotfiles` | Initialize chezmoi, clone dotfiles, decrypt secrets, apply config | 1Password CLI |
| `install_flatpaks` | Install flatpak applications from `roles/flatpaks/vars/main.yml` | |
| `list_flatpaks` | List currently installed flatpaks | |
| `fonts` | Download and install Iosevka SS05 font | |
| `emacs` | Clone `.emacs.d`, compile vterm, install nerd-icons | |
| `kde` | Configure KDE Plasma favorites via D-Bus | |
| `libvirt` | Add current user to libvirt group | `-K` |

### Image Generation

| Playbook | Description | Flags |
|---|---|---|
| `fedora_iso` | Generate custom Fedora ISO with kickstart (mkksiso, network install) | |
| `bootc_iso` | Generate ISO with embedded container via bootc-image-builder (offline install) | `-K` |
| `bootc_qcow2` | Generate qcow2 disk image via bootc-image-builder | `-K` |

### Remote / Specialized

| Playbook | Description | Flags |
|---|---|---|
| `authorized_keys` | Populate SSH authorized_keys from GitHub public keys | inventory |
| `tailscale_up` | Install Tailscale and join tailnet | inventory, auth key |
| `jetkvm_tailscale` | Configure Tailscale on JetKVM devices | inventory, auth key |

### Services

| Playbook | Description | Flags |
|---|---|---|
| `nfs` | Configure NFS server for media sharing | `-K` |
| `jellyfin` | Deploy Jellyfin as a rootless Podman quadlet | |
| `sunshine` | Configure Sunshine game streaming and enable systemd service | |

## Workflows

### Tart VM on macOS

Build a bootc ISO and run it in a Tart VM:

```bash
# Build the ISO (on macOS host)
make bootc-iso BOOTC_USE_ALL_DISKS=yes

# Create and install VM
make tart-create
make tart-install    # boots ISO, runs automated install
make tart-run        # normal boot after install

# SSH into the VM
ssh shanemcd@$(tart ip fedora-mybox)

# Inside the VM: set up the environment
cd toolbox
uvx --from ansible-core ansible-galaxy collection install -r requirements.yml
uvx --from ansible-core ansible-playbook shanemcd.toolbox.inception -K
```

Override VM resources:

```bash
make tart-create TART_VM_NAME=mybox-test TART_DISK_SIZE=250 TART_MEMORY=16384 TART_CPU=8
```

### Bootable Container Image

Build and push the mybox container image:

```bash
make mybox                          # Build Kinoite (KDE) image for current arch
make mybox DESKTOP=silverblue       # Build Silverblue (GNOME) image
make push-mybox                     # Push to quay.io
make push-mybox-manifest            # Create multi-arch manifest
make update-mybox                   # Build, push, manifest, bootc switch (all-in-one)
```

Multi-arch builds are also automated via GitHub Actions (`.github/workflows/build-images.yml`).

### Fedora ISO Generation

**Using Docker (no sudo required):**

```bash
CONTAINER_RUNTIME=docker make context/custom.iso
```

**Using Podman (requires sudo):**

```bash
ANSIBLE_EXTRA_ARGS="-K" make context/custom.iso
```

**With embedded container (offline install):**

```bash
make context/custom-embedded.iso
```

### VM Testing

```bash
# QEMU (direct, no libvirt)
make qemu-mkksiso       # Boot mkksiso ISO
make qemu-bootc-iso     # Boot bootc ISO (24GB RAM)
make qemu-bootc-qcow2   # Boot qcow2 directly (fastest)

# libvirt
make virt-install        # Create VM from mkksiso ISO
make virt-install-bootc  # Create VM from bootc ISO
make virt-start          # Start existing VM
make virt-destroy        # Remove VM
```

## Collection Dependencies

| Collection | Used by | Purpose |
|---|---|---|
| `community.general` | flatpaks, dotfiles, virt_install | flatpak management, 1Password lookup, XML editing |
| `community.docker` | fedora_iso | Docker image/container management |
| `ansible.posix` | nfs, authorized_keys | firewalld rules, SSH authorized keys |
| `containers.podman` | fedora_iso, bootc_image | Podman image/container management |

Install all dependencies: `uvx --from ansible-core ansible-galaxy collection install -r requirements.yml`

## See Also

- [AGENTS.md](AGENTS.md) — architecture details, implementation notes, and all Makefile variables
