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
		gawk \
		git \
		libaugeas0 \
		libcap-ng-dev \
		libcmocka-dev \
		libedit-dev \
		libffi-dev \
		libfstrm-dev \
		libgeoip-dev \
		libgnutls28-dev \
		libidn2-dev \
		libjansson-dev \
		liblmdb-dev \
		libluajit-5.1-dev \
		libprotobuf-c-dev \
		libprotobuf-dev \
		libssl-dev \
		libtool \
		liburcu-dev \
		libuv1-dev \
		luajit \
		luarocks \
		pkg-config \
		protobuf-c-compiler \
		python3 \
		python3-dev \
		python3-pip \
		python3-setuptools \
		python3-wheel \
		xxd

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
		OPENSSL_LIBDIR="/usr/lib/${HOST_MULTIARCH}" \
		CRYPTO_LIBDIR="/usr/lib/${HOST_MULTIARCH}"

# Build Knot DNS (only libknot and utilities)
ARG KNOT_DNS_TREEISH=v2.7.5
ARG KNOT_DNS_REMOTE=https://gitlab.labs.nic.cz/knot/knot-dns.git
RUN mkdir -p /tmp/knot-dns/ && cd /tmp/knot-dns/ \
	&& git clone --recursive "${KNOT_DNS_REMOTE}" ./ \
	&& git checkout "${KNOT_DNS_TREEISH}"
RUN cd /tmp/knot-dns/ \
	&& ./autogen.sh \
	&& ./configure \
		--prefix=/usr \
		--disable-daemon \
		--disable-modules \
		--disable-documentation \
		--enable-fastparser \
		--enable-dnstap \
		--enable-utilities \
	&& make -j"$(nproc)" \
	&& checkinstall --default \
		--pkgname=knot-dns \
		--pkgversion=0 --pkgrelease=0 \
		--exclude=/usr/include/,/usr/lib/pkgconfig/,/usr/share/man/ \
		--nodoc \
		make install \
	&& /usr/bin/kdig --version \
	&& /usr/bin/khost --version

# Build Knot Resolver
ARG KNOT_RESOLVER_TREEISH=v3.2.1
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_SKIP_INSTALLATION_CHECK=false
ARG KNOT_RESOLVER_SKIP_INTEGRATION_CHECK=false
RUN mkdir -p /tmp/knot-resolver/ && cd /tmp/knot-resolver/ \
	&& git clone --recursive "${KNOT_RESOLVER_REMOTE}" ./ \
	&& git checkout "${KNOT_RESOLVER_TREEISH}" \
	&& pip3 install --user -r tests/deckard/requirements.txt
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
		--exclude=/usr/include/,/usr/lib/pkgconfig/,/usr/share/man/ \
		--nodoc \
		make install \
	&& if [ "${KNOT_RESOLVER_SKIP_INSTALLATION_CHECK}" != true ]; then \
		make installcheck || exit 1; \
	fi \
	&& if [ "${KNOT_RESOLVER_SKIP_INTEGRATION_CHECK}" != true ]; then \
		make check-integration || exit 1; \
	fi \
	&& /usr/sbin/kresd --version

# Download hBlock
ARG HBLOCK_TREEISH=v2.0.2
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
RUN mkdir -p /tmp/hblock/ && cd /tmp/hblock/ \
	&& git clone --recursive "${HBLOCK_REMOTE}" ./ \
	&& git checkout "${HBLOCK_TREEISH}"
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
ENV KRESD_CERT_MODE=self-signed

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		diffutils \
		dns-root-data \
		gzip \
		libcap-ng0 \
		libcap2-bin \
		libedit2 \
		libfstrm0 \
		libgcc1 \
		libgeoip1 \
		libgnutls30 \
		libidn2-0 \
		libjansson4 \
		liblmdb0 \
		libprotobuf-c1 \
		libprotobuf10 \
		libssl1.1 \
		libstdc++6 \
		liburcu6 \
		libuv1 \
		luajit \
		openssl \
		runit \
	&& rm -rf /var/lib/apt/lists/*

# Copy Tini build
m4_define([[TINI_IMAGE_TAG]], m4_ifdef([[CROSS_ARCH]], [[v1-CROSS_ARCH]], [[v1]]))m4_dnl
COPY --from=hectormolinero/tini:TINI_IMAGE_TAG --chown=root:root /usr/bin/tini /usr/bin/tini

# Copy Supercronic build
m4_define([[SUPERCRONIC_IMAGE_TAG]], m4_ifdef([[CROSS_ARCH]], [[v1-CROSS_ARCH]], [[v1]]))m4_dnl
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
RUN groupadd --system --gid 999 knot-resolver \
	&& useradd --system --uid 999 --gid 999 \
		--create-home --home-dir /home/knot-resolver/ \
		--shell="$(which bash)" \
		knot-resolver

# Create data directory
RUN mkdir /var/lib/knot-resolver/ \
	&& chown knot-resolver:knot-resolver /var/lib/knot-resolver/

# Copy kresd config
COPY --chown=root:root config/knot-resolver/ /etc/knot-resolver/

# Copy hBlock config
COPY --chown=root:root config/hblock.d/ /etc/hblock.d/

# Copy services
COPY --chown=knot-resolver:knot-resolver scripts/service/ /home/knot-resolver/service/

# Copy crontab
COPY --chown=root:root config/crontab /etc/crontab

# Copy scripts
COPY --chown=root:root scripts/bin/ /usr/local/bin/

# Drop root privileges
USER knot-resolver:knot-resolver

# Expose ports
## DNS
EXPOSE 53/tcp 53/udp
## DNS over TLS
EXPOSE 853/tcp
## HTTPS interface
EXPOSE 8053/tcp

# Don't declare volumes, let the user decide
#VOLUME /var/lib/knot-resolver/

WORKDIR /var/lib/knot-resolver/

HEALTHCHECK --start-period=60s --interval=30s --timeout=5s --retries=3 \
	CMD /usr/local/bin/docker-healthcheck-cmd

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/docker-foreground-cmd"]
