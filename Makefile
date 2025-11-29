MYBOX_IMAGE ?= quay.io/shanemcd/mybox
MYBOX_VERSION ?= $(shell date "+%Y%m%d")
CONTAINER_RUNTIME ?= podman
ANSIBLE_EXTRA_ARGS ?=
VM_NAME ?= fedora-mybox
VM_MEMORY ?= 10000
VM_VCPUS ?= 4
GPU_PASSTHROUGH ?= no
BOOTC_USE_ALL_DISKS ?= no

# Desktop environment selection
DESKTOP ?= kinoite
FEDORA_VERSION ?= 43
BASE_IMAGE_KINOITE := quay.io/fedora/fedora-kinoite:$(FEDORA_VERSION)
BASE_IMAGE_SILVERBLUE := quay.io/fedora/fedora-silverblue:$(FEDORA_VERSION)

ifeq ($(DESKTOP),silverblue)
  BASE_IMAGE := $(BASE_IMAGE_SILVERBLUE)
else
  BASE_IMAGE := $(BASE_IMAGE_KINOITE)
endif

# Append -gpu suffix to VM name if GPU passthrough is enabled
ifeq ($(GPU_PASSTHROUGH),yes)
  VM_NAME_FULL := $(VM_NAME)-gpu
  # Auto-detect NVIDIA GPU PCI addresses
  NVIDIA_VGA_ADDR := $(shell lspci -D | grep -i "NVIDIA" | grep -i "VGA" | awk '{print $$1}')
  NVIDIA_AUDIO_ADDR := $(shell lspci -D | grep -i "NVIDIA" | grep -i "Audio" | awk '{print $$1}')
  # Error if no NVIDIA GPU found
  ifeq ($(NVIDIA_VGA_ADDR),)
    $(error GPU_PASSTHROUGH=yes but no NVIDIA VGA device found. Check 'lspci | grep -i nvidia')
  endif
  VIRT_INSTALL_HOSTDEV := --hostdev $(NVIDIA_VGA_ADDR) $(if $(NVIDIA_AUDIO_ADDR),--hostdev $(NVIDIA_AUDIO_ADDR))
  VIRT_INSTALL_BOOT := uefi,hd,cdrom,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no
  VIRT_INSTALL_GRAPHICS := spice
  VIRT_INSTALL_VIDEO := qxl
else
  VM_NAME_FULL := $(VM_NAME)
  VIRT_INSTALL_HOSTDEV :=
  VIRT_INSTALL_BOOT := uefi,hd,cdrom
  VIRT_INSTALL_GRAPHICS := spice
  VIRT_INSTALL_VIDEO := qxl
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
	$(CONTAINER_RUNTIME) build --pull \
		-f mybox/Containerfile \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-t $(MYBOX_IMAGE):latest-$(DESKTOP)-$(ARCH) \
		-t $(MYBOX_IMAGE):$(MYBOX_VERSION)-$(DESKTOP)-$(ARCH) \
		mybox

.PHONY: build-mybox-kinoite
build-mybox-kinoite:
	$(MAKE) build-mybox DESKTOP=kinoite

.PHONY: build-mybox-silverblue
build-mybox-silverblue:
	$(MAKE) build-mybox DESKTOP=silverblue

.PHONY: build-mybox-both
build-mybox-both: build-mybox-kinoite build-mybox-silverblue

context/mybox-$(DESKTOP)-$(ARCH).tar: $(shell find mybox -type f)
	$(MAKE) mybox DESKTOP=$(DESKTOP)
	@mkdir -p context
	$(CONTAINER_RUNTIME) save $(MYBOX_IMAGE):latest-$(DESKTOP)-$(ARCH) -o $@ --format oci-archive
	@echo "Container archive saved to $@"

.PHONY: mybox-archive
mybox-archive: context/mybox-$(DESKTOP)-$(ARCH).tar

.PHONY: mybox-archive-kinoite
mybox-archive-kinoite:
	$(MAKE) mybox-archive DESKTOP=kinoite

.PHONY: mybox-archive-silverblue
mybox-archive-silverblue:
	$(MAKE) mybox-archive DESKTOP=silverblue

.PHONY: push-mybox
push-mybox: mybox
	$(CONTAINER_RUNTIME) push $(MYBOX_IMAGE):$(MYBOX_VERSION)-$(DESKTOP)-$(ARCH)
	$(CONTAINER_RUNTIME) push $(MYBOX_IMAGE):latest-$(DESKTOP)-$(ARCH)

