#!/bin/sh

set -eu
export LC_ALL=C

DOCKER=$(command -v docker 2>/dev/null)

IMAGE_REGISTRY=docker.io
IMAGE_NAMESPACE=hectorm
IMAGE_PROJECT=hblock-resolver
IMAGE_TAG=latest
IMAGE_NAME=${IMAGE_REGISTRY:?}/${IMAGE_NAMESPACE:?}/${IMAGE_PROJECT:?}:${IMAGE_TAG:?}
CONTAINER_NAME=${IMAGE_PROJECT:?}

imageExists() { [ -n "$("${DOCKER:?}" images -q "${1:?}")" ]; }
containerExists() { "${DOCKER:?}" ps -af name="${1:?}" --format '{{.Names}}' | grep -Fxq "${1:?}"; }
containerIsRunning() { "${DOCKER:?}" ps -f name="${1:?}" --format '{{.Names}}' | grep -Fxq "${1:?}"; }

if ! imageExists "${IMAGE_NAME:?}" && ! imageExists "${IMAGE_NAME#docker.io/}"; then
	>&2 printf '%s\n' "\"${IMAGE_NAME:?}\" image doesn't exist!"
	exit 1
fi

if containerIsRunning "${CONTAINER_NAME:?}"; then
	printf '%s\n' "Stopping \"${CONTAINER_NAME:?}\" container..."
	"${DOCKER:?}" stop "${CONTAINER_NAME:?}" >/dev/null
fi

if containerExists "${CONTAINER_NAME:?}"; then
	printf '%s\n' "Removing \"${CONTAINER_NAME:?}\" container..."
	"${DOCKER:?}" rm "${CONTAINER_NAME:?}" >/dev/null
fi

printf '%s\n' "Creating \"${CONTAINER_NAME:?}\" container..."
"${DOCKER:?}" run --detach \
	--name "${CONTAINER_NAME:?}" \
	--hostname "${CONTAINER_NAME:?}" \
	--restart on-failure:3 \
	--log-opt max-size=32m \
	--user "$(shuf -i100000-200000 -n1)" \
	--publish '127.0.0.153:53:53/udp' \
	--publish '127.0.0.153:53:53/tcp' \
	--publish '127.0.0.153:443:443/tcp' \
	--publish '127.0.0.153:853:853/tcp' \
	--publish '127.0.0.153:8453:8453/tcp' \
	--mount type=volume,src="${CONTAINER_NAME:?}-data",dst='/var/lib/knot-resolver/' \
	--mount type=volume,src="${CONTAINER_NAME:?}-cache",dst='/var/cache/knot-resolver/' \
	--env KRESD_INSTANCE_NUMBER=4 \
	"${IMAGE_NAME:?}" "$@" >/dev/null

printf '%s\n\n' 'Done!'
exec "${DOCKER:?}" logs -f "${CONTAINER_NAME:?}"
