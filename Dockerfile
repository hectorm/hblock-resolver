FROM ubuntu:18.04

# Environment
ENV HBLOCK_BRANCH=v1.5.4
ENV HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
ENV KNOT_RESOLVER_BRANCH=master
ENV KNOT_RESOLVER_REMOTE=https://github.com/cz-nic/knot-resolver.git
ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_PKGS=' \
	autoconf \
	automake \
	g++ \
	gcc \
	git \
	libcmocka-dev \
	libedit-dev \
	libfstrm-dev \
	libgeoip-dev \
	libgnutls28-dev \
	libjansson-dev \
	libknot-dev \
	liblmdb-dev \
	libluajit-5.1-dev \
	libprotobuf-c-dev \
	libprotobuf-dev \
	libssl-dev \
	libtool \
	liburcu-dev \
	libuv1-dev \
	luarocks \
	make \
	pkg-config \
	protobuf-c-compiler \
	xxd \
'
ENV RUN_PKGS=' \
	ca-certificates \
	cron \
	curl \
	dns-root-data \
	gzip \
	libedit2 \
	libfstrm0 \
	libgcc1 \
	libgeoip1 \
	libgnutls30 \
	libjansson4 \
	libknot7 \
	libkres6 \
	liblmdb0 \
	libprotobuf-c1 \
	libprotobuf10 \
	libssl1.1 \
	libstdc++6 \
	liburcu6 \
	libuv1 \
	libzscanner1 \
	luajit \
	supervisor \
'

RUN apt-get update \
	# Install dependencies
	&& apt-get install -y ${BUILD_PKGS} ${RUN_PKGS} \
	&& luarocks install cqueues \
	&& luarocks install http \
	&& luarocks install luasec \
	&& luarocks install luasocket \
	&& luarocks install mmdblua \
	# Install Knot Resolver
	&& git clone --recursive --branch "${KNOT_RESOLVER_BRANCH}" "${KNOT_RESOLVER_REMOTE}" /tmp/knot-resolver/ \
	&& make -C /tmp/knot-resolver/ \
		CFLAGS='-O2 -fstack-protector' \
		PREFIX=/usr/ \
		MODULEDIR=/usr/lib/knot-resolver/ \
		ETCDIR=/etc/knot-resolver/ \
		ROOTHINTS=/usr/share/dns/root.hints \
		KEYFILE_DEFAULT=/usr/share/dns/root.key \
		-j$(nproc) check install \
	&& rm -f /etc/knot-resolver/root.hints /etc/knot-resolver/icann-ca.pem \
	&& mkdir -p /var/lib/knot-resolver/ \
	&& adduser --system --group --home /var/cache/knot-resolver/ knot-resolver \
	&& chown -R root:knot-resolver /etc/knot-resolver/ /var/lib/knot-resolver/ \
	# Install hBlock
	&& git clone --recursive --branch "${HBLOCK_BRANCH}" "${HBLOCK_REMOTE}" /tmp/hblock/ \
	&& mv /tmp/hblock/hblock /usr/bin/hblock \
	&& chmod 755 /usr/bin/hblock \
	# Cleanup
	&& apt-get purge -y ${BUILD_PKGS} \
	&& apt-get autoremove -y \
	&& rm -rf /tmp/* /etc/cron.*/ /var/lib/apt/lists/*

# Copy config and scripts
COPY --chown=root:root config/supervisord.conf /etc/supervisord.conf
COPY --chown=root:root config/crontab /etc/crontab
COPY --chown=root:knot-resolver config/kresd.conf.lua /etc/knot-resolver/kresd.conf
COPY --chown=root:root scripts/ /usr/bin/

WORKDIR /var/lib/knot-resolver/
VOLUME /var/lib/knot-resolver/

EXPOSE 53/tcp 53/udp 8053/tcp

HEALTHCHECK --start-period=60s --interval=60s --timeout=3s --retries=3 \
	CMD ["/bin/sh", "-c", '[ "$(curl -fs http://localhost:8053/health)" = OK ]']

CMD ["/usr/bin/docker-foreground-cmd"]
