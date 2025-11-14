# Shane's Toolbox Ansible Collection

This project is mostly a collection of Ansible content used for provisioning my
personal development environment. If you find something useful here, feel free
to use it.

## Fedora Development Environment

This is currently a bit of an experiment. In the past I used `packer` on my Mac
to produce customized Fedora VMs that would run under VMware Fusion. Here, I am
trying to produce an ISO that I can use to perform unattended (automated)
installations of my personal desktop environment on the various machines that I
use at home and work. I may write more at some point about how and why I am
using an atomic desktop, but my main goal here is to document these things for
my future self.

### Produce custom ISO

This will discover the latest version of Fedora, download the Everything netinst
ISO, inject a kickstart that will automate the provisioning of the machine. A
random password will be generated and printed to the screen unless you pass `-e
fedora_iso_kickstart_password=$KS_PASS`.

#### Container Runtime Selection

The ISO generation process supports both **Docker** and **Podman**. You can select the runtime using the `container_runtime` variable.

**Recommended: Use Docker** - Works without sudo and provides full UEFI boot support:

Dependencies:
- `docker` (`dnf install docker` or see [Docker installation](https://docs.docker.com/engine/install/fedora/))
- `ansible-core` (`pip install ansible-core`)
- `community.docker` (`ansible-galaxy collection install community.docker`)
- `passlib` (`pip install passlib`)
- Python `requests` and `docker` libraries (`pip install requests docker`)

```bash
$ ansible-playbook shanemcd.toolbox.make_fedora_iso -v \
    -e fedora_iso_build_context=/home/shanemcd/Desktop/mybox \
    -e fedora_iso_force=yes \
    -e fedora_iso_kickstart_password=$MY_PASSWORD \
    -e fedora_iso_target_disk_id=nvme-Samsung_SSD_990_PRO_2TB_... \
    -e container_runtime=docker
```

Or use the Makefile:
```bash
$ CONTAINER_RUNTIME=docker make context/custom.iso
```

**Alternative: Use Podman with sudo** - Requires password for privileged operations:

Dependencies:
- `podman` (`dnf install podman`)
- `ansible-core` (`pip install ansible-core`)
- `containers.podman` (`ansible-galaxy collection install containers.podman`)
- `passlib` (`pip install passlib`)

```bash
$ ansible-playbook shanemcd.toolbox.make_fedora_iso -v -K \
    -e fedora_iso_build_context=/home/shanemcd/Desktop/mybox \
    -e fedora_iso_force=yes \
    -e fedora_iso_kickstart_password=$MY_PASSWORD \
    -e fedora_iso_target_disk_id=nvme-Samsung_SSD_990_PRO_2TB_... \
    -e container_runtime=podman
```

Or via the Makefile:
```bash
$ ANSIBLE_EXTRA_ARGS="-K" make context/custom.iso
```

**Note:** The `-K` flag will prompt for your sudo password. This is required because `mkksiso` version 38.4+ needs root privileges to create fully bootable UEFI ISOs. Rootless Podman cannot access loop devices required for EFI boot image creation. See [CONTAINER_RUNTIME_ISSUE.md](CONTAINER_RUNTIME_ISSUE.md) for technical details.


### Testing (sorta)

I test to make sure the thing can boot at all by doing this:

```
$ make qemu
```

## Flatpak Management

Track and restore my flatpak applications.

### List installed flatpaks

```bash
$ ansible-playbook shanemcd.toolbox.list_flatpaks
```

### Install flatpaks

Installs all flatpaks defined in `roles/flatpaks/vars/main.yml`:

```bash
$ ansible-playbook shanemcd.toolbox.install_flatpaks
```

By default, flatpaks are installed at the user level from flathub. Override with:

```bash
$ ansible-playbook shanemcd.toolbox.install_flatpaks -e flatpaks_method=system
```
