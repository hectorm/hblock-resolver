m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:18.04]], [[FROM docker.io/ubuntu:18.04]]) AS build
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		autoconf \
		automake \
		build-essential \
		ca-certificates \
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
		ninja-build \
		pkgconf \
		python3 \
		python3-dev \
		python3-pip \
		python3-setuptools \
		python3-wheel \
		tzdata \
		xxd \
	&& rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --no-cache-dir meson

# Install LuaRocks packages
RUN HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH) \
	&& LIBDIRS="${LIBDIRS-} CRYPTO_LIBDIR=/usr/lib/${HOST_MULTIARCH:?}" \
	&& LIBDIRS="${LIBDIRS-} OPENSSL_LIBDIR=/usr/lib/${HOST_MULTIARCH:?}" \
	&& luarocks install basexx ${LIBDIRS:?} \
	&& luarocks install cqueues ${LIBDIRS:?} \
	# Master branch fixes issue #145 (TODO: return to a stable version)
	&& LUA_HTTP_TREEISH=47225d081318e65d5d832e2dd99ff0880d56b5c6 \
	&& LUA_HTTP_ROCKSPEC=https://raw.githubusercontent.com/daurnimator/lua-http/${LUA_HTTP_TREEISH:?}/http-scm-0.rockspec \
	&& luarocks install "${LUA_HTTP_ROCKSPEC:?}" ${LIBDIRS:?} \
	&& luarocks install luafilesystem ${LIBDIRS:?} \
	&& luarocks install luasec ${LIBDIRS:?} \
	&& luarocks install luasocket ${LIBDIRS:?} \
	&& luarocks install mmdblua ${LIBDIRS:?} \
	&& rm -rf "${HOME:?}"/.cache/luarocks/

# Build Knot DNS (only libknot and utilities)
ARG KNOT_DNS_TREEISH=v2.8.4
ARG KNOT_DNS_REMOTE=https://gitlab.labs.nic.cz/knot/knot-dns.git
WORKDIR /tmp/knot-dns/
RUN git clone "${KNOT_DNS_REMOTE:?}" ./
RUN git checkout "${KNOT_DNS_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./autogen.sh
RUN ./configure \
		--prefix=/usr \
		--enable-utilities \
		--enable-fastparser \
		--disable-daemon \
		--disable-modules \
		--disable-dnstap \
		--disable-documentation
RUN make -j"$(nproc)"
RUN make install
RUN file /usr/bin/kdig
RUN file /usr/bin/khost
RUN /usr/bin/kdig --version
RUN /usr/bin/khost --version

# Build Knot Resolver
ARG KNOT_RESOLVER_TREEISH=v4.2.2
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_UNIT_TESTS=enabled
ARG KNOT_RESOLVER_CONFIG_TESTS=disabled
ARG KNOT_RESOLVER_EXTRA_TESTS=disabled
WORKDIR /tmp/knot-resolver/
RUN git clone "${KNOT_RESOLVER_REMOTE:?}" ./
RUN git checkout "${KNOT_RESOLVER_TREEISH:?}"
RUN git submodule update --init --recursive
RUN pip3 install --user -r ./tests/pytests/requirements.txt
RUN pip3 install --user -r ./tests/integration/deckard/requirements.txt
RUN meson ./build \
		--prefix=/usr \
		--libdir=/usr/lib \
		--sysconfdir=/etc \
		--buildtype=release \
		-D client=enabled \
		-D dnstap=disabled \
		-D doc=disabled \
		-D managed_ta=disabled \
		-D root_hints=/usr/share/dns/root.hints \
		-D keyfile_default=/usr/share/dns/root.key \
		-D unit_tests="${KNOT_RESOLVER_UNIT_TESTS:?}" \
		-D config_tests="${KNOT_RESOLVER_CONFIG_TESTS:?}" \
		-D extra_tests="${KNOT_RESOLVER_EXTRA_TESTS:?}"
RUN ninja -C ./build
RUN ninja -C ./build install
RUN ARGS='--timeout-multiplier=4 --print-errorlogs'; \
	[ "${KNOT_RESOLVER_UNIT_TESTS:?}"   = enabled ] && ARGS="${ARGS:?} --suite unit"; \
	[ "${KNOT_RESOLVER_CONFIG_TESTS:?}" = enabled ] && ARGS="${ARGS:?} --suite config"; \
	[ "${KNOT_RESOLVER_EXTRA_TESTS:?}"  = enabled ] && ARGS="${ARGS:?} --suite pytests --suite integration"; \
	meson test -C ./build ${ARGS:?}
RUN file /usr/sbin/kresd
RUN file /usr/sbin/kresc
RUN /usr/sbin/kresd --version

