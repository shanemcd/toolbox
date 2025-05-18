MYBOX_IMAGE ?= quay.io/shanemcd/mybox
MYBOX_VERSION ?= $(shell date "+%Y%m%d")

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
	qemu-img create -f qcow2 $(CURDIR)/vm-disk.qcow2 20G

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


context:
	mkdir -p $@

context/custom.iso: context
	ansible-playbook shanemcd.toolbox.make_fedora_iso -v \
		-e fedora_iso_build_context=$(CURDIR)/context \
		-e fedora_iso_force=yes \
		-e fedora_iso_kickstart_password=fortestingonly \
		-e fedora_iso_target_disk_id=virtio-f1ce90 \
		-e fedora_iso_kickstart_shutdown_command=poweroff
