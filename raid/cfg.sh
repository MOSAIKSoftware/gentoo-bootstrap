# MD-RAID Based Setup

# in: $mntgentoo 

# Raid Partition Profile 

function bs_create_cfg_files_disk_profile () {
	# update mdadm.conf, important for initramfs!
	cat <<-EOF > "${mntgentoo}"/etc/mdadm.conf
	DEVICE /dev/sd?*
	ARRAY /dev/md0 metadata=1.2 name=root
	ARRAY /dev/md1 metadata=1.2 name=swap
	ARRAY /dev/md2 metadata=1.2 name=boot
	EOF
}
