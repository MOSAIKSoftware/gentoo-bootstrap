#!/sbin/runscript
# Copyright 2016 Julian Ospald
# Distributed under the terms of the GNU General Public License v2

network_name=${SVCNAME#docker-network-}

depend() {
	need net
}

start() {
	ebegin "Starting network ${network_name}"
	docker network create ${network_name}
	eend $?
}

stop() {
	ebegin "Stopping network ${network_name}"
	docker network rm ${network_name}
	eend $?
}

