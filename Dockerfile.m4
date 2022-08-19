m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:22.04]], [[FROM docker.io/ubuntu:22.04]]) AS build
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectorm/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		autoconf \
		automake \
		build-essential \
		ca-certificates \
		curl \
		dns-root-data \
		file \
		gawk \
		git \
		libaugeas-dev \
		libcap-ng-dev \
		libcmocka-dev \
		libedit-dev \
		libffi-dev \
		libgeoip-dev \
		libgnutls28-dev \
		libidn2-dev \
		libjansson-dev \
		liblmdb-dev \
		libnghttp2-dev \
		libpsl-dev \
		libssl-dev \
		libsystemd-dev \
		libtool \
		libunistring-dev \
		liburcu-dev \
		libuv1-dev \
		meson \
		ninja-build \
		pkgconf \
		tzdata \
		unzip \
	&& rm -rf /var/lib/apt/lists/*

# Build Knot DNS (only libknot and utilities)
ARG KNOT_DNS_TREEISH=v3.1.9
ARG KNOT_DNS_REMOTE=https://gitlab.nic.cz/knot/knot-dns.git
RUN mkdir /tmp/knot-dns/
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

# Build LuaJIT
ARG LUAJIT_TREEISH=03080b795aa3496ed62d4a0697c9f4767e7ca7e5
ARG LUAJIT_REMOTE=https://github.com/LuaJIT/LuaJIT.git
RUN mkdir /tmp/luajit/
WORKDIR /tmp/luajit/
RUN git clone "${LUAJIT_REMOTE:?}" ./
RUN git checkout "${LUAJIT_TREEISH:?}"
RUN git submodule update --init --recursive
RUN [ "$(getconf LONG_BIT)" != 32 ] || XCFLAGS='-DLUAJIT_USE_SYSMALLOC'; \
	make -j"$(nproc)" amalg XCFLAGS="${XCFLAGS-}"
RUN make install PREFIX=/usr INSTALL_TNAME=luajit
RUN file /usr/bin/luajit
RUN luajit -v

# Build LuaRocks
ARG LUAROCKS_TREEISH=v3.9.1
ARG LUAROCKS_REMOTE=https://github.com/luarocks/luarocks.git
RUN mkdir /tmp/luarocks/
WORKDIR /tmp/luarocks/
RUN git clone "${LUAROCKS_REMOTE:?}" ./
RUN git checkout "${LUAROCKS_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--rocks-tree=/usr/local \
		--lua-version=5.1 \
		--with-lua=/usr \
		--with-lua-bin=/usr/bin \
		--with-lua-lib=/usr/lib \
		--with-lua-include=/usr/include/luajit-2.1 \
		--with-lua-interpreter=luajit
RUN make build -j"$(nproc)"
RUN make install
RUN file /usr/bin/luarocks
RUN luarocks --version

# Install LuaRocks packages
RUN mkdir /tmp/rocks/
WORKDIR /tmp/rocks/
RUN luarocks init --lua-versions=5.1 metapackage
RUN ROCKS=$(printf '["%s"]="%s",' \
		basexx        0.4.1-1 \
		binaryheap    0.4-1 \
		bit32         5.3.5.1-1 \
		compat53      0.8-1 \
		cqueues       20200726.51-0 \
		fifo          0.2-0 \
		http          0.4-0 \
		lpeg          1.0.2-1 \
		lpeg_patterns 0.5-0 \
		lua           5.1-1 \
		lua-lru       1.0-1 \
		luafilesystem 1.8.0-1 \
		luaossl       20220711-0 \
		mmdblua       0.2-0 \
		psl           0.3-0 \
	) \
	&& printf 'return {dependencies = {%s}}' "${ROCKS:?}" > ./luarocks.lock \
	&& HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH) \
	&& LIBDIRS="${LIBDIRS-} CRYPTO_LIBDIR=/usr/lib/${HOST_MULTIARCH:?}" \
	&& LIBDIRS="${LIBDIRS-} OPENSSL_LIBDIR=/usr/lib/${HOST_MULTIARCH:?}" \
	&& luarocks install --tree=system --only-deps ./*.rockspec ${LIBDIRS:?}

# Build Knot Resolver
ARG KNOT_RESOLVER_TREEISH=v5.5.2
ARG KNOT_RESOLVER_REMOTE=https://gitlab.nic.cz/knot/knot-resolver.git
RUN mkdir /tmp/knot-resolver/
WORKDIR /tmp/knot-resolver/
RUN git clone "${KNOT_RESOLVER_REMOTE:?}" ./
RUN git checkout "${KNOT_RESOLVER_TREEISH:?}"
RUN git submodule update --init --recursive
RUN meson ./build/ \
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
		-D unit_tests=enabled \
		-D config_tests=enabled \
		-D extra_tests=disabled
RUN ninja -C ./build/
RUN ninja -C ./build/ install
RUN meson test -C ./build/ --print-errorlogs --suite unit --suite config --no-suite snowflake
RUN file /usr/sbin/kresd
RUN file /usr/sbin/kresc
RUN /usr/sbin/kresd --version

# Download hBlock
ARG HBLOCK_TREEISH=v3.4.0
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
RUN mkdir /tmp/hblock/
WORKDIR /tmp/hblock/
RUN git clone "${HBLOCK_REMOTE:?}" ./
RUN git checkout "${HBLOCK_TREEISH:?}"
RUN git submodule update --init --recursive
RUN make install prefix=/usr
RUN /usr/bin/hblock --version

##################################################
## "base" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:22.04]], [[FROM docker.io/ubuntu:22.04]]) AS base
m4_ifdef([[CROSS_QEMU]], [[COPY --from=docker.io/hectorm/qemu-user-static:latest CROSS_QEMU CROSS_QEMU]])

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		catatonit \
		curl \
		dns-root-data \
		gzip \
		libcap-ng0 \
		libcap2-bin \
		libedit2 \
		libgcc1 \
		libgeoip1 \
		libgnutls30 \
		libidn2-0 \
		libjansson4 \
		liblmdb0 \
		libnghttp2-14 \
		libpsl5 \
		libssl3 \
		libstdc++6 \
		libsystemd0 \
		libunistring2 \
		liburcu8 \
		libuv1 \
		netcat-openbsd \
		openssl \
		rlwrap \
		runit \
		snooze \
		tzdata \
	&& apt-get clean \
	&& rm -rf \
		/var/lib/apt/lists/* \
		/var/cache/ldconfig/aux-cache \
		/var/log/apt/* \
		/var/log/alternatives.log \
		/var/log/bootstrap.log \
		/var/log/dpkg.log

# Environment
ENV SVDIR=/service/
ENV KRESD_UID=1000
ENV KRESD_CONF_DIR=/etc/knot-resolver/
ENV KRESD_DATA_DIR=/var/lib/knot-resolver/
ENV KRESD_CACHE_DIR=/var/cache/knot-resolver/
ENV KRESD_CACHE_SIZE=50
ENV KRESD_DNS1_IP=1.1.1.1@853
ENV KRESD_DNS1_HOSTNAME=cloudflare-dns.com
ENV KRESD_DNS2_IP=1.0.0.1@853
ENV KRESD_DNS2_HOSTNAME=cloudflare-dns.com
ENV KRESD_INSTANCE_NUMBER=1
ENV KRESD_RECENTLY_BLOCKED_NUMBER=100
ENV KRESD_CERT_MANAGED=true
ENV KRESD_NIC=
ENV KRESD_LOG_LEVEL=notice

# Create unprivileged user
RUN useradd -u "${KRESD_UID:?}" -g 0 -s "$(command -v bash)" -Md "${KRESD_CACHE_DIR:?}" knot-resolver

# Copy LuaJIT build
COPY --from=build --chown=root:root /usr/lib/libluajit-* /usr/lib/

# Copy Lua packages
COPY --from=build --chown=root:root /usr/local/lib/lua/ /usr/local/lib/lua/
COPY --from=build --chown=root:root /usr/local/share/lua/ /usr/local/share/lua/

# Copy Knot DNS build
COPY --from=build --chown=root:root /usr/lib/libdnssec.* /usr/lib/
COPY --from=build --chown=root:root /usr/lib/libknot.* /usr/lib/
COPY --from=build --chown=root:root /usr/lib/libzscanner.* /usr/lib/
COPY --from=build --chown=root:root /usr/bin/kdig /usr/bin/kdig
COPY --from=build --chown=root:root /usr/bin/khost /usr/bin/khost

# Copy Knot Resolver build
COPY --from=build --chown=root:root /usr/lib/libkres.* /usr/lib/
COPY --from=build --chown=root:root /usr/lib/knot-resolver/ /usr/lib/knot-resolver/
COPY --from=build --chown=root:root /usr/sbin/kresd /usr/sbin/kresd
COPY --from=build --chown=root:root /usr/sbin/kresc /usr/sbin/kresc
COPY --from=build --chown=root:root /usr/sbin/kres-cache-gc /usr/sbin/kres-cache-gc

# Copy hBlock build
COPY --from=build --chown=root:root /usr/bin/hblock /usr/bin/hblock

# Add capabilities to the kresd binary
m4_ifdef([[CROSS_QEMU]], [[RUN setcap cap_net_bind_service=+ep CROSS_QEMU]])
RUN setcap cap_net_bind_service=+ep /usr/sbin/kresd

# Create data and cache directories
RUN mkdir "${KRESD_DATA_DIR:?}" "${KRESD_CACHE_DIR:?}"
RUN chown knot-resolver:root "${KRESD_DATA_DIR:?}" "${KRESD_CACHE_DIR:?}"
RUN chmod 0775 "${KRESD_DATA_DIR:?}" "${KRESD_CACHE_DIR:?}"

# Copy kresd config
COPY --chown=root:root ./config/knot-resolver/ /etc/knot-resolver/
RUN find /etc/knot-resolver/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
RUN find /etc/knot-resolver/ -type f -not -perm 0644 -exec chmod 0644 '{}' ';'

# Copy hBlock config
COPY --chown=root:root ./config/hblock/ /etc/hblock/
RUN find /etc/hblock/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
RUN find /etc/hblock/ -type f -not -perm 0644 -exec chmod 0644 '{}' ';'

# Copy scripts
COPY --chown=root:root ./scripts/bin/ /usr/local/bin/
RUN find /usr/local/bin/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
RUN find /usr/local/bin/ -type f -not -perm 0755 -exec chmod 0755 '{}' ';'

# Copy services
COPY --chown=root:root ./scripts/service/ /service/
RUN find /service/ -type d -not -perm 0775 -exec chmod 0775 '{}' ';'
RUN find /service/ -type f -not -perm 0775 -exec chmod 0775 '{}' ';'

# Drop root privileges
USER knot-resolver:root

# DNS endpoint
EXPOSE 53/udp 53/tcp
# DNS-over-HTTPS endpoint
EXPOSE 443/tcp
# DNS-over-TLS endpoint
EXPOSE 853/tcp
# Web management endpoint
EXPOSE 8453/tcp

HEALTHCHECK --start-period=30s --interval=10s --timeout=5s --retries=1 CMD ["/usr/local/bin/container-healthcheck"]
ENTRYPOINT ["/usr/local/bin/container-init"]

##################################################
## "test" stage
##################################################

FROM base AS test

# Perform a test run
RUN printf '%s\n' 'Starting services...' \
	&& export KRESD_INSTANCE_NUMBER=2 \
	&& (nohup container-init &) \
	&& TIMEOUT_DURATION=240s \
	&& TIMEOUT_COMMAND='until container-healthcheck; do sleep 1; done' \
	&& timeout "${TIMEOUT_DURATION:?}" sh -euc "${TIMEOUT_COMMAND:?}"

##################################################
## "main" stage
##################################################

FROM base AS main

# Dummy instruction so BuildKit does not skip the test stage
RUN --mount=type=bind,from=test,source=/mnt/,target=/mnt/
