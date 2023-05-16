RUNNER=./ansible-runner.sh
IMG=ubuntu-22.04.2-preinstalled-server-arm64+raspi.img.xz
URL_IMG=https://cdimage.ubuntu.com/releases/22.04/release/${IMG}
# REPLACE WITH YOUR USB (`lsblk`)
USB=/dev/sdb
SYSTEM_BOOT_MOUNT=/tmp/pi-disk
USER_DATA_NODES=user-data-SSD-partition

.EXPORT_ALL_VARIABLES:

img/${IMG}:
	wget ${URL_IMG} -O img/${IMG}

.PHONY: wipe-disk
wipe-disk:
	sudo wipefs -a -f ${USB}

.PHONY: burn-image
burn-image:
	# `-d` decompress `<` redirect $FILE contents to expand `|` sending the output to `dd` to copy directly to $USB
	xz -d < img/${IMG} - | sudo dd bs=100M of=${USB}

.PHONY: mount-system-boot
mount-system-boot:
	sudo mkdir ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-gateway
prepare-gateway:
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT} 
	sudo cp cloud-init/gateway/user-data ${SYSTEM_BOOT_MOUNT}
	sudo cp cloud-init/gateway/network-config ${SYSTEM_BOOT_MOUNT}
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node1
prepare-node1:
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed 's/nodeX/node1/g' cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node2
prepare-node2:
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed 's/nodeX/node2/g' cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node3
prepare-node3:
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed 's/nodeX/node3/g' cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node4
prepare-node4:
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed 's/nodeX/node4/g' cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sudo umount ${SYSTEM_BOOT_MOUNT}

.PHONY: prepare-node5
prepare-node5:
	sudo mount ${USB}1 ${SYSTEM_BOOT_MOUNT}
	sed 's/nodeX/node5/g' cloud-init/nodes/${USER_DATA_NODES} | sudo tee ${SYSTEM_BOOT_MOUNT}/user-data
	sudo umount ${SYSTEM_BOOT_MOUNT}
