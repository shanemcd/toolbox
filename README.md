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

### Produce custom ISO using Podman

This will discover the latest version of Fedora, download the Everything netinst
ISO, inject a kickstart that will automate the provisioning of the machine. A
random password will be generated and printed to the screen unless you pass `-e
fedora_iso_kickstart_password=$KS_PASS`.

Dependencies:

- `podman` (`dnf or brew install podman`)
- `ansible-core` (`pip install ansible-core`)
- `containers.podman` (`ansible-galaxy collection install containers.podman`)
- `passlib` (`pip install passlib`)

From the root of this repo, run:

```
$ ansible-playbook shanemcd.toolbox.make_fedora_iso -v \
    -e fedora_iso_build_context=/home/shanemcd/Desktop/mybox \
    -e fedora_iso_force=yes \
    -e fedora_iso_kickstart_password=$MY_PASSWORD \
    -e fedora_iso_target_disk_id=nvme-Samsung_SSD_990_PRO_2TB_... # found under /dev/disk/by-id/...
```


### Testing (sorta)

I test to make sure the thing can boot at all by doing this:

```
$ qemu-img create -f qcow2 vm-disk.qcow2 40G
$ qemu-system-x86_64 -enable-kvm \
    -boot d -cdrom
    ~/Desktop/mybox/ks-Fedora-Everything-netinst-x86_64-41-1.4.iso \
    -m 10000 -device virtio-blk-pci,drive=vm_disk,serial="f1ce90" \
    -drive file=vm-disk.qcow2,format=qcow2,if=none,id=vm_disk # This installs onto the virtual disk
$ qemu-system-x86_64 -enable-kvm \
    -m 10000 -device virtio-blk-pci,drive=vm_disk,serial="f1ce90" \
    -drive file=vm-disk.qcow2,format=qcow2,if=none,id=vm_disk # This boots the OS we just installed on the virtual disk
```
