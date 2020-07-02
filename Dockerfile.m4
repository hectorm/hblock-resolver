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
		libpsl-dev \
		libssl-dev \
		libsystemd-dev \
		libtool \
		libunistring-dev \
		liburcu-dev \
		libuv1-dev \
		ninja-build \
		pkgconf \
		python3 \
		python3-dev \
		python3-pip \
		python3-setuptools \
		python3-wheel \
		tzdata \
		unzip

# Install Python packages
RUN pip3 install --no-cache-dir meson

# Build Knot DNS (only libknot and utilities)
ARG KNOT_DNS_TREEISH=v2.9.5
ARG KNOT_DNS_REMOTE=https://gitlab.labs.nic.cz/knot/knot-dns.git
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

# Build Moonjit
ARG MOONJIT_TREEISH=2.1.2
ARG MOONJIT_REMOTE=https://github.com/moonjit/moonjit.git
RUN mkdir /tmp/moonjit/
WORKDIR /tmp/moonjit/
RUN git clone "${MOONJIT_REMOTE:?}" ./
RUN git checkout "${MOONJIT_TREEISH:?}"
RUN git submodule update --init --recursive
RUN ARCH=$(uname -m); \
	LUAJIT_XCFLAGS=''; \
	if [ "${ARCH:?}" = 'x86_64' ]; then \
		LUAJIT_XCFLAGS="${LUAJIT_XCFLAGS-} -DLUAJIT_ENABLE_GC64"; \
	elif [ "${ARCH:?}" = 'armv7l' ]; then \
		LUAJIT_XCFLAGS="${LUAJIT_XCFLAGS-} -DLUAJIT_USE_SYSMALLOC"; \
	fi; \
	make -j"$(nproc)" amalg XCFLAGS="${LUAJIT_XCFLAGS?}"
RUN make install PREFIX=/usr INSTALL_TNAME=luajit
RUN file /usr/bin/luajit
RUN luajit -v