.PHONY: push-mybox-kinoite
push-mybox-kinoite:
	$(MAKE) push-mybox DESKTOP=kinoite

.PHONY: push-mybox-silverblue
push-mybox-silverblue:
	$(MAKE) push-mybox DESKTOP=silverblue

.PHONY: push-mybox-both
push-mybox-both: push-mybox-kinoite push-mybox-silverblue

.PHONY: push-mybox-manifest
push-mybox-manifest:
	-$(CONTAINER_RUNTIME) rmi $(MYBOX_IMAGE):latest-$(DESKTOP)

	$(CONTAINER_RUNTIME) manifest create $(MYBOX_IMAGE):latest-$(DESKTOP)

	$(CONTAINER_RUNTIME) manifest add $(MYBOX_IMAGE):latest-$(DESKTOP) \
		docker://$(MYBOX_IMAGE):latest-$(DESKTOP)-x86_64

	$(CONTAINER_RUNTIME) manifest add $(MYBOX_IMAGE):latest-$(DESKTOP) \
		docker://$(MYBOX_IMAGE):latest-$(DESKTOP)-aarch64

	$(CONTAINER_RUNTIME) manifest push --all $(MYBOX_IMAGE):latest-$(DESKTOP) \
		docker://$(MYBOX_IMAGE):latest-$(DESKTOP)

.PHONY: push-mybox-manifest-kinoite
push-mybox-manifest-kinoite:
	$(MAKE) push-mybox-manifest DESKTOP=kinoite

.PHONY: push-mybox-manifest-silverblue
push-mybox-manifest-silverblue:
	$(MAKE) push-mybox-manifest DESKTOP=silverblue

.PHONY: push-mybox-manifest-both
push-mybox-manifest-both: push-mybox-manifest-kinoite push-mybox-manifest-silverblue

.PHONY: bootc-switch-mybox
bootc-switch-mybox:
	sudo bootc switch $(MYBOX_IMAGE):$(MYBOX_VERSION)-$(DESKTOP)

.PHONY: update-mybox
update-mybox: build-mybox push-mybox push-mybox-manifest bootc-switch-mybox

.PHONY: update-mybox-kinoite
update-mybox-kinoite:
	$(MAKE) update-mybox DESKTOP=kinoite

.PHONY: update-mybox-silverblue
update-mybox-silverblue:
	$(MAKE) update-mybox DESKTOP=silverblue

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
	ansible-playbook shanemcd.toolbox.virt_install \
		-e virt_install_vm_name=$(VM_NAME_FULL) \
		-e virt_install_memory=$(VM_MEMORY) \
		-e virt_install_vcpus=$(VM_VCPUS) \
		-e virt_install_disk_source=$(CURDIR)/vm-disk.qcow2 \
		-e virt_install_disk_dest=$(HOME)/.local/share/libvirt/images/$(VM_NAME_FULL).qcow2 \
		-e virt_install_iso_source=$(CURDIR)/context/custom.iso \
		-e virt_install_iso_dest=$(HOME)/.local/share/libvirt/images/custom.iso \
		-e virt_install_graphics="$(VIRT_INSTALL_GRAPHICS)" \
		-e virt_install_video="$(VIRT_INSTALL_VIDEO)" \
		-e virt_install_boot="$(VIRT_INSTALL_BOOT)" \
		-e virt_install_gpu_vga_addr="$(NVIDIA_VGA_ADDR)" \
		-e virt_install_gpu_audio_addr="$(NVIDIA_AUDIO_ADDR)" \
		-e virt_install_gpu_passthrough=$(GPU_PASSTHROUGH)

