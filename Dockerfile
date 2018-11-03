FROM ubuntu:18.04 AS build-tini
###############################

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		build-essential \
		ca-certificates \
		cmake \
		git \
	&& rm -rf /var/lib/apt/lists/*

# Build Tiny
ARG TINY_BRANCH=v0.18.0
ARG TINY_REMOTE=https://github.com/krallin/tini.git
RUN git clone --recursive "${TINY_REMOTE}" /tmp/tini/ \
	&& cd /tmp/tini/ \
	&& git checkout "${TINY_BRANCH}" \
	&& export CFLAGS='-DPR_SET_CHILD_SUBREAPER=36 -DPR_GET_CHILD_SUBREAPER=37' \
	&& cmake . -DCMAKE_INSTALL_PREFIX=/usr \
	&& make -j$(nproc) install

FROM golang:1-stretch AS build-supercronic
##########################################

# Build dep
RUN go get -d github.com/golang/dep \
	&& cd "${GOPATH}/src/github.com/golang/dep" \
	&& DEP_LATEST=$(git describe --abbrev=0 --tags) \
	&& git checkout "${DEP_LATEST}" \
	&& go install -ldflags="-X main.version=${DEP_LATEST}" ./cmd/dep \
	&& dep version

# Build supercronic
ARG SUPERCRONIC_BRANCH=v0.1.6
ARG SUPERCRONIC_PACKAGE=github.com/aptible/supercronic
RUN go get -d "${SUPERCRONIC_PACKAGE}" \
	&& cd "${GOPATH}/src/${SUPERCRONIC_PACKAGE}" \
	&& git checkout "${SUPERCRONIC_BRANCH}" \
	&& dep ensure \
	&& go install

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
		cmake \
		dns-root-data \
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
		xxd \
	&& rm -rf /var/lib/apt/lists/*

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
ARG KNOT_DNS_BRANCH=v2.7.3
ARG KNOT_DNS_REMOTE=https://gitlab.labs.nic.cz/knot/knot-dns.git
RUN git clone --recursive "${KNOT_DNS_REMOTE}" /tmp/knot-dns/ \
	&& cd /tmp/knot-dns/ \
	&& git checkout "${KNOT_DNS_BRANCH}" \
	&& ./autogen.sh \
	&& ./configure \
		--prefix=/usr \
		--disable-daemon \
		--disable-modules \
		--disable-documentation \
		--enable-utilities \
	&& make -j$(nproc) install \
	&& /usr/bin/kdig --version \
	&& /usr/bin/khost --version

# Build Knot Resolver
ARG KNOT_RESOLVER_BRANCH=v3.1.0
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_REQUIRE_INSTALLATION_CHECK=false
ARG KNOT_RESOLVER_REQUIRE_INTEGRATION_CHECK=false
RUN git clone --recursive "${KNOT_RESOLVER_REMOTE}" /tmp/knot-resolver/ \
	&& cd /tmp/knot-resolver/ \
	&& git checkout "${KNOT_RESOLVER_BRANCH}" \
	&& pip3 install --user -r tests/deckard/requirements.txt \
	&& make \
		CFLAGS='-O2 -fstack-protector' \
		PREFIX=/usr \
		ETCDIR=/etc/knot-resolver \
		MODULEDIR=/usr/lib/knot-resolver \
		ROOTHINTS=/usr/share/dns/root.hints \
		-j$(nproc) check install \
	&& rm /etc/knot-resolver/root.hints \
	&& if ! make PREFIX=/usr installcheck; then \
		>&2 printf '%s\n' 'Installation check failed'; \
		if [ "${KNOT_RESOLVER_REQUIRE_INSTALLATION_CHECK}" = true ]; then \
			exit 1; \
		fi; \
	fi \
	&& if ! make PREFIX=/usr check-integration; then \
		>&2 printf '%s\n' 'Integration check failed'; \
		if [ "${KNOT_RESOLVER_REQUIRE_INTEGRATION_CHECK}" = true ]; then \
			exit 1; \
		fi; \
	fi \
	&& /usr/sbin/kresd --version

# Download hBlock
ARG HBLOCK_BRANCH=v1.6.9
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git
RUN git clone --recursive "${HBLOCK_REMOTE}" /tmp/hblock/ \
	&& cd /tmp/hblock/ \
	&& git checkout "${HBLOCK_BRANCH}" \
	&& mv ./hblock /usr/bin/hblock \
	&& chmod 755 /usr/bin/hblock \
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

# Copy Knot DNS installation
COPY --from=build-knot-resolver --chown=root:root /usr/lib/libknot.* /usr/lib/
COPY --from=build-knot-resolver --chown=root:root /usr/lib/libdnssec.* /usr/lib/
COPY --from=build-knot-resolver --chown=root:root /usr/lib/libzscanner.* /usr/lib/
COPY --from=build-knot-resolver --chown=root:root /usr/bin/kdig /usr/bin/kdig
COPY --from=build-knot-resolver --chown=root:root /usr/bin/khost /usr/bin/khost

# Copy Knot Resolver installation
COPY --from=build-knot-resolver --chown=root:root /etc/knot-resolver/ /etc/knot-resolver/
COPY --from=build-knot-resolver --chown=root:root /usr/lib/knot-resolver/ /usr/lib/knot-resolver/
COPY --from=build-knot-resolver --chown=root:root /usr/lib/libkres.* /usr/lib/
COPY --from=build-knot-resolver --chown=root:root /usr/sbin/kresc /usr/sbin/kresc
COPY --from=build-knot-resolver --chown=root:root /usr/sbin/kresd /usr/sbin/kresd

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
