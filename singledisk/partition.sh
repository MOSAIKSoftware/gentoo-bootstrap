# Singledisk Partition Profile 

# partitioning
function bs_partition_disk_profile_create () {
part=(
		'mklabel gpt'
		'mkpart primary 1MiB 300MiB'
		'name 1 "boot"'
		'set 1 legacy_boot on'
		'mkpart primary 300MiB 2300MiB' 
		'name 2 "swap"'
		'mkpart primary 2300MiB 66%' 
		'name 3 "root"'
		'mkpart primary 66% 100%' 
		'name 4 "docker"'
		)

		for cmd in "${part[@]}"; do
			parted -a optimal -s "${disk}" || die "failed setting up partitions: $cmd"
		done	

	partprobe ${disk}
}

function bs_partition_disk_profile_mkfs () {
	mkfs.ext2 -L boot ${disk}1 || die "failed creating ext2 on ${disk}1"
	mkswap -L swap ${disk}2 || die "failed creating swap partition on ${disk}2"
	mkfs.ext4 -L root ${disk}3 || die "failed creating ext4 on ${disk}3"
	mkfs.btrfs -L docker ${disk}4 || die "failed creating btrfs filesystem on ${disk}4"
}

function bs_partition_disk_profile_mount () {
	mount /dev/disk/by-label/root "${mntgentoo}" || die "failed mounting ${mntgentoo}"
	mkdir -p "${mntgentoo}"/boot || die "failed creating ${mntgentoo}/boot"
	mount -rw /dev/disk/by-label/boot "${mntgentoo}"/boot || die "failed mounting ${mntgentoo}/boot"
}

