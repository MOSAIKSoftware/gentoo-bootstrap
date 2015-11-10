#!/bin/bash

die() {
  echo "$@"
  exit 1
}


kernel_dir="/usr/src/linux"


cp /etc/paludis/kernel/config "${kernel_dir}"/.config || die
cd "${kernel_dir}" || die
make olddefconfig || die
make -j$(nproc 2>/dev/null || echo '1') || die
make modules_install || die
cp arch/x86/boot/bzImage \
	/boot/kernel-$(readlink "${kernel_dir}" | sed "s/linux-//") || die
