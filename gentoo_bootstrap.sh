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


tasks=(	greeter
	partition
	stage3
	prep_chroot
	create_cfg_files
	prep_install
	install_server_set
	install_kernel
	install_grub
	update_runlevels
	cleanup
	postnote )

scripts_dir=$(dirname $0)
RUN_CMD="$1"
########################

cd "$scripts_dir"
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
		-z ${MYHOSTNAME} ||
		-z ${PROFILE}
		]] ; then
	die "some required environment variables have not been set!"
fi

### PROFILES ###
echo "Profile: ${scripts_dir}/${PROFILE}"
if [[ ! -e "${scripts_dir}/${PROFILE}/conf.sh" ]]; then 
	die "conf.sh missing in profile" 
fi
if [[ ! -e "${scripts_dir}/${PROFILE}/partition.sh" ]]; then 
	die "partition.sh missing in profile" 
fi
if [[ ! -e "${scripts_dir}/${PROFILE}/update-grub.sh" ]]; then
 	die "update-grub.sh missing in profile" 
fi

source "${scripts_dir}/${PROFILE}/conf.sh"
source "${scripts_dir}/${PROFILE}/partition.sh"

### FUNCTIONS ###
bs_greeter () {
	echo "=== GENTOO BOOTSTRAP ==="
}

bs_partition() {
	# partitioning
	bs_partition_disk_profile_create 
	bs_partition_disk_profile_mkfs
	bs_partition_disk_profile_mount
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
	cp ./docker-services.sh \
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
	chroot_run 'git clone --depth=1 https://github.com/hasufell/libressl.git /var/db/paludis/repositories/libressl'
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

	cp ./mkkernel.sh "${mntgentoo}"/sbin/mkkernel.sh
	chroot_run 'chmod +x /sbin/mkkernel.sh'
	chroot_run '/sbin/mkkernel.sh'
}

bs_install_initrfamfs() {
	# alternatively: wget http://bin.vm03.srvhub.de/initrd-4.2.4

	cp ./mkinitrd.sh "${mntgentoo}"/sbin/mkinitrd.sh
	chroot_run 'chmod +x /sbin/mkinitrd.sh'
	chroot_run '/sbin/mkinitrd.sh'
}


bs_install_grub() {
	# grub

	cp "./${PROFILE}/update-grub.sh" "${mntgentoo}"/sbin/update-grub.sh
	chroot_run 'chmod +x /sbin/update-grub.sh'
	chroot_run '/sbin/update-grub.sh'
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


## 
# Run tasks before and including $1 
# remember if a task finished before
bs_to() {
	till_cmd=$1

	for cmd in ${tasks[@]}; do
		if [[ -e /tmp/bs_${cmd}_done ]]; then
			echo "$cmd allready done"
		else 
			echo "running $cmd"	
			bs_${cmd} && touch /tmp/bs_${cmd}_done	
		fi

		if [[ ${cmd} = ${till_cmd}  ]]; then 
			break
		fi

	done
}

bs_all() {
	for cmd in ${tasks[@]}; do
		bs_to ${cmd}
	done
}

#################


if [[ -n ${RUN_ALL} ]] ; then
	bs_all
elif [[ -n ${RUN_CMD} ]] ; then
	bs_to ${RUN_CMD}
else 
	echo "Usage: "
fi
