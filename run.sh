#!/bin/sh

set -eu
export LC_ALL=C

DOCKER_IMAGE_NAMESPACE=hectormolinero
DOCKER_IMAGE_NAME=hblock-resolver
DOCKER_IMAGE_VERSION=latest
DOCKER_IMAGE=${DOCKER_IMAGE_NAMESPACE}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}
DOCKER_CONTAINER=${DOCKER_IMAGE_NAME}
DOCKER_VOLUME=${DOCKER_CONTAINER}-data

imageExists() { [ -n "$(docker images -q "$1")" ]; }
containerExists() { docker ps -aqf name="$1" --format '{{.Names}}' | grep -Fxq "$1"; }
containerIsRunning() { docker ps -qf name="$1" --format '{{.Names}}' | grep -Fxq "$1"; }

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

if [ -z "${HBLOCK_SOURCES-}" ] && [ -f '/etc/hblock-resolver/hblock.conf.d/sources.list' ]; then
	HBLOCK_SOURCES=$(cat /etc/hblock-resolver/hblock.conf.d/sources.list)
fi

if [ -z "${HBLOCK_WHITELIST-}" ] && [ -f '/etc/hblock-resolver/hblock.conf.d/whitelist.list' ]; then
	HBLOCK_WHITELIST=$(cat /etc/hblock-resolver/hblock.conf.d/whitelist.list)
fi

if [ -z "${HBLOCK_BLACKLIST-}" ] && [ -f '/etc/hblock-resolver/hblock.conf.d/blacklist.list' ]; then
	HBLOCK_BLACKLIST=$(cat /etc/hblock-resolver/hblock.conf.d/blacklist.list)
fi

if [ -z "${KRESD_ADDITIONAL_CONF_DIR-}" ] && [ -d '/etc/hblock-resolver/kresd.conf.d/' ]; then
	KRESD_ADDITIONAL_CONF_DIR='/etc/hblock-resolver/kresd.conf.d/'
fi

if [ -z "${KRESD_EXTERNAL_CERT_KEY-}" ] && [ -f '/etc/hblock-resolver/ssl/server.key' ]; then
	KRESD_EXTERNAL_CERT_KEY='/etc/hblock-resolver/ssl/server.key'
fi

if [ -z "${KRESD_EXTERNAL_CERT-}" ] && [ -f '/etc/hblock-resolver/ssl/server.crt' ]; then
	KRESD_EXTERNAL_CERT='/etc/hblock-resolver/ssl/server.crt'
fi

printf -- '%s\n' "Creating \"${DOCKER_CONTAINER}\" container..."
docker run --detach \
	--name "${DOCKER_CONTAINER}" \
	--hostname "${DOCKER_CONTAINER}" \
	--restart on-failure:3 \
	--log-opt max-size=32m \
	--publish '53:53/tcp' \
	--publish '53:53/udp' \
	--publish '127.0.0.1:8053:8053/tcp' --publish '[::1]:8053:8053/tcp' \
	--mount type=volume,src="${DOCKER_VOLUME}",dst='/var/lib/knot-resolver/' \
	${HBLOCK_SOURCES+ \
		--env HBLOCK_SOURCES="${HBLOCK_SOURCES}" \
	} \
	${HBLOCK_WHITELIST+ \
		--env HBLOCK_WHITELIST="${HBLOCK_WHITELIST}" \
	} \
	${HBLOCK_BLACKLIST+ \
		--env HBLOCK_BLACKLIST="${HBLOCK_BLACKLIST}" \
	} \
	${KRESD_NIC+ \
		--env KRESD_NIC="${KRESD_NIC}" \
	} \
	${KRESD_EXTERNAL_CERT_KEY+${KRESD_EXTERNAL_CERT+ \
		--publish '853:853/tcp' \
		--mount type=bind,src="${KRESD_EXTERNAL_CERT_KEY}",dst='/var/lib/knot-resolver/ssl/server.key',ro \
		--mount type=bind,src="${KRESD_EXTERNAL_CERT}",dst='/var/lib/knot-resolver/ssl/server.crt',ro \
		--env KRESD_CERT_MODE=external \
	}} \
	${KRESD_ADDITIONAL_CONF_DIR+ \
		--mount type=bind,src="${KRESD_ADDITIONAL_CONF_DIR}",dst='/etc/knot-resolver/kresd.conf.d/',ro \
	} \
	"${DOCKER_IMAGE}" "$@" >/dev/null

printf -- '%s\n\n' 'Done!'
exec docker logs -f "${DOCKER_CONTAINER}"