.PHONY: virt-install-embedded
virt-install-embedded: vm-disk.qcow2 context/custom-embedded.iso
	@echo "Creating libvirt VM with embedded container: $(VM_NAME_FULL)"
	@echo "If VM already exists, remove it first with: virsh -c qemu:///system undefine $(VM_NAME_FULL) --nvram"
	@mkdir -p $(HOME)/.local/share/libvirt/images
	ansible-playbook shanemcd.toolbox.virt_install \
		-e virt_install_vm_name=$(VM_NAME_FULL) \
		-e virt_install_memory=$(VM_MEMORY) \
		-e virt_install_vcpus=$(VM_VCPUS) \
		-e virt_install_disk_source=$(CURDIR)/vm-disk.qcow2 \
		-e virt_install_disk_dest=$(HOME)/.local/share/libvirt/images/$(VM_NAME_FULL).qcow2 \
		-e virt_install_iso_source=$(CURDIR)/context/custom-embedded.iso \
		-e virt_install_iso_dest=$(HOME)/.local/share/libvirt/images/custom-embedded.iso \
		-e virt_install_graphics="$(VIRT_INSTALL_GRAPHICS)" \
		-e virt_install_video="$(VIRT_INSTALL_VIDEO)" \
		-e virt_install_boot="$(VIRT_INSTALL_BOOT)" \
		-e virt_install_gpu_vga_addr="$(NVIDIA_VGA_ADDR)" \
		-e virt_install_gpu_audio_addr="$(NVIDIA_AUDIO_ADDR)" \
		-e virt_install_gpu_passthrough=$(GPU_PASSTHROUGH)

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
		$(VIRT_INSTALL_GRAPHICS) \
		$(VIRT_INSTALL_VIDEO) \
		$(VIRT_INSTALL_BOOT) \
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

context/custom-embedded.iso: context context/mybox-$(DESKTOP)-$(ARCH).tar
	ansible-playbook shanemcd.toolbox.make_fedora_iso -v -K \
		-e fedora_iso_build_context=$(CURDIR)/context \
		-e fedora_iso_output_filename=custom-embedded.iso \
		-e fedora_iso_force=yes \
		-e fedora_iso_kickstart_password=fortestingonly \
		-e fedora_iso_target_disk_id=virtio-f1ce90 \
		-e fedora_iso_kickstart_shutdown_command=poweroff \
		-e container_runtime=$(CONTAINER_RUNTIME) \
		-e fedora_iso_embed_container=yes \
		-e fedora_iso_container_archive=mybox-$(DESKTOP)-$(ARCH).tar \
		$(ANSIBLE_EXTRA_ARGS)

# bootc-image-builder based ISO generation
output:
	mkdir -p $@

ifeq ($(BOOTC_USE_ALL_DISKS),yes)
  BOOTC_DISK_ARGS := -e bootc_iso_use_all_disks=yes
else
  BOOTC_DISK_ARGS := -e bootc_iso_target_disk_id=virtio-f1ce90
endif

.PHONY: bootc-iso
bootc-iso: output/bootiso/install.iso

output/bootiso/install.iso: output
	ansible-playbook shanemcd.toolbox.make_bootc_iso -v -K \
		-e bootc_iso_build_context=$(CURDIR)/output \
		-e bootc_iso_force=yes \
		-e bootc_iso_user_password=fortestingonly \
		$(BOOTC_DISK_ARGS) \
		$(ANSIBLE_EXTRA_ARGS)

.PHONY: virt-install-bootc
virt-install-bootc: vm-disk.qcow2 output/bootiso/install.iso
	@echo "Creating libvirt VM with bootc ISO: $(VM_NAME_FULL)"
	@echo "If VM already exists, remove it first with: virsh -c qemu:///system undefine $(VM_NAME_FULL) --nvram"
	@mkdir -p $(HOME)/.local/share/libvirt/images
	ansible-playbook shanemcd.toolbox.virt_install \
		-e virt_install_vm_name=$(VM_NAME_FULL) \
		-e virt_install_memory=24000 \
		-e virt_install_vcpus=$(VM_VCPUS) \
		-e virt_install_disk_source=$(CURDIR)/vm-disk.qcow2 \
		-e virt_install_disk_dest=$(HOME)/.local/share/libvirt/images/$(VM_NAME_FULL).qcow2 \
		-e virt_install_iso_source=$(CURDIR)/output/bootiso/install.iso \
		-e virt_install_iso_dest=$(HOME)/.local/share/libvirt/images/bootc-install.iso \
		-e virt_install_graphics="$(VIRT_INSTALL_GRAPHICS)" \
		-e virt_install_video="$(VIRT_INSTALL_VIDEO)" \
		-e virt_install_boot="$(VIRT_INSTALL_BOOT)" \
		-e virt_install_gpu_vga_addr="$(NVIDIA_VGA_ADDR)" \
		-e virt_install_gpu_audio_addr="$(NVIDIA_AUDIO_ADDR)" \
		-e virt_install_gpu_passthrough=$(GPU_PASSTHROUGH)