# Build LuaRocks
ARG LUAROCKS_TREEISH=v3.3.1
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
RUN ROCKS=$(printf '%s="%s",' \
		basexx        0.4.1-1 \
		binaryheap    0.4-1 \
		bit32         5.3.0-1 \
		compat53      0.7-1 \
		cqueues       20200603.51-0 \
		fifo          0.2-0 \
		#http         0.3-0 \
		lpeg          1.0.2-1 \
		lpeg_patterns 0.5-0 \
		lua           5.1-1 \
		luafilesystem 1.8.0-1 \
		luaossl       20190731-0 \
		mmdblua       0.2-0 \
		psl           0.3-0 \
	) \
	&& printf 'return {dependencies = {%s}}' "${ROCKS:?}" > ./luarocks.lock \
	&& HOST_MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH) \
	&& LIBDIRS="${LIBDIRS-} CRYPTO_LIBDIR=/usr/lib/${HOST_MULTIARCH:?}" \
	&& LIBDIRS="${LIBDIRS-} OPENSSL_LIBDIR=/usr/lib/${HOST_MULTIARCH:?}" \
	&& luarocks install --tree=system --only-deps ./*.rockspec ${LIBDIRS:?}

# Install lua-http (master branch fixes #145)
ARG LUA_HTTP_TREEISH=47225d081318e65d5d832e2dd99ff0880d56b5c6
ARG LUA_HTTP_ROCKSPEC=https://raw.githubusercontent.com/daurnimator/lua-http/${LUA_HTTP_TREEISH}/http-scm-0.rockspec
RUN luarocks install --tree=system --deps-mode=none "${LUA_HTTP_ROCKSPEC:?}"

# Build Knot Resolver
ARG KNOT_RESOLVER_TREEISH=v5.1.2
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_UNIT_TESTS=enabled
ARG KNOT_RESOLVER_CONFIG_TESTS=disabled
ARG KNOT_RESOLVER_EXTRA_TESTS=disabled
RUN mkdir /tmp/knot-resolver/
WORKDIR /tmp/knot-resolver/
RUN git clone "${KNOT_RESOLVER_REMOTE:?}" ./
RUN git checkout "${KNOT_RESOLVER_TREEISH:?}"
RUN git submodule update --init --recursive
RUN pip3 install --user -r ./tests/pytests/requirements.txt
RUN pip3 install --user -r ./tests/integration/deckard/requirements.txt
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
		-D unit_tests="${KNOT_RESOLVER_UNIT_TESTS:?}" \
		-D config_tests="${KNOT_RESOLVER_CONFIG_TESTS:?}" \
		-D extra_tests="${KNOT_RESOLVER_EXTRA_TESTS:?}"
RUN ninja -C ./build/
RUN ninja -C ./build/ install
RUN ARGS='--timeout-multiplier=4 --print-errorlogs'; \
	[ "${KNOT_RESOLVER_UNIT_TESTS:?}"   = enabled ] && ARGS="${ARGS:?} --suite unit"; \
	[ "${KNOT_RESOLVER_CONFIG_TESTS:?}" = enabled ] && ARGS="${ARGS:?} --suite config"; \
	[ "${KNOT_RESOLVER_EXTRA_TESTS:?}"  = enabled ] && ARGS="${ARGS:?} --suite pytests --suite integration"; \
	meson test -C ./build/ ${ARGS:?}
RUN file /usr/sbin/kresd
RUN file /usr/sbin/kresc
RUN /usr/sbin/kresd --version

# Download hBlock
ARG HBLOCK_TREEISH=v2.1.6
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
RUN mkdir /tmp/hblock/
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

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
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
		libpsl5 \
		libssl1.1 \
		libstdc++6 \
		libsystemd0 \
		libunistring2 \
		liburcu6 \
		libuv1 \
		openssl \
		runit \
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
ENV KRESD_DNS1_IP=1.1.1.1@853
ENV KRESD_DNS1_HOSTNAME=cloudflare-dns.com
ENV KRESD_DNS2_IP=1.0.0.1@853
ENV KRESD_DNS2_HOSTNAME=cloudflare-dns.com
ENV KRESD_WATCHDOG_QNAME=cloudflare.com.
ENV KRESD_WATCHDOG_QTYPE=A
ENV KRESD_WATCHDOG_INTERVAL=10000
ENV KRESD_CERT_MANAGED=true
ENV KRESD_CERT_CRT_FILE=/var/lib/knot-resolver/ssl/server.crt
ENV KRESD_CERT_KEY_FILE=/var/lib/knot-resolver/ssl/server.key
ENV KRESD_BLACKLIST_RPZ_FILE=/var/lib/knot-resolver/hblock.rpz
ENV KRESD_NIC=
ENV KRESD_VERBOSE=false

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

# Copy Moonjit build
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
RUN mkdir /var/lib/knot-resolver/ /var/cache/knot-resolver/
RUN chown knot-resolver:knot-resolver /var/lib/knot-resolver/ /var/cache/knot-resolver/

# Copy kresd config
COPY --chown=root:root ./config/knot-resolver/ /etc/knot-resolver/

# Copy hBlock config
COPY --chown=root:root ./config/hblock.d/ /etc/hblock.d/

# Copy crontab
COPY --chown=root:root ./config/crontab /etc/crontab

# Copy scripts
COPY --chown=root:root ./scripts/bin/ /usr/local/bin/

# Copy services
COPY --chown=knot-resolver:knot-resolver ./scripts/service/ /home/knot-resolver/service/

# Drop root privileges
USER knot-resolver:knot-resolver

##################################################
## "test" stage
##################################################

FROM base AS test

# Perform a test run
RUN printf '%s\n' 'Starting services...' \
	&& (nohup container-foreground-cmd &) \
	&& TIMEOUT_DURATION=240s \
	&& TIMEOUT_COMMAND='until container-healthcheck-cmd; do sleep 1; done' \
	&& timeout "${TIMEOUT_DURATION:?}" sh -eu -c "${TIMEOUT_COMMAND:?}"

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

HEALTHCHECK --start-period=30s --interval=10s --timeout=5s --retries=1 \
CMD ["/usr/local/bin/container-healthcheck-cmd"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/container-foreground-cmd"]
