#!/sbin/runscript
# Copyright 2015 Julian Ospald
# Distributed under the terms of the GNU General Public License v2
# $Id$

extra_commands="clean rmc update"
description_clean="Remove dangling images"
description_rmc="Remove the container"
description_update="For updating the images, you still need to restart them yourself"

image="${image:-gentoo${SVCNAME#docker}}"
container="${container:-${SVCNAME#docker-}}"
pidfile=/run/${SVCNAME}.pid

depend() {
	need docker ${need_dependencies}
	use net ${use_dependencies}
}


create_pid_file() {
	# docker daemon does not create container PID files for us
	docker inspect -f {{.State.Pid}} ${container} \
		> "${pidfile}"
}

clean() {
	if [ -z "${DONT_TOUCH}" ] ; then
		ebegin "Cleaning up dangling images"
		docker rmi $(docker images -q -f dangling=true)
		eend $?
	fi
}

rmc() {
	if [ -z "${DONT_TOUCH}" ] ; then
		ebegin "Removing ${container}"
		docker rm ${container}
		eend $?
	fi
}

update() {
	if [ -z "${DONT_TOUCH}" ] ; then
		ebegin "Updating image ${image}"
		if [ -n "${GIT_REPO_PATH}" ] ; then
			if [ -d "${GIT_REPO_PATH}" ] ; then
				git -C "${GIT_REPO_PATH}" pull --depth=1 ${GIT_REMOTE:-origin} ${GIT_BRANCH:-master}
			else
				git clone --depth=1 ${GIT_REPO_URL} --branch ${GIT_BRANCH:-master}
			fi
			docker build -t ${image} "${GIT_REPO_PATH}"
		else
			docker pull ${image}
		fi
		eend $?
	fi
}

start() {
	# decide whether we can just run the existing container or have to
	# create it from scratch
	if docker inspect --type=container --format="{{.}}" ${container} >/dev/null 2>&1 ; then
		ebegin "Starting container ${container}"
		start-stop-daemon --start \
			--pidfile "${pidfile}" \
			--exec docker \
			-- \
				start ${container}
	else
		ebegin "Starting container ${container} from image ${image}"
		start-stop-daemon --start \
			--pidfile "${pidfile}" \
			--exec docker \
			-- \
				run -ti -d \
				--name=${container} \
				${RUN_ARGS} \
				${image}
	fi
	create_pid_file
	eend $?
}

stop() {
	# start-stop-daemon messes up here
	ebegin "Stopping ${container}"
	docker stop ${container}
	if [ -n "${FULL_STOP}" ] && [ -z "${DONT_TOUCH}" ] ; then
		docker rm ${container}
	fi
	rm -f "${pidfile}"
	eend $?
}
