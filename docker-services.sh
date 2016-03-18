#!/sbin/runscript
# Copyright 2015 Julian Ospald
# Distributed under the terms of the GNU General Public License v2

extra_commands="clean rmc update"
description_clean="Remove dangling images"
description_rmc="Remove the container"
description_update="For updating the images, you still need to restart them yourself"

image="${image:-gentoo${SVCNAME#docker}}"
container="${container:-${SVCNAME#docker-}}"
pidfile=/run/${SVCNAME}.pid
MAIN_NET="${MAIN_NET:-bridge}"

if [ "${MAIN_NET}" != "bridge" ] ; then
	need_dependencies="${need_dependencies} docker-network-${MAIN_NET}"
fi

if [ -n "${ADD_NETWORKS}" ] ; then
	for i in ${ADD_NETWORKS} ; do
		need_dependencies="${need_dependencies} docker-network-${i}"
	done
fi

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

# config variables:
#   GIT_REPO_PATH: local path to the repository, will be created if not a dir
#                  if empty, 'docker pull' is used
#   GIT_REPO_URL: clone url (must be set if GIT_REPO_PATH is set)
#   GIT_BRANCH: the branch to use (default master)
#   GIT_BUILD_PATH: build folder where the Dockerfile is,
#                   relative to GIT_REPO_PATH, default empty
update() {
	if [ -z "${DONT_TOUCH}" ] ; then
		ebegin "Updating image ${image}"
		if [ -n "${GIT_REPO_PATH}" ] ; then
			[ -n "${GIT_REPO_URL}" ] || {
				eerror "GIT_REPO_URL variable not set!"
				return 1
			}
			if [ -d "${GIT_REPO_PATH}" ] ; then
				git -C "${GIT_REPO_PATH}" fetch --depth=1 \
					origin
				git -C "${GIT_REPO_PATH}" reset --hard \
					origin/${GIT_BRANCH:-master}
			else
				git clone --depth=1 --branch \
					${GIT_BRANCH:-master} ${GIT_REPO_URL} \
					"${GIT_REPO_PATH}"
			fi
			docker build -t ${image} \
				"${GIT_REPO_PATH%/}/${GIT_BUILD_PATH}"
		else
			docker pull ${image}
		fi
		eend $?
	fi
}

start() {
	# decide whether we can just run the existing container or have to
	# create it from scratch
	if docker inspect --type=container --format="{{.}}" \
			${container} >/dev/null 2>&1 ; then
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
				$([ "${MAIN_NET}" != "bridge" ] && echo "--net=${MAIN_NET}") \
				--name=${container} \
				${RUN_ARGS} \
				${image}

		if [ -n "${ADD_NETWORKS}" ] ; then
			local i
			ebegin "Connecting to additional networks"
			for i in ${ADD_NETWORKS} ; do
				docker network connect ${i} ${container}
			done
		fi
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

