IMG=ubuntu-24.04.3-live-server-amd64.iso
URL_IMG=https://releases.ubuntu.com/noble/${IMG}
ISO_MOUNT=/tmp/iso-disk
OUT_BOOT_FILES=pxe-files/boot/

.EXPORT_ALL_VARIABLES:

default: get-kernel-files get-uefi-files

pxe-files/img/${IMG}:
	wget ${URL_IMG} -O pxe-files/img/${IMG}

${ISO_MOUNT}:
	mkdir ${ISO_MOUNT}

.PHONY: get-kernel-files
get-kernel-files: pxe-files/img/${IMG} ${ISO_MOUNT}
	sudo mount pxe-files/img/${IMG} ${ISO_MOUNT}
	cp ${ISO_MOUNT}/casper/vmlinuz ${OUT_BOOT_FILES}
	cp ${ISO_MOUNT}/casper/initrd ${OUT_BOOT_FILES}
	sudo umount ${ISO_MOUNT}

build/build-docker-helper-image:
	docker build build/. --tag pxe-build
	touch build/build-docker-helper-image

.PHONY: get-uefi-files
get-uefi-files: build/build-docker-helper-image
	$(eval BUILD_CONTAINER := $(shell docker create pxe-build))
	docker cp ${BUILD_CONTAINER}:/build/. ${OUT_BOOT_FILES}
	docker rm -v ${BUILD_CONTAINER}
