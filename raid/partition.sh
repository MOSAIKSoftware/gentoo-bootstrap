# MD-RAID Based Setup

# in: $mntgentoo 
# out: $rootdisk

# Raid Partition Profile 
disk1=${disk1}
disk2=${disk2}

rootdisk=/dev/md0

# partitioning
function bs_partition_disk_profile_create () {
	parted -s ${disk1} mklabel gpt
	parted -s ${disk1} mkpart primary 1MiB 4MiB || die "failed creating BIOS boot partition"
	parted -s ${disk1} set 1 bios_grub on || die "failed setting bios_grub flag BIOS boot partition"
	parted -s ${disk1} mkpart primary 4MiB 300MiB || die "failed creating /boot partition"
	parted -s ${disk1} set 2 raid on || die "failed setting boot flag for /boot partition"
	parted -s ${disk1} mkpart primary 300MiB 2300MiB || die "failed creating swap partition"
	parted -s ${disk1} set 3 raid on || die "failed setting raid flag for swap partition"
	parted -s ${disk1} mkpart primary 2300MiB 66% || die "failed creating root partition"
	parted -s ${disk1} set 4 raid on || die "failed setting raid flag for root partition"
	parted -s ${disk1} mkpart primary 66% 100% || die "failed creating btrfs partition"

	parted -s ${disk2} mklabel gpt
	parted -s ${disk2} mkpart primary 1MiB 4MiB || die "failed creating BIOS boot partition"
	parted -s ${disk2} set 1 bios_grub on || die "failed setting bios_grub flag BIOS boot partition"
	parted -s ${disk2} mkpart primary 4MiB 300MiB || die "failed creating /boot partition"
	parted -s ${disk2} set 2 raid on || die "failed setting boot flag for /boot partition"
	parted -s ${disk2} mkpart primary 300MiB 2300MiB || die "failed creating swap partition"
	parted -s ${disk2} set 3 raid on || die "failed setting raid flag for swap partition"
	parted -s ${disk2} mkpart primary 2300MiB 66% || die "failed creating root partition"
	parted -s ${disk2} set 4 raid on || die "failed setting raid flag for root partition"
	parted -s ${disk2} mkpart primary 66% 100% || die "failed creating btrfs partition"
}

function bs_partition_disk_profile_mkfs () {
	yes "y" | mdadm --create --verbose /dev/md0 --name=root --level=mirror --raid-devices=2 ${disk1}4 ${disk2}4 || die "failed creating softraid on ${disk1}4 ${disk2}4"
	mkfs.ext4 -L root /dev/md0 || die "failed creating ext4 on /dev/md0"
	yes "y" | mdadm --create --verbose /dev/md1 --name=swap --level=mirror --raid-devices=2 ${disk1}3 ${disk2}3 || die "failed creating softraid on ${disk1}3 ${disk2}3"
	mkswap -L swap /dev/md1 || die "failed creating swap partition on /dev/md1"
	yes "y" | mdadm --create --verbose /dev/md2 --name=boot --level=mirror --raid-devices=2 ${disk1}2 ${disk2}2 || die "failed creating softraid on ${disk1}2 ${disk2}2"
	mkfs.ext2 -L boot /dev/md2 || die "failed creating ext2 on /dev/md2"
	mkfs.btrfs -L docker -m raid1 -d raid1 ${disk1}5 ${disk2}5 || die "failed creating btrfs mirrored filesystem on ${disk1}5 ${disk2}5"

}

function bs_partition_disk_profile_mount () {
	mount /dev/disk/by-label/root "${mntgentoo}" || die "failed mounting ${mntgentoo}"
	mkdir -p "${mntgentoo}"/boot || die "failed creating ${mntgentoo}/boot"
	mount /dev/disk/by-label/boot "${mntgentoo}"/boot || die "failed mounting ${mntgentoo}/boot"
}

function bs_install_initrfamfs_disk_profile() {
	cat <<-EOF > "${mntgentoo}"/usr/src/initramfs/etc/mdadm.conf
	DEVICE /dev/sd?*
	ARRAY /dev/md0 metadata=1.2 name=root
	EOF
}

function bs_create_cfg_files_disk_profile () {
	# update mdadm.conf, important for initramfs!
	cat <<-EOF > "${mntgentoo}"/etc/mdadm.conf
	DEVICE /dev/sd?*
	ARRAY /dev/md0 metadata=1.2 name=root
	ARRAY /dev/md1 metadata=1.2 name=swap
	ARRAY /dev/md2 metadata=1.2 name=boot
	EOF
}

function bs_install_grub_disk_profile () {
	chroot_run "grub2-install ${disk1}"
	chroot_run "grub2-install ${disk2}"
}
