m4_changequote([[, ]])

m4_ifdef([[CROSS_QEMU]], [[
##################################################
## "qemu-user-static" stage
##################################################

FROM ubuntu:18.04 AS qemu-user-static
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends qemu-user-static
]])

##################################################
## "build-main" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM CROSS_ARCH/ubuntu:18.04]], [[FROM ubuntu:18.04]]) AS build-main
m4_ifdef([[CROSS_QEMU]], [[COPY --from=qemu-user-static CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		autoconf \
		automake \
		build-essential \
		ca-certificates \
		checkinstall \
		cmake \
		curl \
		debhelper \
		dh-systemd \
		dns-root-data \
		file \
		gawk \
		git \
		libaugeas-dev \
		libcmocka-dev \
		libedit-dev \
		libffi-dev \
		libgeoip-dev \
		libgnutls28-dev \
		libidn2-dev \
		libjansson-dev \
		liblmdb-dev \
		libluajit-5.1-dev \
		libssl-dev \
		libsystemd-dev \
		libtool \
		libunistring-dev \
		liburcu-dev \
		libuv1-dev \
		luajit \
		luarocks \
		pkg-config \
		python3 \
		python3-dev \
		python3-pip \
		python3-setuptools \
		python3-wheel \
		tzdata \
		xxd \
	&& rm -rf /var/lib/apt/lists/*

# Install LuaRocks packages
RUN HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH) \
	&& printf '%s\n' \
		cqueues \
		http \
		luafilesystem \
		luasec \
		luasocket \
		mmdblua \
	| xargs -n1 -iPKG luarocks install PKG \
		CRYPTO_LIBDIR="/usr/lib/${HOST_MULTIARCH}" \
		OPENSSL_LIBDIR="/usr/lib/${HOST_MULTIARCH}"

# Build Knot DNS (only libknot and utilities)
ARG KNOT_DNS_TREEISH=v2.7.6
ARG KNOT_DNS_REMOTE=https://gitlab.labs.nic.cz/knot/knot-dns.git
RUN mkdir -p /tmp/knot-dns/ && cd /tmp/knot-dns/ \
	&& git clone "${KNOT_DNS_REMOTE}" ./ \
	&& git checkout "${KNOT_DNS_TREEISH}" \
	&& git submodule update --init --recursive
RUN cd /tmp/knot-dns/ \
	&& ./autogen.sh \
	&& ./configure \
		--prefix=/usr \
		--enable-utilities \
		--enable-fastparser \
		--disable-daemon \
		--disable-modules \
		--disable-dnstap \
		--disable-documentation \
	&& make -j"$(nproc)" \
	&& checkinstall --default \
		--pkgname=knot-dns \
		--pkgversion=0 --pkgrelease=0 \
		--exclude=/usr/include/,/usr/lib/pkgconfig/,/usr/share/man/ --nodoc \
		make install \
	&& file /usr/bin/kdig && /usr/bin/kdig --version \
	&& file /usr/bin/khost && /usr/bin/khost --version

# Build Knot Resolver
ARG KNOT_RESOLVER_TREEISH=v3.2.1
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_INSTALLATION_TESTS=enabled
ARG KNOT_RESOLVER_INTEGRATION_TESTS=enabled
RUN mkdir -p /tmp/knot-resolver/ && cd /tmp/knot-resolver/ \
	&& git clone "${KNOT_RESOLVER_REMOTE}" ./ \
	&& git checkout "${KNOT_RESOLVER_TREEISH}" \
	&& git submodule update --init --recursive
RUN cd /tmp/knot-resolver/ \
	&& pip3 install --user -r ./tests/pytests/requirements.txt \
	&& pip3 install --user -r ./tests/deckard/requirements.txt
RUN cd /tmp/knot-resolver/ \
	&& export CFLAGS='-O2 -fstack-protector' \
	&& export PREFIX=/usr \
	&& export ETCDIR=/etc/knot-resolver \
	&& export MODULEDIR=/usr/lib/knot-resolver \
	&& export ROOTHINTS=/usr/share/dns/root.hints \
	&& make -j"$(nproc)" \
	&& make check \
	&& checkinstall --default \
		--pkgname=knot-resolver \
		--pkgversion=0 --pkgrelease=0 \
		--exclude=/usr/include/,/usr/lib/pkgconfig/,/usr/share/man/ --nodoc \
		make install \
	&& if [ "${KNOT_RESOLVER_INSTALLATION_TESTS}" = enabled ]; then make installcheck || exit 1; fi \
	&& if [ "${KNOT_RESOLVER_INTEGRATION_TESTS}"  = enabled ]; then make check-integration || exit 1; fi \
	&& file /usr/sbin/kresd && /usr/sbin/kresd --version \
	&& file /usr/sbin/kresc

# Download hBlock
ARG HBLOCK_TREEISH=v2.0.6
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
RUN mkdir -p /tmp/hblock/ && cd /tmp/hblock/ \
	&& git clone "${HBLOCK_REMOTE}" ./ \
	&& git checkout "${HBLOCK_TREEISH}" \
	&& git submodule update --init --recursive
RUN cd /tmp/hblock/ \
	&& make package-deb \
	&& dpkg -i ./dist/hblock-*.deb \
	&& /usr/bin/hblock --version

##################################################
## "hblock-resolver" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM CROSS_ARCH/ubuntu:18.04]], [[FROM ubuntu:18.04]]) AS hblock-resolver
m4_ifdef([[CROSS_QEMU]], [[COPY --from=qemu-user-static CROSS_QEMU CROSS_QEMU]])

# Environment
ENV KRESD_NIC=
ENV KRESD_VERBOSE=false
ENV KRESD_CERT_MODE=self-signed
ENV KRESD_CERT_CRT_FILE=/var/lib/knot-resolver/ssl/server.crt
ENV KRESD_CERT_KEY_FILE=/var/lib/knot-resolver/ssl/server.key

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		diffutils \
		dns-root-data \
		gzip \
		libcap2-bin \
		libedit2 \
		libgcc1 \
		libgeoip1 \
		libgnutls30 \
		libidn2-0 \
		libjansson4 \
		liblmdb0 \
		libssl1.1 \
		libstdc++6 \
		libsystemd0 \
		libunistring2 \
		liburcu6 \
		libuv1 \
		luajit \
		openssl \
		runit \
		tzdata \
	&& rm -rf /var/lib/apt/lists/*

# Copy Tini build
m4_define([[TINI_IMAGE_TAG]], m4_ifdef([[CROSS_ARCH]], [[v4-CROSS_ARCH]], [[v4]]))m4_dnl
COPY --from=hectormolinero/tini:TINI_IMAGE_TAG --chown=root:root /usr/bin/tini /usr/bin/tini

# Copy Supercronic build
m4_define([[SUPERCRONIC_IMAGE_TAG]], m4_ifdef([[CROSS_ARCH]], [[v6-CROSS_ARCH]], [[v6]]))m4_dnl
COPY --from=hectormolinero/supercronic:SUPERCRONIC_IMAGE_TAG --chown=root:root /usr/bin/supercronic /usr/bin/supercronic

# Copy LuaRocks packages
COPY --from=build-main --chown=root:root /usr/local/lib/lua/ /usr/local/lib/lua/
COPY --from=build-main --chown=root:root /usr/local/share/lua/ /usr/local/share/lua/

# Install Knot DNS from package
COPY --from=build-main --chown=root:root /tmp/knot-dns/knot-dns_*.deb /tmp/
RUN dpkg -i /tmp/knot-dns_*.deb && rm /tmp/knot-dns_*.deb

# Install Knot Resolver from package
COPY --from=build-main --chown=root:root /tmp/knot-resolver/knot-resolver_*.deb /tmp/
RUN dpkg -i /tmp/knot-resolver_*.deb && rm /tmp/knot-resolver_*.deb

# Install hBlock from package
COPY --from=build-main --chown=root:root /tmp/hblock/dist/hblock-*.deb /tmp/
RUN dpkg -i /tmp/hblock-*.deb && rm /tmp/hblock-*.deb

# Add capabilities to the kresd binary
RUN setcap cap_net_bind_service=+ep /usr/sbin/kresd

# Create users and groups
ARG KNOT_RESOLVER_USER_UID=1000
ARG KNOT_RESOLVER_USER_GID=1000
RUN groupadd \
		--gid "${KNOT_RESOLVER_USER_GID}" \
		knot-resolver
RUN useradd \
		--uid "${KNOT_RESOLVER_USER_UID}" \
		--gid "${KNOT_RESOLVER_USER_GID}" \
		--shell="$(which bash)" \
		--home-dir /home/knot-resolver/ \
		--create-home \
		knot-resolver

# Create data directory
RUN mkdir /var/lib/knot-resolver/ && chown knot-resolver:knot-resolver /var/lib/knot-resolver/
WORKDIR /var/lib/knot-resolver/

# Copy kresd config
COPY --chown=root:root config/knot-resolver/ /etc/knot-resolver/

# Copy hBlock config
COPY --chown=root:root config/hblock.d/ /etc/hblock.d/

# Copy crontab
COPY --chown=root:root config/crontab /etc/crontab

# Copy scripts
COPY --chown=root:root scripts/bin/ /usr/local/bin/

# Copy services
COPY --chown=knot-resolver:knot-resolver scripts/service/ /home/knot-resolver/service/

# Drop root privileges
USER knot-resolver:knot-resolver

# DNS
EXPOSE 53/tcp 53/udp
# DNS over TLS
EXPOSE 853/tcp
# HTTPS interface
EXPOSE 8053/tcp

HEALTHCHECK --start-period=60s --interval=30s --timeout=5s --retries=3 CMD /usr/local/bin/docker-healthcheck-cmd

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/docker-foreground-cmd"]
