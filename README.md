# Shane's Toolbox Ansible Collection

An Ansible collection for provisioning my personal development environment, including automated Fedora installations, desktop configuration, and application management.

## Quick Start

All playbooks can be run using `uvx --from ansible-core ansible-playbook`:

```bash
uvx --from ansible-core ansible-playbook shanemcd.toolbox.<playbook_name>
```

## Available Playbooks

### System Provisioning

#### `make_fedora_iso`
Generate a custom Fedora ISO with kickstart for unattended installations. Downloads the latest Fedora Everything netinst ISO, injects a kickstart configuration, and produces a bootable ISO that installs a Fedora Kinoite system using the bootc container image from `mybox/Containerfile`.

**Using Docker (recommended - no sudo required):**
```bash
CONTAINER_RUNTIME=docker make context/custom.iso
```

**Using Podman (requires sudo):**
```bash
ANSIBLE_EXTRA_ARGS="-K" make context/custom.iso
```

**Custom parameters:**
```bash
ansible-playbook shanemcd.toolbox.make_fedora_iso -v \
  -e fedora_iso_build_context=/path/to/context \
  -e fedora_iso_force=yes \
  -e fedora_iso_kickstart_password=$PASSWORD \
  -e fedora_iso_target_disk_id=nvme-Samsung_SSD_... \
  -e container_runtime=docker
```

**Dependencies:**
- Docker: `docker`, `ansible-core`, `community.docker` collection, Python `passlib`, `requests`, `docker`
- Podman: `podman`, `ansible-core`, `containers.podman` collection, Python `passlib`

**Testing the ISO:**
```bash
make qemu  # Boot ISO in QEMU, install, then reboot to test
```

**Note:** Podman requires sudo (`-K`) because `mkksiso` 38.4+ needs root privileges to create UEFI boot images. Rootless Podman cannot access the loop devices required for EFI boot image creation.

#### `inception`
Meta-playbook that runs a full environment setup: configures dotfiles, installs flatpaks, fonts, and configures Emacs. Perfect for setting up a new machine.

```bash
ansible-playbook shanemcd.toolbox.inception
```

**Note:** Requires 1Password CLI authenticated for dotfiles role.

### Desktop Configuration

#### `dotfiles`
Initialize chezmoi and apply dotfiles configuration. Fetches the age encryption key from 1Password, clones the dotfiles repository, decrypts secrets, and applies the configuration.

```bash
ansible-playbook shanemcd.toolbox.dotfiles
```

**Requirements:**
- `chezmoi` installed on the target system
- `community.general` Ansible collection
- 1Password CLI (`op`) installed and authenticated
- 1Password item named "Chezmoi Key" containing the age private key

**What it does:**
1. Creates `~/.config/chezmoi` directory with secure permissions
2. Fetches age encryption key from 1Password (if not already present)
3. Initializes chezmoi with the dotfiles repository
4. Runs `setup-secrets.sh` to decrypt secrets
5. Applies chezmoi configuration

#### `kde`
Configure KDE Plasma application menu favorites using the official D-Bus API. Favorites are defined in `roles/kde/vars/main.yml`.

```bash
ansible-playbook shanemcd.toolbox.kde
```

**How it works:** Uses `org.kde.ActivityManager.ResourcesLinking` D-Bus interface to add/remove favorites. This is the proper, supported method that works during active Plasma sessions and lets KDE handle all database synchronization.

#### `flatpaks`
Install flatpak applications defined in `roles/flatpaks/vars/main.yml`.

```bash
ansible-playbook shanemcd.toolbox.install_flatpaks

# Install at system level instead of user level
ansible-playbook shanemcd.toolbox.install_flatpaks -e flatpaks_method=system
```

List currently installed flatpaks:
```bash
ansible-playbook shanemcd.toolbox.list_flatpaks
```

#### `fonts`
Download and install Iosevka SS05 font from the latest GitHub release.

```bash
ansible-playbook shanemcd.toolbox.fonts
```

#### `emacs`
Clone `.emacs.d` repository and configure Emacs with packages, vterm compilation, and nerd-icons fonts.

```bash
ansible-playbook shanemcd.toolbox.emacs
```

**What it does:**
1. Clones `https://github.com/shanemcd/.emacs.d`
2. Runs Emacs in batch mode with `vterm-always-compile-module=t` to auto-compile vterm
3. Loads init.el (which runs org-babel to load configuration)
4. Installs nerd-icons fonts non-interactively

### Remote/Specialized Systems

#### `authorized_keys`
Populate SSH authorized_keys from GitHub user public keys.

```bash
ansible-playbook shanemcd.toolbox.authorized_keys \
  -i inventory.ini \
  -e github_users=['shanemcd','otheruser'] \
  -e remote_user=root
```

**Options:**
- `github_users` - List of GitHub usernames to fetch keys from
- `remote_user` - User account to configure (default: `root`)
- `clear_existing` - Set to `true` to wipe existing authorized_keys first

#### `jetkvm_tailscale`
Install and configure Tailscale on JetKVM devices (Rockchip-based KVM over IP hardware).

```bash
ansible-playbook shanemcd.toolbox.jetkvm_tailscale \
  -i jetkvm-inventory \
  -e tailscale_auth_key=$TSKEY
```

**Requirements:**
- Target must be a JetKVM device (detects Rockchip in `/proc/cpuinfo`)
- Tailscale auth key from https://login.tailscale.com/admin/settings/keys

**What it does:**
1. Downloads latest Tailscale ARM release
2. Installs tailscaled daemon with init script (`S22tailscale`)
3. Configures persistent state in `/userdata/tailscale-state`
4. Authenticates using provided auth key
