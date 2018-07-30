FROM ubuntu:18.04

# Environment
ARG KNOT_DNS_BRANCH=v2.6.8
ARG KNOT_DNS_REMOTE=https://gitlab.labs.nic.cz/knot/knot-dns.git

ARG KNOT_RESOLVER_BRANCH=v2.4.0
ARG KNOT_RESOLVER_REMOTE=https://gitlab.labs.nic.cz/knot/knot-resolver.git
ARG KNOT_RESOLVER_REQUIRE_INSTALLATION_CHECK=false
ARG KNOT_RESOLVER_REQUIRE_INTEGRATION_CHECK=false

ARG HBLOCK_BRANCH=v1.6.6
ARG HBLOCK_REMOTE=https://github.com/hectorm/hblock.git

ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_PKGS=' \
	autoconf \
	automake \
	cmake \
	dpkg-dev \
	g++ \
	gcc \
	git \
	libcap-ng-dev \
	libcmocka-dev \
	libedit-dev \
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
	diffutils \
	dns-root-data \
	gzip \
	libcap-ng0 \
	libedit2 \
	libfstrm0 \
	libgcc1 \
	libgeoip1 \
	libgnutls30 \
	libidn2-0 \
	libjansson4 \
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
	# Install Knot DNS (only libknot and utilities)
	&& git clone --recursive "${KNOT_DNS_REMOTE}" /tmp/knot-dns/ \
	&& (cd /tmp/knot-dns/ \
		&& git checkout "${KNOT_DNS_BRANCH}" \
		&& ./autogen.sh \
		&& ./configure \
			--prefix=/usr \
			--disable-daemon \
			--disable-modules \
			--disable-documentation \
			--enable-utilities \
		&& make -j$(nproc) \
		&& make install \
		&& /usr/bin/kdig --version \
		&& /usr/bin/khost --version \
	) \
	# Install Knot Resolver
	&& git clone --recursive "${KNOT_RESOLVER_REMOTE}" /tmp/knot-resolver/ \
	&& (cd /tmp/knot-resolver/ \
		&& git checkout "${KNOT_RESOLVER_BRANCH}" \
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
		&& /usr/sbin/kresd --version \
	) \
	&& groupadd -r -g 500 knot-resolver \
	&& useradd -r -u 500 -g 500 -md /var/cache/knot-resolver/ knot-resolver \
	&& mkdir -p /var/lib/knot-resolver/ \
	&& chown -R knot-resolver:knot-resolver /var/lib/knot-resolver/ \
	# Install hBlock
	&& git clone --recursive "${HBLOCK_REMOTE}" /tmp/hblock/ \
	&& (cd /tmp/hblock/ \
		git checkout "${HBLOCK_BRANCH}" \
		&& mv ./hblock /usr/bin/hblock \
		&& chmod 755 /usr/bin/hblock \
		&& /usr/bin/hblock --version \
	) \
	# Create supervisor group
	&& groupadd -r supervisor \
	&& usermod -aG supervisor knot-resolver \
	# Cleanup
	&& apt-get purge -y ${BUILD_PKGS} \
	&& apt-get autoremove -y \
	&& rm -rf /tmp/* /etc/cron.*/ /var/lib/apt/lists/*

# Copy scripts and config
COPY --chown=root:root scripts/ /usr/local/bin/
COPY --chown=root:root config/supervisord.conf /etc/supervisord.conf
COPY --chown=root:root config/crontab /etc/crontab
COPY --chown=root:root config/kresd.conf.lua /etc/knot-resolver/kresd.conf
COPY --chown=knot-resolver:knot-resolver config/kresd.extra.conf.lua /var/lib/knot-resolver/kresd.extra.conf

# Ensure correct permissions for crontab
RUN chmod 644 /etc/crontab

WORKDIR /var/lib/knot-resolver/
VOLUME /var/lib/knot-resolver/

EXPOSE 53/tcp 53/udp 8053/tcp

HEALTHCHECK --start-period=60s --interval=60s --timeout=3s --retries=3 \
	CMD [ "$(curl -fs http://localhost:8053/health)" = OK ]

CMD ["/usr/local/bin/docker-foreground-cmd"]
