#!/bin/sh

set -eu
export LC_ALL=C

DOCKER_IMAGE=hblock-resolver
DOCKER_CONTAINER=hblock-resolver

imageExists() { [ -n "$(docker images -q "$1")" ]; }
containerExists() { docker ps -aqf name="$1" --format '{{.Names}}' | grep -qw "$1"; }
containerIsRunning() { docker ps -qf name="$1" --format '{{.Names}}' | grep -qw "$1"; }

if ! imageExists "${DOCKER_IMAGE}"; then
	>&2 printf -- '%s\n' "${DOCKER_IMAGE} image doesn't exist!"
	exit 1
fi

if containerIsRunning "${DOCKER_CONTAINER}"; then
	printf -- '%s\n' "Stopping \"${DOCKER_CONTAINER}\" container..."
	docker stop "${DOCKER_CONTAINER}" >/dev/null
fi

if containerExists "${DOCKER_CONTAINER}"; then
	printf -- '%s\n' "Removing \"${DOCKER_CONTAINER}\" container..."
	docker rm "${DOCKER_CONTAINER}" >/dev/null
fi

printf -- '%s\n' "Creating \"${DOCKER_CONTAINER}\" container..."
exec docker run --detach \
	--name "${DOCKER_CONTAINER}" \
	--hostname 'hblock-resolver' \
	--cpus 0.5 \
	--memory 256mb \
	--restart on-failure:3 \
	--log-opt max-size=32m \
	--publish '153:53/tcp' \
	--publish '153:53/udp' \
	--publish '127.0.0.1:8053:8053/tcp' --publish '[::1]:8053:8053/tcp' \
	--mount type=volume,src='hblock-resolver-data',dst='/var/lib/knot-resolver/' \
	"${DOCKER_IMAGE}" "$@"
