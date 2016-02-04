# Singledisk Partition Profile 

# partitioning
function bs_partition_disk_profile_create () {
cat <<-EOF |	parted -a optimal -s "${disk}" 
		mklabel gpt
		mkpart primary 1MiB 300MiB
		set 1 name "boot"
		set 1 legacy_boot on
		mkpart primary 300MiB 2300MiB 
		set 2 name "swap"
		mkpart primary 2300MiB 66% 
		set 3 name "root"
		mkpart primary 66% 100% 
		set 4 name "docker"
EOF

[[ "$?" != "0" ]] && die "failed setting up partitions" 

	partprobe ${disk}
}

function bs_partition_disk_profile_mkfs () {
	mkfs.ext2 -L boot ${disk}1 || die "failed creating ext2 on ${disk}2"
	mkswap -L swap ${disk}2 || die "failed creating swap partition on ${disk}3"
	mkfs.ext4 -L root ${disk}3 || die "failed creating ext4 on ${disk}4"
	mkfs.btrfs -L docker ${disk}4 || die "failed creating btrfs filesystem on ${disk}5"
}

function bs_partition_disk_profile_mount () {
	mount /dev/disk/by-label/root "${mntgentoo}" || die "failed mounting ${mntgentoo}"
	mkdir -p "${mntgentoo}"/boot || die "failed creating ${mntgentoo}/boot"
	mount -rw /dev/disk/by-label/boot "${mntgentoo}"/boot || die "failed mounting ${mntgentoo}/boot"
}

