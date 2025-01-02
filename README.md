# Shane's Toolbox Ansible Collection

This project is mostly a collection of Ansible content used for provisioning my
personal development environment. If you find something useful here, feel free
to use it.

## Fedora ISO w/ embedded kickstart

This is currently a bit of an experiment. In the past I had used `packer` on my
Mac to produce Fedora VMs that would run under VMWare Fusion. My current
environment is a dedicated PC running Fedora Silverblue. After years of getting
pretty good at rebuilding my system, I wanted to see if it was possible to
declare my PC as code and have it boot itself with little or no effort. This is
my attempt to do that. This will likely evolve into a series of blog posts that
I can share more broadly.



```
$ ansible-playbook shanemcd.toolbox.make_fedora_iso -v 
```
