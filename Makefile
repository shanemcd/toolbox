MYBOX_IMAGE ?= quay.io/shanemcd/mybox
MYBOX_VERSION ?= $(shell date "+%Y%m%d")
CONTAINER_RUNTIME ?= podman
ANSIBLE_EXTRA_ARGS ?=
VM_NAME ?= fedora-mybox
VM_MEMORY ?= 10000
VM_VCPUS ?= 4
GPU_PASSTHROUGH ?= no

# Append -gpu suffix to VM name if GPU passthrough is enabled
ifeq ($(GPU_PASSTHROUGH),yes)
  VM_NAME_FULL := $(VM_NAME)-gpu
  VIRT_INSTALL_HOSTDEV := --hostdev 0000:01:00.0 --hostdev 0000:01:00.1
else
  VM_NAME_FULL := $(VM_NAME)
  VIRT_INSTALL_HOSTDEV :=
endif

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ARCH := $(if $(filter $(UNAME_M),arm64 aarch64),aarch64,$(UNAME_M))

QEMU_BIN ?= qemu-system-$(ARCH)

ifeq ($(UNAME_S),Darwin)
  QEMU_ACCEL ?= -accel hvf
else ifeq ($(UNAME_S),Linux)
  QEMU_ACCEL ?= -enable-kvm
else
  QEMU_ACCEL ?= -accel tcg
endif

ifeq ($(ARCH),aarch64)
  QEMU_MACHINE ?= -machine virt,highmem=on -cpu host
  QEMU_EXTRA_DEVICES ?= \
    -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
    -device qemu-xhci \
    -device usb-kbd \
    -device usb-tablet \
    -device virtio-gpu-pci \
    -device ramfb \
    -device intel-hda
else
  QEMU_MACHINE ?=
  QEMU_EXTRA_DEVICES ?=
endif

.PHONY: mybox
mybox: build-mybox

.PHONY: build-mybox
build-mybox:
	podman build --pull=Always -t $(MYBOX_IMAGE):latest-$(ARCH) -t $(MYBOX_IMAGE):$(MYBOX_VERSION)-$(ARCH) mybox

.PHONY: push-mybox
push-mybox: mybox
	podman push $(MYBOX_IMAGE):$(MYBOX_VERSION)-$(ARCH)
	podman push $(MYBOX_IMAGE):latest-$(ARCH)

.PHONY: push-mybox-manifest
push-mybox-manifest:
	podman rmi $(MYBOX_IMAGE):latest

	podman manifest create $(MYBOX_IMAGE):latest

	podman manifest add $(MYBOX_IMAGE):latest \
		docker://$(MYBOX_IMAGE):latest-x86_64

	podman manifest add $(MYBOX_IMAGE):latest \
		docker://$(MYBOX_IMAGE):latest-aarch64

	podman manifest push --all $(MYBOX_IMAGE):latest \
		docker://$(MYBOX_IMAGE):latest

.PHONY: bootc-switch-mybox
bootc-switch-mybox:
	sudo bootc switch $(MYBOX_IMAGE):$(MYBOX_VERSION)

.PHONY: update-mybox
update-mybox: build-mybox push-mybox push-mybox-manifest bootc-switch-mybox

vm-disk.qcow2:
	qemu-img create -f qcow2 $(CURDIR)/vm-disk.qcow2 100G

.PHONY: qemu
qemu: vm-disk.qcow2 context/custom.iso
	@# First boot: install OS from ISO, boot from cdrom
	$(QEMU_BIN) $(QEMU_ACCEL) $(QEMU_MACHINE) \
		-m 10000 \
		-device virtio-blk-pci,drive=primary_disk,serial="f1ce90" \
		-drive file=$(CURDIR)/vm-disk.qcow2,format=qcow2,if=none,id=primary_disk \
		-boot d \
		-cdrom $(CURDIR)/context/custom.iso \
		$(QEMU_EXTRA_DEVICES)

	@# Second boot: boot from disk
	$(QEMU_BIN) $(QEMU_ACCEL) $(QEMU_MACHINE) \
		-m 10000 \
		-device virtio-blk-pci,drive=primary_disk,serial="f1ce90" \
		-drive file=$(CURDIR)/vm-disk.qcow2,format=qcow2,if=none,id=primary_disk \
		$(QEMU_EXTRA_DEVICES)

