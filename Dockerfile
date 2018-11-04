FROM ubuntu:18.04 AS build-tini
###############################

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		build-essential \
		ca-certificates \
		cmake \
		git

# Build Tiny
ARG TINY_TREEISH=v0.18.0
ARG TINY_REMOTE=https://github.com/krallin/tini.git
RUN mkdir -p /tmp/tini/ && cd /tmp/tini/ \
	&& git clone --recursive "${TINY_REMOTE}" ./ \
	&& git checkout "${TINY_TREEISH}"
RUN cd /tmp/tini/ \
	&& export CFLAGS='-DPR_SET_CHILD_SUBREAPER=36 -DPR_GET_CHILD_SUBREAPER=37' \
	&& cmake . -DCMAKE_INSTALL_PREFIX=/usr \
	&& make -j$(nproc) \
	&& make install \
	&& /usr/bin/tini --version

FROM golang:1-stretch AS build-supercronic
##########################################

# Build dep
RUN go get -d github.com/golang/dep \
	&& cd "${GOPATH}/src/github.com/golang/dep" \
	&& DEP_LATEST=$(git describe --abbrev=0 --tags) \
	&& git checkout "${DEP_LATEST}"
RUN cd "${GOPATH}/src/github.com/golang/dep" \
	&& go install -ldflags="-X main.version=${DEP_LATEST}" ./cmd/dep \
	&& "${GOPATH}"/bin/dep version

# Build supercronic
ARG SUPERCRONIC_TREEISH=v0.1.6
ARG SUPERCRONIC_PACKAGE=github.com/aptible/supercronic
RUN go get -d "${SUPERCRONIC_PACKAGE}" \
	&& cd "${GOPATH}/src/${SUPERCRONIC_PACKAGE}" \
	&& git checkout "${SUPERCRONIC_TREEISH}" \
	&& dep ensure
RUN cd "${GOPATH}/src/${SUPERCRONIC_PACKAGE}" \
	&& go install \
	&& [ -x "${GOPATH}"/bin/supercronic ]

FROM ubuntu:18.04 AS build-knot-resolver
########################################

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

# Install luarocks packages
RUN HOST_MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" \
	&& printf '%s\n' \
		cqueues \
		http \
		luasec \
		luasocket \
		mmdblua \
	| xargs -n1 -iPKG luarocks install PKG \
		OPENSSL_LIBDIR="/usr/lib/${HOST_MULTIARCH}" \
		CRYPTO_LIBDIR="/usr/lib/${HOST_MULTIARCH}"

# Build Knot DNS (only libknot and utilities)
ARG KNOT_DNS_TREEISH=v2.7.3
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
	&& make -j$(nproc) \
	&& checkinstall --default \
		--pkgname=knot-dns \
		--pkgversion=0 --pkgrelease=0 \
		--exclude=/usr/include/,/usr/lib/pkgconfig/,/usr/share/man/ \
		--nodoc \
		make install \
	&& /usr/bin/kdig --version \
	&& /usr/bin/khost --version

# Build Knot Resolver
ARG KNOT_RESOLVER_TREEISH=v3.1.0
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_REQUIRE_INSTALLATION_CHECK=false
ARG KNOT_RESOLVER_REQUIRE_INTEGRATION_CHECK=false
RUN mkdir -p /tmp/knot-resolver/ && cd /tmp/knot-resolver/ \
	&& git clone --recursive "${KNOT_RESOLVER_REMOTE}" ./ \
	&& git checkout "${KNOT_RESOLVER_TREEISH}" \
	&& pip3 install --user -r tests/deckard/requirements.txt
RUN cd /tmp/knot-resolver/ \
	&& export \
		CFLAGS='-O2 -fstack-protector' \
		PREFIX=/usr \
		ETCDIR=/etc/knot-resolver \
		MODULEDIR=/usr/lib/knot-resolver \
		ROOTHINTS=/usr/share/dns/root.hints \
	&& make -j$(nproc) \
	&& make check \
	&& checkinstall --default \
		--pkgname=knot-resolver \
		--pkgversion=0 --pkgrelease=0 \
		--exclude=/usr/include/,/usr/lib/pkgconfig/,/usr/share/man/ \
		--nodoc \
		make install \
	&& if ! make installcheck; then \
		>&2 printf '%s\n' 'Installation check failed'; \
		if [ "${KNOT_RESOLVER_REQUIRE_INSTALLATION_CHECK}" = true ]; then \
			exit 1; \
		fi; \
	fi \
	&& if ! make check-integration; then \
		>&2 printf '%s\n' 'Integration check failed'; \
		if [ "${KNOT_RESOLVER_REQUIRE_INTEGRATION_CHECK}" = true ]; then \
			exit 1; \
		fi; \
	fi \
	&& /usr/sbin/kresd --version

# Download hBlock
ARG HBLOCK_TREEISH=v1.6.9
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
RUN mkdir -p /tmp/hblock/ && cd /tmp/hblock/ \
	&& git clone --recursive "${HBLOCK_REMOTE}" ./ \
	&& git checkout "${HBLOCK_TREEISH}"
RUN cd /tmp/hblock/ \
	&& install -m 0755 ./hblock /usr/bin/hblock \
	&& /usr/bin/hblock --version

FROM ubuntu:18.04
#################

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

# Copy tini binary
COPY --from=build-tini --chown=root:root /usr/bin/tini /usr/bin/tini

# Copy supercronic binary
COPY --from=build-supercronic --chown=root:root /go/bin/supercronic /usr/bin/supercronic

# Copy luarocks packages
COPY --from=build-knot-resolver --chown=root:root /usr/local/lib/lua/ /usr/local/lib/lua/
COPY --from=build-knot-resolver --chown=root:root /usr/local/share/lua/ /usr/local/share/lua/

# Install Knot DNS from package
COPY --from=build-knot-resolver --chown=root:root /tmp/knot-dns/knot-dns_*.deb /tmp/
RUN dpkg -i /tmp/knot-dns_*.deb && rm /tmp/knot-dns_*.deb

# Install Knot Resolver from package
COPY --from=build-knot-resolver --chown=root:root /tmp/knot-resolver/knot-resolver_*.deb /tmp/
RUN dpkg -i /tmp/knot-resolver_*.deb && rm /tmp/knot-resolver_*.deb

# Copy hBlock script
COPY --from=build-knot-resolver --chown=root:root /usr/bin/hblock /usr/bin/hblock

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
COPY --chown=root:root config/kresd.conf.lua /etc/knot-resolver/kresd.conf
COPY --chown=knot-resolver:knot-resolver config/kresd.extra.conf.lua /var/lib/knot-resolver/kresd.extra.conf

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

WORKDIR /var/lib/knot-resolver/
VOLUME /var/lib/knot-resolver/

HEALTHCHECK --start-period=60s --interval=30s --timeout=5s --retries=3 \
	CMD /usr/local/bin/docker-healthcheck-cmd

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/docker-foreground-cmd"]
