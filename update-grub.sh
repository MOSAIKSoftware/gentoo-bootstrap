#!/bin/bash

die() {
  echo "$@"
  exit 1
}


sed -i -r \
	-e 's#^[[:space:]]*initrd=$#  initrd=initrd#' \
	/etc/grub.d/10_linux || die
echo 'GRUB_CMDLINE_LINUX="net.ifnames=0"' >> /etc/default/grub || die
grub2-install /dev/sda || die
grub2-install /dev/sdb || die
grub2-mkconfig -o /boot/grub/grub.cfg || die
