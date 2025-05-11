MYBOX_IMAGE ?= quay.io/shanemcd/mybox
MYBOX_VERSION ?= $(shell date "+%Y%m%d")

.PHONY: mybox
mybox: build-mybox

.PHONY: build-mybox
build-mybox:
	podman build --pull=Always -t $(MYBOX_IMAGE):latest -t $(MYBOX_IMAGE):$(MYBOX_VERSION) mybox

.PHONY: push--mybox
push-mybox: mybox
	podman push $(MYBOX_IMAGE):$(MYBOX_VERSION)
	podman push $(MYBOX_IMAGE):latest

.PHONY: bootc-switch-mybox
bootc-switch-mybox:
	sudo bootc switch $(MYBOX_IMAGE):$(MYBOX_VERSION)

.PHONY: update-mybox
update-mybox: build-mybox push-mybox bootc-switch-mybox

vm-disk.qcow2:
	qemu-img create -f qcow2 $(CURDIR)/vm-disk.qcow2 20G

qemu: vm-disk.qcow2 context/custom.iso
	qemu-system-x86_64 -enable-kvm \
		-m 10000 \
		-device virtio-blk-pci,drive=primary_disk,serial="f1ce90" \
		-drive file=$(CURDIR)/vm-disk.qcow2,format=qcow2,if=none,id=primary_disk \
		-boot d -cdrom $(CURDIR)/context/custom.iso

	qemu-system-x86_64 -enable-kvm \
		-m 10000 \
		-device virtio-blk-pci,drive=primary_disk,serial="f1ce90" \
		-drive file=$(CURDIR)/vm-disk.qcow2,format=qcow2,if=none,id=primary_disk

context:
	mkdir -p $@

context/custom.iso: context
	ansible-playbook shanemcd.toolbox.make_fedora_iso -v \
		-e fedora_iso_build_context=$(CURDIR)/context \
		-e fedora_iso_force=yes \
		-e fedora_iso_kickstart_password=fortestingonly \
		-e fedora_iso_target_disk_id=virtio-f1ce90 \
		-e fedora_iso_kickstart_shutdown_command=poweroff
