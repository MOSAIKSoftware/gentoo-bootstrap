#!/bin/bash

die() {
  echo "$@"
  exit 1
}

monitor_ip="8.8.8.8"
initrd_dir="/usr/src/initramfs"

# need to be mounted rw, else it will be ro
mount -o remount -rw /boot

if [[ -z ${IPV4_IP} ||
		-z ${IPV4_DEF_ROUTE}
		]] ; then
	die "some required environment variables have not been set!"
fi

if [[ -e ${initrd_dir} ]] ; then
	die "${initrd_dir} already exists! Back it up first."
fi


mkdir -p "${initrd_dir}" || die
pushd "${initrd_dir}" || die
mkdir -p bin lib lib64 dev etc mnt/root proc root sbin sys || die

# devices
cp -a /dev/{null,console,tty,md?,sd*,urandom,random} "${initrd_dir}"/dev/ || die

# mdadm stuff
cp -a /sbin/mdadm "${initrd_dir}"/sbin/ || die

# dropbear
mkdir -p "${initrd_dir}"/etc/dropbear || die
cp -a /usr/sbin/dropbear "${initrd_dir}"/sbin/ || die
cp -a /usr/bin/{dropbearkey,dbclient,dropbearconvert,dbscp} "${initrd_dir}"/bin/ || die
cp -a /lib64/libz.so* /lib64/libcrypt.so* /lib64/libcrypt-*.so* /lib64/libutil* /lib64/ld-* /lib64/libc.so* /lib64/libc-*.so* /lib64/libnss* /lib64/libnsl* /lib64/libresolv-*.so* /lib64/libresolv.so* "${initrd_dir}"/lib64/ || die

# busybox and symlinks
cp -a /bin/busybox "${initrd_dir}"/bin/busybox || die
chroot "${initrd_dir}" /bin/busybox --install -s || die

# other binaries
cp -a /usr/bin/strace "${initrd_dir}"/bin/ || die

# for elinks
cp -a /usr/bin/elinks "${initrd_dir}"/bin/ || die
cp -a /lib64/libbz2.so* /usr/lib64/libgc.so* /usr/lib64/libexpat.so* "${initrd_dir}"/lib64/ || die

# needed for dropbear
cat <<EOF > "${initrd_dir}"/etc/passwd || die "cat failed"
root:x:0:0:root:/root:/bin/sh
EOF

# needed for dropbear
cat <<EOF > "${initrd_dir}"/etc/group || die "cat failed"
root:x:0:root
EOF

# needed for dropbear
cat <<EOF > "${initrd_dir}"/etc/resolv.conf || die "cat failed"
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# TODO: copy pubkeys

cat <<EOF > "${initrd_dir}"/init || die "cat failed"
#!/bin/busybox sh

rescue_shell() {
	echo "Something went wrong. Dropping you to a shell."
	exec /bin/sh
}

echo "This script mounts rootfs and boots it up, nothing more!"

mount -t proc none /proc || rescue_shell
mount -t sysfs none /sys || rescue_shell
mdev -s || rescue_shell
mkdir /dev/pts || rescue_shell
mount -t devpts /dev/pts /dev/pts || rescue_shell

# start network
# start network
echo "Starting network"
ifconfig eth0 ${IPV4_IP}
ifconfig eth0 up
route add default gw ${IPV4_DEF_ROUTE}
_timeout=0
while ! ping -c 1 -W 1 ${monitor_ip} > /dev/null && [ \${_timeout} -lt 15 ] ; do
	echo "Waiting for ${IPV4_IP} - network interface might be down..."
	_timeout=\$(( \${_timeout} + 1 ))
	sleep 1
done

# start dropbear
dropbear -R -s -m -p 22922

# mount rootfs
mount -o ro /dev/sda4 /mnt/root || rescue_shell

# clean up networking
route del default gw ${IPV4_DEF_ROUTE}
ifconfig eth0 down
ip addr flush dev eth0
killall dropbear

# Clean up.
echo "Unmounting stuff"
umount -l /dev/pts
umount /proc || rescue_shell
umount /sys || rescue_shell

exec switch_root /mnt/root /sbin/init || rescue_shell
EOF

chmod +x "${initrd_dir}"/init || die

if [[ -e /boot/initrd ]] ; then
	die "/boot/initrd already exists! Back it up first."
else
	cd "${initrd_dir}" || die
	find . -print0 | cpio --null -ov --format=newc | gzip -9 > /boot/initrd || die
fi

popd