.PHONY: virt-install
virt-install: vm-disk.qcow2 context/custom.iso
	@echo "Creating libvirt VM: $(VM_NAME_FULL)"
	@echo "If VM already exists, remove it first with: virsh -c qemu:///system undefine $(VM_NAME_FULL) --nvram"
	@mkdir -p $(HOME)/.local/share/libvirt/images
	@cp -f $(CURDIR)/context/custom.iso $(HOME)/.local/share/libvirt/images/custom.iso
	@cp -f $(CURDIR)/vm-disk.qcow2 $(HOME)/.local/share/libvirt/images/$(VM_NAME_FULL).qcow2
	virt-install \
		--connect qemu:///system \
		--name $(VM_NAME_FULL) \
		--memory $(VM_MEMORY) \
		--vcpus $(VM_VCPUS) \
		--disk path=$(HOME)/.local/share/libvirt/images/$(VM_NAME_FULL).qcow2,format=qcow2,bus=virtio,serial=f1ce90 \
		--disk $(HOME)/.local/share/libvirt/images/custom.iso,device=cdrom,bus=sata \
		--os-variant fedora-unknown \
		--graphics spice \
		--video qxl \
		--channel spicevmc \
		--boot uefi,hd,cdrom \
		$(VIRT_INSTALL_HOSTDEV) \
		--noautoconsole

.PHONY: virt-install-console
virt-install-console: vm-disk.qcow2 context/custom.iso
	@echo "Creating libvirt VM with console: $(VM_NAME_FULL)"
	@echo "If VM already exists, remove it first with: virsh undefine $(VM_NAME_FULL) --nvram"
	@mkdir -p $(HOME)/.local/share/libvirt/images
	@cp -f $(CURDIR)/context/custom.iso $(HOME)/.local/share/libvirt/images/custom.iso
	@cp -f $(CURDIR)/vm-disk.qcow2 $(HOME)/.local/share/libvirt/images/$(VM_NAME_FULL).qcow2
	virt-install \
		--connect qemu:///system \
		--name $(VM_NAME_FULL) \
		--memory $(VM_MEMORY) \
		--vcpus $(VM_VCPUS) \
		--disk path=$(HOME)/.local/share/libvirt/images/$(VM_NAME_FULL).qcow2,format=qcow2,bus=virtio,serial=f1ce90 \
		--disk $(HOME)/.local/share/libvirt/images/custom.iso,device=cdrom,bus=sata \
		--os-variant fedora-unknown \
		--graphics spice \
		--video qxl \
		--channel spicevmc \
		--boot uefi,hd,cdrom \
		$(VIRT_INSTALL_HOSTDEV)

.PHONY: virt-destroy
virt-destroy:
	@echo "Destroying VM: $(VM_NAME_FULL)"
	-virsh -c qemu:///system destroy $(VM_NAME_FULL)
	-virsh -c qemu:///system undefine $(VM_NAME_FULL) --nvram
	@echo "VM destroyed. Disk file preserved at: $(CURDIR)/vm-disk.qcow2"

.PHONY: virt-start
virt-start:
	@echo "Starting VM: $(VM_NAME_FULL)"
	virsh -c qemu:///system start $(VM_NAME_FULL)
	virt-viewer -c qemu:///system $(VM_NAME_FULL) &

context:
	mkdir -p $@

context/custom.iso: context
	ansible-playbook shanemcd.toolbox.make_fedora_iso -v \
		-e fedora_iso_build_context=$(CURDIR)/context \
		-e fedora_iso_force=yes \
		-e fedora_iso_kickstart_password=fortestingonly \
		-e fedora_iso_target_disk_id=virtio-f1ce90 \
		-e fedora_iso_kickstart_shutdown_command=poweroff \
		-e container_runtime=$(CONTAINER_RUNTIME) \
		$(ANSIBLE_EXTRA_ARGS)
