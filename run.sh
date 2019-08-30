#!/bin/sh

set -eu
export LC_ALL=C

IMAGE_NAMESPACE=hectormolinero
IMAGE_PROJECT=hblock-resolver
IMAGE_TAG=latest
IMAGE_NAME=${IMAGE_NAMESPACE:?}/${IMAGE_PROJECT:?}:${IMAGE_TAG:?}
CONTAINER_NAME=${IMAGE_PROJECT:?}
VOLUME_NAME=${CONTAINER_NAME:?}-data

imageExists() { [ -n "$(docker images -q "$1")" ]; }
containerExists() { docker ps -aqf name="$1" --format '{{.Names}}' | grep -Fxq "$1"; }
containerIsRunning() { docker ps -qf name="$1" --format '{{.Names}}' | grep -Fxq "$1"; }

if ! imageExists "${IMAGE_NAME:?}"; then
	>&2 printf -- '%s\n' "\"${IMAGE_NAME:?}\" image doesn't exist!"
	exit 1
fi

if containerIsRunning "${CONTAINER_NAME:?}"; then
	printf -- '%s\n' "Stopping \"${CONTAINER_NAME:?}\" container..."
	docker stop "${CONTAINER_NAME:?}" >/dev/null
fi

if containerExists "${CONTAINER_NAME:?}"; then
	printf -- '%s\n' "Removing \"${CONTAINER_NAME:?}\" container..."
	docker rm "${CONTAINER_NAME:?}" >/dev/null
fi

if [ -z "${HBLOCK_HEADER_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/header' ]; then
	HBLOCK_HEADER_FILE=/etc/hblock-resolver/hblock.d/header
fi

if [ -z "${HBLOCK_FOOTER_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/footer' ]; then
	HBLOCK_FOOTER_FILE=/etc/hblock-resolver/hblock.d/footer
fi

if [ -z "${HBLOCK_SOURCES_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/sources.list' ]; then
	HBLOCK_SOURCES_FILE=/etc/hblock-resolver/hblock.d/sources.list
fi

if [ -z "${HBLOCK_WHITELIST_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/whitelist.list' ]; then
	HBLOCK_WHITELIST_FILE=/etc/hblock-resolver/hblock.d/whitelist.list
fi

if [ -z "${HBLOCK_BLACKLIST_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/blacklist.list' ]; then
	HBLOCK_BLACKLIST_FILE=/etc/hblock-resolver/hblock.d/blacklist.list
fi

if [ -z "${KRESD_CONF_FILE-}" ] && [ -f '/etc/hblock-resolver/kresd.conf' ]; then
	KRESD_CONF_FILE='/etc/hblock-resolver/kresd.conf'
fi

if [ -z "${KRESD_CONF_DIR-}" ] && [ -d '/etc/hblock-resolver/kresd.conf.d/' ]; then
	KRESD_CONF_DIR='/etc/hblock-resolver/kresd.conf.d/'
fi

printf -- '%s\n' "Creating \"${CONTAINER_NAME:?}\" container..."
docker run --detach \
	--name "${CONTAINER_NAME:?}" \
	--hostname "${CONTAINER_NAME:?}" \
	--restart on-failure:3 \
	--log-opt max-size=32m \
	--dns '1.1.1.1' --dns '1.0.0.1' \
	--publish '127.0.0.1:53:53/udp' \
	--publish '127.0.0.1:53:53/tcp' \
	--publish '127.0.0.1:853:853/tcp' \
	--publish '127.0.0.1:8453:8453/tcp' \
	--mount type=volume,src="${VOLUME_NAME:?}",dst='/var/lib/knot-resolver/' \
	${HBLOCK_HEADER_FILE+--mount type=bind,src="${HBLOCK_HEADER_FILE:?}",dst='/etc/hblock.d/header',ro} \
	${HBLOCK_FOOTER_FILE+--mount type=bind,src="${HBLOCK_FOOTER_FILE:?}",dst='/etc/hblock.d/footer',ro} \
	${HBLOCK_SOURCES_FILE+--mount type=bind,src="${HBLOCK_SOURCES_FILE:?}",dst='/etc/hblock.d/sources.list',ro} \
	${HBLOCK_WHITELIST_FILE+--mount type=bind,src="${HBLOCK_WHITELIST_FILE:?}",dst='/etc/hblock.d/whitelist.list',ro} \
	${HBLOCK_BLACKLIST_FILE+--mount type=bind,src="${HBLOCK_BLACKLIST_FILE:?}",dst='/etc/hblock.d/blacklist.list',ro} \
	${KRESD_CONF_FILE+--mount type=bind,src="${KRESD_CONF_FILE:?}",dst='/etc/knot-resolver/kresd.conf',ro} \
	${KRESD_CONF_DIR+$(
		for file in "${KRESD_CONF_DIR-}"/*; do
			[ -e "${file:?}" ] || continue
			srcFile="$(readlink -f -- "${file:?}")"
			dstFile="/etc/knot-resolver/kresd.conf.d/$(basename -- "${file:?}")"
			printf -- ' --mount type=bind,src=%s,dst=%s,ro' "${srcFile:?}" "${dstFile:?}"
		done
	)} \
	"${IMAGE_NAME:?}" "$@" >/dev/null

printf -- '%s\n\n' 'Done!'
exec docker logs -f "${CONTAINER_NAME:?}"
