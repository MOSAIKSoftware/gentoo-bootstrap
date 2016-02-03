# Singledisk Partition Profile 

# partitioning
function bs_partition_disk_profile_create () {
	parted -a optimal -s "${disk}" <<-EOS
		mklabel gpt
		mkpart primary 1MiB 4MiB
		set 1 bios_grub on 
		set 1 name "grub"
		mkpart primary 4MiB 300MiB 
		set 2 name "boot"
		set 2 legacy_boot on
		mkpart primary 300MiB 2300MiB 
		set 3 name "swap"
		mkpart primary 2300MiB 66% 
		set 4 name "root"
		mkpart primary 66% 100% 
		set 5 name "docker"
EOS

[[ "$?" != "0" ]] || die "failed setting up partitions" 

	partprobe ${disk}
}

function bs_partition_disk_profile_mkfs () {
	mkfs.ext2 -L boot ${disk}2 || die "failed creating ext2 on ${disk}2"
	mkswap -L swap ${disk}3 || die "failed creating swap partition on ${disk}3"
	mkfs.ext4 -L root ${disk}4 || die "failed creating ext4 on ${disk}4"
	mkfs.btrfs -L docker ${disk}5 || die "failed creating btrfs filesystem on ${disk}5"
}

function bs_partition_disk_profile_mount () {
	mount /dev/disk/by-label/root "${mntgentoo}" || die "failed mounting ${mntgentoo}"
	mkdir -p "${mntgentoo}"/boot || die "failed creating ${mntgentoo}/boot"
	mount -rw /dev/disk/by-label/boot "${mntgentoo}"/boot || die "failed mounting ${mntgentoo}/boot"
}

