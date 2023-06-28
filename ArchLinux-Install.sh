#!/bin/bash

DESCRIPTION="\
ArchLinux ARM
=============
Free fast and secure Linux based operating system for everyone, suitable
replacement to Windows or MacOS with different Desktop Environments.
    TYPES= server
    BOARDS= VIM3
" #DESCRIPTION_END

LABEL="ArchLinux"
BOARDS="VIM3 #"



FAIL() {
    echo "[e] $@">&2
    exit 1
}

# add git
opkg update && opkg install libmbedtls12 git git-http

BOARD=$(tr -d '\0' < /sys/firmware/devicetree/base/model || echo Khadas)
echo "ArchLinux installation for $BOARD ..."

# create partitions
echo "label: dos" | sfdisk $(mmc_disk)
echo "part1 : start=16M," | sfdisk $(mmc_disk)

# create rootfs
mkfs.ext4 -L ROOT $(mmc_disk)p1 < /dev/null
mkdir -p system && mount $(mmc_disk)p1 system
ROOT=$(pwd)/system
echo "Target root is ${ROOT}"

# can chouse any other rootfs source
SRC=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz

echo "download and extract $SRC"
curl -A downloader -jkL $SRC | pigz -dc | tar -xf- -C system

# setup extlinux config
mkdir -p system/boot/{extlinux,dtbs}
cat <<-END > system/boot/extlinux/extlinux.conf
label ArchLinux
kernel /boot/Image.gz
initrd /boot/initramfs-linux.img
fdtdir /boot/dtbs
append root=LABEL=ROOT rw quiet
END

# setup rootfs
echo LABEL=ROOT / auto errors=remount-ro 1 1 >> system/etc/fstab

# setup host name
echo ${BOARD// /-} > system/etc/hostname

# setup dhcp for ethernet
echo dhcpcd eth0 -d > system/etc/rc.local
chmod 0777 system/etc/rc.local

# add device firmware
# Broadcom
DRIVER_CODE=4359
case $BOARD in
    *VIM3)  DRIVER_CODE=4359;;
    *) DRIVER_CODE= ;;
esac


GH_RAW="https://raw.githubusercontent.com"
CURR_DIR=$(pwd)
mkdir -p /tmp/extras && cd /tmp/extras
git clone "https://github.com/LibreELEC/brcmfmac_sdio-firmware" && cd brcmfmac_sdio-firmware
cp *$DRIVER_CODE* system/lib/firmware/brcm/ && cd -

# add default DT overlays
git clone "https://github.com/khadas/khadas-linux-kernel-dt-overlays.git" khadas-overlays && cd khadas-overlays
cp ./overlays/$(echo "${BOARD}" | tr '[:upper:]' '[:lower:]')/mainline/* "${ROOT}/boot/dtbs"

cd "${CURR_DIR}"

# setup secure tty
echo ttyAML0 >> system/etc/securetty
echo ttyFIQ0 >> system/etc/securetty

umount system

# install uboot to eMMC
mmc_update_uboot online

# optional install uboot to SPI flash
spi_update_uboot online -k && echo need poweroff and poweron device again

# DONE plz reboot device
