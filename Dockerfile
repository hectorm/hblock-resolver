FROM ubuntu:18.04

# Environment
ARG HBLOCK_BRANCH=master
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
ARG KNOT_RESOLVER_BRANCH=master
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_SKIP_INSTALL_CHECK=false
ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_PKGS=' \
	autoconf \
	automake \
	cmake \
	dpkg-dev \
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
	python3-augeas \
	python3-dnspython \
	python3-jinja2 \
	python3-pytest \
	python3-pytest-xdist \
	python3-yaml \
	xxd \
'
ENV RUN_PKGS=' \
	ca-certificates \
	cron \
	curl \
	dns-root-data \
	gzip \
	knot-dnsutils \
	knot-host \
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
ENV LUAROCKS_PKGS=' \
	cqueues \
	http \
	luasec \
	luasocket \
	mmdblua \
'

RUN apt-get update \
	# Install dependencies
	&& apt-get install -y --no-install-recommends ${BUILD_PKGS} ${RUN_PKGS} \
	&& HOST_MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" \
	&& printf '%s\n' ${LUAROCKS_PKGS} | xargs -n1 -iPKG luarocks install PKG \
		OPENSSL_LIBDIR="/usr/lib/${HOST_MULTIARCH}" \
		CRYPTO_LIBDIR="/usr/lib/${HOST_MULTIARCH}" \
	# Install Knot Resolver
	&& git clone --recursive --branch "${KNOT_RESOLVER_BRANCH}" "${KNOT_RESOLVER_REMOTE}" /tmp/knot-resolver/ \
	&& (cd /tmp/knot-resolver/ \
		&& make \
			CFLAGS='-O2 -fstack-protector' \
			PREFIX=/usr \
			MODULEDIR=/usr/lib/knot-resolver \
			ETCDIR=/etc/knot-resolver \
			ROOTHINTS=/usr/share/dns/root.hints \
			-j$(nproc) check install \
		&& rm /etc/knot-resolver/root.hints \
		&& if [ "${KNOT_RESOLVER_SKIP_INSTALL_CHECK}" != true ]; then \
			make PREFIX=/usr installcheck \
			&& make PREFIX=/usr check-integration; \
		fi \
		&& /usr/sbin/kresd --version \
	) \
	&& groupadd -r -g 500 knot-resolver \
	&& useradd -r -u 500 -g 500 -md /var/cache/knot-resolver/ knot-resolver \
	&& mkdir -p /var/lib/knot-resolver/ \
	&& chown -R root:knot-resolver /etc/knot-resolver/ /var/lib/knot-resolver/ \
	# Install hBlock
	&& git clone --recursive --branch "${HBLOCK_BRANCH}" "${HBLOCK_REMOTE}" /tmp/hblock/ \
	&& mv /tmp/hblock/hblock /usr/bin/hblock \
	&& chmod 755 /usr/bin/hblock \
	&& /usr/bin/hblock --version \
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
	CMD [ "$(curl -fs http://localhost:8053/health)" = OK ]

CMD ["/usr/bin/docker-foreground-cmd"]
