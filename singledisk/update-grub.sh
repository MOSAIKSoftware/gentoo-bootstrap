#!/bin/bash

#see: https://wiki.gentoo.org/wiki/Syslinux
die() {
  echo "$@"
  exit 1
}

# and agian read only
mount -o remount  -rw /boot

dd bs=440 conv=notrunc count=1 if=/usr/share/syslinux/gptmbr.bin of=/dev/sda

mkdir /boot/extlinux
extlinux --install /boot/extlinux
ln -snf . /boot/boot
cp /usr/share/syslinux/{menu.c32,memdisk,libcom32.c32,libutil.c32} /boot/extlinux
