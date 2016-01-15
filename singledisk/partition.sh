# Raid Partition Profile 

# partitioning
function bs_partition_disk_profile_create () {
  parted -s ${disk} mklabel gpt
	parted -s ${disk} mkpart primary 1MiB 4MiB || die "failed creating BIOS boot partition"
	parted -s ${disk} set 1 bios_grub on || die "failed setting bios_grub flag BIOS boot partition"
	parted -s ${disk} mkpart primary 4MiB 300MiB || die "failed creating /boot partition"
	parted -s ${disk} mkpart primary 300MiB 2300MiB || die "failed creating swap partition"
	parted -s ${disk} mkpart primary 2300MiB 66% || die "failed creating root partition"
	parted -s ${disk} mkpart primary 66% 100% || die "failed creating btrfs partition"
	partprobe ${disk}
}

function bs_partition_disk_profile_mkfs () {
	mkfs.ext4 -L root ${disk}4 || die "failed creating ext4 on ${disk}4"
	mkswap -L swap ${disk}3 || die "failed creating swap partition on ${disk}1"
	mkfs.ext2 -L boot ${disk}2 || die "failed creating ext2 on ${disk}2"
	mkfs.btrfs -L docker ${disk}5 || die "failed creating btrfs filesystem on ${disk}5"
}

function bs_partition_disk_profile_mount () {
	mount /dev/disk/by-label/root "${mntgentoo}" || die "failed mounting ${mntgentoo}"
	mkdir -p "${mntgentoo}"/boot || die "failed creating ${mntgentoo}/boot"
	mount -rw /dev/disk/by-label/boot "${mntgentoo}"/boot || die "failed mounting ${mntgentoo}/boot"
}

