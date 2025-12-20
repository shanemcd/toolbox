# Slimming the Base Image with Sysexts

We're on a journey to remove as much as possible from our bootc container image (`mybox/Containerfile`) by leveraging Fedora system extensions (sysexts). This reduces image size, build time, and allows independent updates of optional tooling.

## Progress Tracker

### Migrated to sysexts

| Package | Sysext | Repo | Size Saved | PR/Status |
|---------|--------|------|------------|-----------|
| Cursor | `cursor` | community | ~594 MB | [PR #25](https://github.com/fedora-sysexts/community/pull/25) |
| 1Password GUI | `1password-gui` | community | ~503 MB | Existing (aarch64: [PR #26](https://github.com/fedora-sysexts/community/pull/26)) |
| libvirt + qemu | `libvirtd-desktop` | fedora | ~500+ MB | Available (F43 not on extensions.fcos.fr yet, use [GitHub releases](https://github.com/fedora-sysexts/fedora/releases/tag/libvirtd-desktop)) |
| `docker-ce` | `docker-ce` | community | ~98 MB | Available |
| `tailscale` | `tailscale` | community | ~65 MB | Available |

### Removed from image (no sysext)

| Package | Size | Notes |
|---------|------|-------|
| `zed` | ~357 MB | Removed entirely, install via Flatpak or manually if needed |

### Upstream contributions

| Sysext | Improvement | PR/Status |
|--------|-------------|-----------|
| `1password-gui` | Added aarch64 support using tarball | [PR #26](https://github.com/fedora-sysexts/community/pull/26) |

### Candidates for migration

These packages have sysext equivalents and could be removed from the Containerfile:

| Package | Sysext | Repo | Size | Notes |
|---------|--------|------|------|-------|
| `emacs` | `emacs` | fedora | ~289 MB | |
| `chromium` | `chromium` | fedora | ~335 MB | |
| `gh` | `gh` | fedora | ~55 MB | |
| `ripgrep` | `ripgrep` | fedora | small | |
| `zsh` | `zsh` | fedora | small | |
| `tmux` | `tmux` | fedora | small | |
| `1password-cli` | `1password-cli` | community | small | |

### Must stay in Containerfile

These cannot be sysexts due to technical limitations:

| Package | Reason |
|---------|--------|
| `akmod-nvidia` + kernel modules | Sysexts cannot provide kernel modules |
| `nvidia-container-toolkit` | Tightly coupled with NVIDIA drivers |
| System config (keyboard, locale, tz) | Sysexts cannot modify `/etc` |
| `cockpit*` | Deep system integration |
| `apcupsd` | Requires `/etc` config + systemd service |

### No sysext available yet

| Package | Size | Notes |
|---------|------|-------|
| `pandoc` | ~213 MB | Could contribute |
| `k9s` | ~178 MB | Could contribute |
| `Sunshine` | ? | WIP: sysext created in community repo, pending PR |

## Quick Reference

### Install a local sysext

```bash
./install-sysext.sh /path/to/sysext-name-version.raw
```

### Uninstall a sysext

```bash
./uninstall-sysext.sh <sysext-name>
```

### Install from upstream

```bash
SYSEXT="cursor"
URL="https://extensions.fcos.fr"

sudo install -d -m 0755 -o 0 -g 0 /var/lib/extensions /etc/sysupdate.${SYSEXT}.d
sudo restorecon -RFv /var/lib/extensions /etc/sysupdate.${SYSEXT}.d

curl -sfL "${URL}/${SYSEXT}.conf" | sudo tee "/etc/sysupdate.${SYSEXT}.d/${SYSEXT}.conf"
sudo /usr/lib/systemd/systemd-sysupdate update --component "${SYSEXT}"
sudo systemctl enable --now systemd-sysext.service
```

### Update all sysexts

```bash
for c in $(/usr/lib/systemd/systemd-sysupdate components --json=short | jq -r '.components[]'); do
    sudo /usr/lib/systemd/systemd-sysupdate update --component "${c}"
done
sudo systemctl restart systemd-sysext.service
```

### Check status

```bash
systemd-sysext status
```

## What are sysexts?

System extensions are EROFS filesystem images that overlay onto `/usr` using overlayfs. They extend immutable/image-based systems without modifying the base image.

**Limitations:**
- Cannot modify kernel, kernel modules, or initrd
- Cannot modify `/etc` configuration
- Cannot add udev rules

## Resources

- [Fedora sysexts (official)](https://github.com/fedora-sysexts/fedora)
- [Fedora sysexts (community)](https://github.com/fedora-sysexts/community)
- [Documentation](https://fedora-sysexts.github.io/)
- [Browse available sysexts](https://extensions.fcos.fr)
