#!/bin/bash


# set the following environment variables before running this script:
# * IPV4_IP
# * IPV4_NETMASK
# * IPV4_BRD
# * IPV6_IP
# * IPV6_MASK
# * IPV4_DEF_ROUTE (ip only)
# * IPV6_DEF_ROUTE (ip only)
# * MYHOSTNAME


### HELPER FUNCTIONS ###

# arg1: command to run inside gentoo chroot
# arg2: error message in case of failure (optional)
chroot_run() {
	local cmd=$1
	local diemsg=${2:-${cmd} failed}
	chroot "${mntgentoo}" /bin/bash -c \
		"${cmd}" || die "${diemsg}"
}

die() {
  echo "$@"
  exit 1
}

########################


### GLOBAL VARIABLES ###

suffix= # e.g. -hardened
arch=amd64
busybox_version=x86_64
dist="http://distfiles.gentoo.org/releases/${arch}/autobuilds/"
stage3="$(wget -q -O- ${dist}/latest-stage3-${arch}${suffix}.txt | tail -n 1 | cut -f 1 -d ' ')"
mntgentoo=/mnt/gentoo

########################


# sanity checks
if [[ -z ${mntgentoo} || /${mntgentoo##+(/)} == '/' ]] ; then
	die "invalid mountpoint for gentoo!"
fi

if [[ -z ${IPV4_IP} ||
		-z ${IPV4_NETMASK} ||
		-z ${IPV4_BRD} ||
		-z ${IPV6_IP} ||
		-z ${IPV6_MASK} ||
		-z ${IPV4_DEF_ROUTE} ||
		-z ${IPV6_DEF_ROUTE} ||
		-z ${MYHOSTNAME}
		]] ; then
	die "some required environment variables have not been set!"
fi

### FUNCTIONS ###

bs_partition() {
	# partitioning
	parted -s /dev/sda mklabel gpt
	parted -s /dev/sda mkpart primary 1MiB 4MiB || die "failed creating BIOS boot partition"
	parted -s /dev/sda set 1 bios_grub on || die "failed setting bios_grub flag BIOS boot partition"
	parted -s /dev/sda mkpart primary 4MiB 300MiB || die "failed creating /boot partition"
	parted -s /dev/sda set 2 raid on || die "failed setting boot flag for /boot partition"
	parted -s /dev/sda mkpart primary 300MiB 2300MiB || die "failed creating swap partition"
	parted -s /dev/sda set 3 raid on || die "failed setting raid flag for swap partition"
	parted -s /dev/sda mkpart primary 2300MiB 66% || die "failed creating root partition"
	parted -s /dev/sda set 4 raid on || die "failed setting raid flag for root partition"
	parted -s /dev/sda mkpart primary 66% 100% || die "failed creating btrfs partition"

	parted -s /dev/sdb mklabel gpt
	parted -s /dev/sdb mkpart primary 1MiB 4MiB || die "failed creating BIOS boot partition"
	parted -s /dev/sdb set 1 bios_grub on || die "failed setting bios_grub flag BIOS boot partition"
	parted -s /dev/sdb mkpart primary 4MiB 300MiB || die "failed creating /boot partition"
	parted -s /dev/sdb set 2 raid on || die "failed setting boot flag for /boot partition"
	parted -s /dev/sdb mkpart primary 300MiB 2300MiB || die "failed creating swap partition"
	parted -s /dev/sdb set 3 raid on || die "failed setting raid flag for swap partition"
	parted -s /dev/sdb mkpart primary 2300MiB 66% || die "failed creating root partition"
	parted -s /dev/sdb set 4 raid on || die "failed setting raid flag for root partition"
	parted -s /dev/sdb mkpart primary 66% 100% || die "failed creating btrfs partition"

	yes "y" | mdadm --create --verbose /dev/md0 --name=root --level=mirror --raid-devices=2 /dev/sda4 /dev/sdb4 || die "failed creating softraid on /dev/sda4 /dev/sdb4"
	mkfs.ext4 -L root /dev/md0 || die "failed creating ext4 on /dev/md0"
	yes "y" | mdadm --create --verbose /dev/md1 --name=swap --level=mirror --raid-devices=2 /dev/sda3 /dev/sdb3 || die "failed creating softraid on /dev/sda3 /dev/sdb3"
	mkswap -L swap /dev/md1 || die "failed creating swap partition on /dev/md1"
	yes "y" | mdadm --create --verbose /dev/md2 --name=boot --level=mirror --raid-devices=2 /dev/sda2 /dev/sdb2 || die "failed creating softraid on /dev/sda2 /dev/sdb2"
	mkfs.ext2 -L boot /dev/md2 || die "failed creating ext2 on /dev/md2"
	mkfs.btrfs -L docker -m raid1 -d raid1 /dev/sda5 /dev/sdb5 || die "failed creating btrfs mirrored filesystem on /dev/sda5 /dev/sdb5"

	mkdir -p "${mntgentoo}"/boot || die "failed creating ${mntgentoo}/boot"
	mount /dev/md0 "${mntgentoo}" || die "failed mounting ${mntgentoo}"
	mount /dev/md2 "${mntgentoo}"/boot || die "failed mounting ${mntgentoo}/boot"
}


bs_stage3(){
	# stage3 bootstrapping
	cd "${mntgentoo}" || die "/mnt/gentoo missing!"
	echo "Downloading and extracting ${stage3}..."
	wget -c "${dist}/${stage3}" || die "failed to get stage3"
	bunzip2 -c $(basename ${stage3}) | tar --exclude "./etc/hosts" --exclude "./sys/*" -xf - || die "failed to extract stage3"
	rm -f $(basename ${stage3}) || die "failed to remove stage3"

	echo "Bootstrapped ${stage3} into ${mntgentoo}"
	ls --color -lah "${mntgentoo}"
}


bs_prep_chroot() {
	# preparing chroot
	echo "Mounting required directories into gentoo chroot"
	mount -t proc proc "${mntgentoo}"/proc || die "failed to mount proc"
	mount --rbind /sys "${mntgentoo}"/sys || die "failed to rbind sys"
	mount --make-rslave "${mntgentoo}"/sys || die "failed to make-rslave sys"
	mount --rbind /dev "${mntgentoo}"/dev || die "failed to rbind dev"
	mount --make-rslave "${mntgentoo}"/dev || die "failed to make-rslave dev"
}


bs_create_cfg_files() {
	# configuration

	# get our openrc init template for docker services
	wget https://gist.githubusercontent.com/hasufell/406c35f275efd7ce652a/raw/145d8624f707ca7f3b07c079373da25952dfb447/docker-services.sh -O \
		"${mntgentoo}"/etc/init.d/docker-services || die
	chmod +x "${mntgentoo}"/etc/init.d/docker-services || die

	# update mdadm.conf, important for initramfs!
	cat <<-EOF > "${mntgentoo}"/etc/mdadm.conf || die "cat failed"
	DEVICE /dev/sd?*
	ARRAY /dev/md0 metadata=1.2 name=root
	ARRAY /dev/md1 metadata=1.2 name=swap
	ARRAY /dev/md2 metadata=1.2 name=boot
	EOF

	echo "Copying resolv.conf"
	cp /etc/resolv.conf "${mntgentoo}"/etc/resolv.conf || die "failed to copy resolv.conf to chroot"

	cat <<-EOF > "${mntgentoo}"/etc/env.d/90cave || die "cat failed"
	CAVE_RESUME_FILE_OPT="--resume-file /etc/paludis/tmp/cave_resume"
	CAVE_SEARCH_INDEX=/etc/paludis/tmp/cave-search-index
	EOF
	mkdir -p "${mntgentoo}"/etc/paludis/tmp || die "mkdir failed"

	# add bashrc with cave aliases
	cat <<-EOF > "${mntgentoo}"/root/.bashrc || die "cat failed"
	# cave aliases

	source /etc/profile

	alias cs="cave search --index \${CAVE_SEARCH_INDEX}"
	alias cm="cave manage-search-index --create \${CAVE_SEARCH_INDEX}"
	alias cc='cave contents'
	alias cv='cave resolve'
	alias cvr="cave resolve \${CAVE_RESUME_FILE_OPT}"
	alias cw='cave show'
	alias co='cave owner'
	alias cu='cave uninstall'
	alias cy='cave sync'
	alias cr="cave resume -Cs \${CAVE_RESUME_FILE_OPT}"
	alias world-up="cave resolve \${CAVE_RESUME_FILE_OPT} -c -Cs -P '*/*' -Si world"
	alias system-up="cave resolve \${CAVE_RESUME_FILE_OPT} -c -Cs -P '*/*' -Si system"

	export PATH="/usr/local/bin:\$PATH"

	pbin_repo="/usr/gentoo-binhost"
	distdir="/srv/binhost"
	backupdir="/backup"

	# update the pbin digests in \${pbin_repo}
	update_pbin_digest() {
		local pkg f
		for pkg in \$(
				cd "\${pbin_repo}" && for f in */*; do
					echo \${f}
				done | grep -vE '(profiles|metadata)'
				) ; do
			cave digest \${pkg} gentoo-binhost
		done
	}

	# rm all pbin digests from \${pbin_repo}
	rm_pbin_digests() {
		rm -v "\${pbin_repo}"/*/*/Manifest
	}

	# rm all pbins from \${pbin_repo}
	rm_all_pbins() {
		rm -rv "\${pbin_repo}"/*
		git -C "\${pbin_repo}" checkout -- profiles
	}

	# rm a given pbin "category/packagename" from \${pbin_repo}
	rm_pbin() {
		local pbin=\$1
		rm -v "\${pbin_repo}"/"\${pbin}"
	}

	# remove binary tarballs from \${distdir}
	rm_distfiles() {
		rm -v "\${distdir}"/gentoo-binhost--*
	}

	# update the sha256sum.txt index in \${distdir}
	update_distfiles_shasum() {
		(
			cd "\${distdir}" &&
			rm sha256sum.txt &&
			for i in * ; do
				sha256sum \${i} >> sha256sum.txt
			done
		)
	}

	backup_distfiles() {
		cp -a "\${distdir}" "\${backupdir}/binhost-\$(date -u '+%Y-%m-%d-%H:%M:%S')"
	}

	cave-ask() {
		cave resolve --resume-file ~/cave_resume "\$@"
		local ret=\$?

		if [[ \$ret == 0 ]] ; then
			while true; do
				echo -e '\n'
				read -p "Do you wish to carry out these steps? [Y/n] " yn
				case \$yn in
					[Yy]* ) cave resume --resume-file ~/cave_resume ; break;;
					[Nn]* ) return 0 ;;
					"" ) cave resume --resume-file ~/cave_resume ; break;;
					* ) echo "Please answer yes or no.";;
				esac
			done
		fi
	}

	# bashcomp
	[[ -e /etc/bash/bashrc.d/bash_completion.sh ]] &&
		source /etc/bash/bashrc.d/bash_completion.sh
	EOF

	# fstab
	cat <<-EOF > "${mntgentoo}"/etc/fstab || die "cat failed"
	# <fs>                  <mountpoint>      <type>          <opts>              <dump/pass>
	LABEL=boot              /boot             ext2            noauto,noatime      0 0
	LABEL=root              /                 ext4            errors=remount-ro   0 0
	LABEL=swap              none              swap            sw                  0 0
	LABEL=docker            /var/lib/docker/  btrfs           defaults            0 0
	proc                    /proc             proc            defaults            0 0
	EOF

	# networking
	cat <<-EOF > "${mntgentoo}"/etc/conf.d/net || die "cat failed"
	config_eth0="${IPV4_IP} netmask ${IPV4_NETMASK} brd ${IPV4_BRD}
	${IPV6_IP}/${IPV6_MASK}"
	routes_eth0="default via ${IPV4_DEF_ROUTE}
	default via ${IPV6_DEF_ROUTE}"
	EOF

	cat <<-EOF >> "${mntgentoo}"/etc/hosts || die "cat failed"
	${IPV4_IP}   ${MYHOSTNAME}
	${IPV6_IP}   ${MYHOSTNAME}
	EOF

	cat <<-EOF >> "${mntgentoo}"/etc/conf.d/hostname || die "cat failed"
	hostname="${MYHOSTNAME}"
	EOF

	cat <<-EOF >> "${mntgentoo}"/etc/sudoers || die "cat failed"
	%wheel ALL=(ALL) ALL
	EOF

	# docker
	cat <<-EOF >> "${mntgentoo}"/etc/conf.d/docker || die "cat failed"
	DOCKER_OPTS="\${DOCKER_OPTS} -s btrfs"
	EOF
	mkdir -p "${mntgentoo}"/var/lib/docker

	# ssh
	sed -i \
		-e 's/PasswordAuthentication no/PasswordAuthentication yes/' \
		-e 's/#PermitRootLogin no/#PermitRootLogin yes/' \
		"${mntgentoo}"/etc/ssh/sshd_config || die "sed on /etc/ssh/sshd_config failed!"
}


bs_prep_install() {
	chroot_run 'ln -sf /etc/init.d/net.lo /etc/init.d/net.eth0 && ln -s /etc/init.d/net.eth0 /run/openrc/started/net.eth0'
	chroot_run 'echo UTC > /etc/timezone'
	chroot_run 'eselect locale set en_US.utf8 && env-update && source /etc/profile'
	chroot_run 'emerge-webrsync'
	chroot_run 'echo "sys-apps/paludis pbins search-index xml" >> /etc/portage/package.use/paludis && echo "sys-apps/paludis ~amd64" >> /etc/portage/package.accept_keywords'
	chroot_run 'emerge -v1 sys-apps/paludis app-eselect/eselect-package-manager'
	chroot_run 'eselect package-manager set paludis && . /etc/profile'
	chroot_run 'emerge -v1 dev-vcs/git app-portage/eix sys-apps/etckeeper'
	chroot_run 'etckeeper init -d /etc && git -C /etc config --local user.email "root@foo.com" && git -C /etc config --local user.name "Root User" && git -C /etc commit -am "Initial commit"'
	chroot_run 'git -C /etc submodule add https://github.com/hasufell/gentoo-server-config.git paludis && git -C /etc commit -am "Add paludis submodule"'
	chroot_run 'mkdir -p /var/cache/paludis/names /var/cache/paludis/metadata /var/tmp/paludis /var/db/paludis/repositories'
	chroot_run 'mkdir -p /srv/binhost && chown paludisbuild:paludisbuild /srv/binhost && chmod g+w /srv/binhost'
	chroot_run 'chown paludisbuild:paludisbuild /var/tmp/paludis && chmod g+w /var/tmp/paludis'
	chroot_run 'rm -r /usr/portage && git clone --depth=1 https://github.com/gentoo/gentoo.git /usr/portage && mkdir /usr/portage/distfiles && chown paludisbuild:paludisbuild /usr/portage/distfiles && chmod g+w /usr/portage/distfiles'
	chroot_run 'etckeeper init -d /etc'
	chroot_run 'cd /etc git submodule add https://github.com/hasufell/gentoo-server-config.git paludis'
	chroot_run 'git clone --depth=1 https://github.com/gentoo/libressl.git /var/db/paludis/repositories/libressl'
	chroot_run 'git clone --depth=1 https://github.com/hasufell/gentoo-binhost.git /usr/gentoo-binhost'
	chroot_run 'mkdir /etc/paludis/tmp && touch /etc/paludis/tmp/cave_resume /etc/paludis/tmp/cave-search-index && chown paludisbuild:paludisbuild /etc/paludis/tmp/cave_resume /etc/paludis/tmp/cave-search-index && chmod g+w /etc/paludis/tmp/cave_resume /etc/paludis/tmp/cave-search-index && chmod g+w /etc/paludis/tmp && chgrp paludisbuild /etc/paludis/tmp'
	chroot_run 'chgrp paludisbuild /dev/tty && env-update && . /etc/profile && cave sync'
}


bs_install_server_set() {
	# installation
	chroot_run 'echo server >> /var/lib/portage/world' # add server set to world file manually
	chroot_run "chgrp paludisbuild /dev/tty && cave resolve -e world --permit-old-version '*/*' -F sys-fs/eudev -U sys-fs/udev -x -f"
	chroot_run "chgrp paludisbuild /dev/tty && cave resolve -e world --permit-old-version '*/*' -F sys-fs/eudev -U sys-fs/udev -x"
}


bs_install_kernel() {
	# alternatively: wget http://bin.vm03.srvhub.de/kernel-4.2.5

	chroot_run 'cp /etc/paludis/kernel/config /usr/src/linux/.config'
	chroot_run 'cd /usr/src/linux && make olddefconfig'
	chroot_run 'cd /usr/src/linux && make -j4 && make modules_install && cp arch/x86/boot/bzImage /boot/kernel-$(readlink /usr/src/linux | sed "s/linux-//")'
}

bs_install_initrfamfs() {
	# alternatively: wget http://bin.vm03.srvhub.de/initrd-4.2.4

	cp ./mkinitrd.sh "${mntgentoo}"/sbin/mkinitrd.sh
	chroot_run 'chmod +x /sbin/mkinitrd.sh'
	chroot_run '/sbin/mkinitrd.sh'
}


bs_install_grub() {
	# grub
	sed -i -r \
		-e 's#^[[:space:]]*initrd=#  initrd=initrd#' \
		"${mntgentoo}"/etc/grub.d/10_linux || die
	echo 'GRUB_CMDLINE_LINUX="net.ifnames=0"' >> "${mntgentoo}"/etc/default/grub
	chroot_run 'grub2-install /dev/sda'
	chroot_run 'grub2-install /dev/sdb'
	chroot_run 'grub2-mkconfig -o /boot/grub/grub.cfg'
}

bs_update_runlevels() {
	# add stuff to default runlevel
	chroot_run 'rc-update add vmware-tools default'
	chroot_run 'rc-update add syslog-ng default'
	chroot_run 'rc-update add dhcpcd default'
	chroot_run 'rc-update add verynice default'
	chroot_run 'rc-update add sshd default'
	chroot_run 'rc-update add docker default'
	chroot_run 'rc-update add net.eth0 default'
	chroot_run 'rc-update add iptables default'
}


bs_cleanup() {
	# prepare reboot
	umount -l "${mntgentoo}"/dev{/shm,/pts,}
	umount "${mntgentoo}"{/boot,/sys,/proc,}
}


bs_postnote() {
	echo
	echo "Now create a root password via 'passwd' and reboot!"
	echo "Then disable password authentication and root login"
	echo "in /etc/ssh/sshd_config."
	echo
}


bs_all() {
	bs_partition
	bs_stage3
	bs_prep_chroot
	bs_create_cfg_files
	bs_prep_install
	bs_install_server_set
	bs_install_kernel
	bs_install_grub
	bs_update_runlevels
	bs_cleanup
	bs_postnote
}

#################


if [[ -n ${RUN_ALL} ]] ; then
	bs_all
fi