# Download hBlock
ARG HBLOCK_TREEISH=v2.1.2
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
WORKDIR /tmp/hblock/
RUN git clone "${HBLOCK_REMOTE:?}" ./
RUN git checkout "${HBLOCK_TREEISH:?}"
RUN git submodule update --init --recursive
RUN make install PREFIX=/usr
RUN /usr/bin/hblock --version

##################################################
## "base" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:18.04]], [[FROM docker.io/ubuntu:18.04]]) AS base
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectormolinero/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Environment
ENV KRESD_NIC=
ENV KRESD_VERBOSE=false
ENV KRESD_CERT_MANAGED=true
ENV KRESD_CERT_CRT_FILE=/var/lib/knot-resolver/ssl/server.crt
ENV KRESD_CERT_KEY_FILE=/var/lib/knot-resolver/ssl/server.key
ENV KRESD_BLACKLIST_RPZ_FILE=/var/lib/knot-resolver/hblock.rpz

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

# Create users and groups
ARG KNOT_RESOLVER_USER_UID=1000
ARG KNOT_RESOLVER_USER_GID=1000
RUN groupadd \
		--gid "${KNOT_RESOLVER_USER_GID:?}" \
		knot-resolver
RUN useradd \
		--uid "${KNOT_RESOLVER_USER_UID:?}" \
		--gid "${KNOT_RESOLVER_USER_GID:?}" \
		--shell "$(command -v bash)" \
		--home-dir /home/knot-resolver/ \
		--create-home \
		knot-resolver

# Copy Tini build
m4_define([[TINI_IMAGE_TAG]], m4_ifdef([[CROSS_ARCH]], [[latest-CROSS_ARCH]], [[latest]]))m4_dnl
COPY --from=docker.io/hectormolinero/tini:TINI_IMAGE_TAG --chown=root:root /usr/bin/tini /usr/bin/tini

# Copy Supercronic build
m4_define([[SUPERCRONIC_IMAGE_TAG]], m4_ifdef([[CROSS_ARCH]], [[latest-CROSS_ARCH]], [[latest]]))m4_dnl
COPY --from=docker.io/hectormolinero/supercronic:SUPERCRONIC_IMAGE_TAG --chown=root:root /usr/bin/supercronic /usr/bin/supercronic

# Copy LuaRocks packages
COPY --from=build --chown=root:root /usr/local/lib/lua/ /usr/local/lib/lua/
COPY --from=build --chown=root:root /usr/local/share/lua/ /usr/local/share/lua/

# Copy Knot DNS installation
COPY --from=build --chown=root:root /usr/lib/libdnssec.* /usr/lib/
COPY --from=build --chown=root:root /usr/lib/libknot.* /usr/lib/
COPY --from=build --chown=root:root /usr/lib/libzscanner.* /usr/lib/
COPY --from=build --chown=root:root /usr/bin/kdig /usr/bin/kdig
COPY --from=build --chown=root:root /usr/bin/khost /usr/bin/khost

# Copy Knot Resolver installation
COPY --from=build --chown=root:root /usr/lib/libkres.* /usr/lib/
COPY --from=build --chown=root:root /usr/lib/knot-resolver/ /usr/lib/knot-resolver/
COPY --from=build --chown=root:root /usr/sbin/kresd /usr/sbin/kresd
COPY --from=build --chown=root:root /usr/sbin/kresc /usr/sbin/kresc
COPY --from=build --chown=root:root /usr/sbin/kres-cache-gc /usr/sbin/kres-cache-gc

# Copy hBlock installation
COPY --from=build --chown=root:root /usr/bin/hblock /usr/bin/hblock

# Add capabilities to the kresd binary
RUN setcap cap_net_bind_service=+ep /usr/sbin/kresd

# Create data directory
WORKDIR /var/lib/knot-resolver/
RUN chown knot-resolver:knot-resolver /var/lib/knot-resolver/

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

m4_ifdef([[CROSS_ARCH]], [[]], [[
##################################################
## "test" stage
##################################################

FROM base AS test

# Perform a test run
RUN printf '%s\n' 'Starting services...' \
	&& (nohup container-foreground-cmd &) \
	&& TIMEOUT_DURATION=120s \
	&& TIMEOUT_COMMAND='until container-healthcheck-cmd; do sleep 5; done' \
	&& timeout "${TIMEOUT_DURATION:?}" sh -eu -c "${TIMEOUT_COMMAND:?}"
]])

##################################################
## "main" stage
##################################################

FROM base AS main

# DNS over UDP & TCP
EXPOSE 53/udp 53/tcp
# DNS over HTTPS & TLS
EXPOSE 443/tcp 853/tcp
# Web interface
EXPOSE 8453/tcp

HEALTHCHECK --start-period=60s --interval=30s --timeout=5s --retries=3 \
CMD ["/usr/local/bin/container-healthcheck-cmd"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/container-foreground-cmd"]
