#!/bin/bash

die() {
  echo "$@"
  exit 1
}


kernel_dir="/usr/src/linux"
mount -o remount -rw /boot #this is strange?!

cp /etc/paludis/kernel/config "${kernel_dir}"/.config || die
cd "${kernel_dir}" || die
make olddefconfig || die
make -j$(nproc 2>/dev/null || echo '1') || die
#make modules_install || die # no modules support in kernel
cp arch/x86/boot/bzImage \
	/boot/kernel-$(readlink "${kernel_dir}" | sed "s/linux-//") || die
