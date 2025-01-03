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
$ ansible-playbook shanemcd.toolbox.make_fedora_iso -e fedora_iso_force=yes -v
```
