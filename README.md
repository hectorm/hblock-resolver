[![Docker pulls](https://img.shields.io/docker/pulls/hectormolinero/hblock-resolver?label=Docker%20pulls)](https://hub.docker.com/r/hectormolinero/hblock-resolver)
[![GitHub CI](https://img.shields.io/github/workflow/status/hectorm/hblock-resolver/Development%20build?label=GitHub%20CI)](https://github.com/hectorm/hblock-resolver/commits)
[![GitLab CI](https://img.shields.io/gitlab/pipeline/hectorm/hblock-resolver/master?label=GitLab%20CI)](https://gitlab.com/hectorm/hblock-resolver/pipelines)
[![License](https://img.shields.io/github/license/hectorm/hblock-resolver?label=License)](LICENSE.md)

***

# hBlock Resolver

A Docker image of [Knot Resolver](https://www.knot-resolver.cz) configured to automatically block ads, tracking and malware domains with
[hBlock](https://github.com/hectorm/hblock).

## Start an instance

```sh
docker run --detach \
  --name hblock-resolver \
  --restart on-failure:3 \
  --publish 127.0.0.1:53:53/udp \
  --publish 127.0.0.1:53:53/tcp \
  --publish 127.0.0.1:853:853/tcp \
  --publish 127.0.0.1:8453:8453/tcp \
  --mount type=volume,src=hblock-resolver-data,dst=/var/lib/knot-resolver/ \
  hectormolinero/hblock-resolver:latest
```

> **Warning:** do not expose this service to the open internet. An open DNS resolver represents a significant threat and it can be used in a number of
different attacks, such as [DNS amplification attacks](https://www.cloudflare.com/learning/ddos/dns-amplification-ddos-attack/).

## Environment variables

#### `KRESD_DNS{1..4}_IP` (default: `1.1.1.1@853` and `1.0.0.1@853`)
IP (and optionally port) of the DNS-over-TLS server to which the queries will be forwarded
([alternative DoT servers](https://dnsprivacy.org/wiki/display/DP/DNS+Privacy+Public+Resolvers#DNSPrivacyPublicResolvers-DNS-over-TLS(DoT))).

#### `KRESD_DNS{1..4}_HOSTNAME` (default: `cloudflare-dns.com`)
Hostname of the DNS-over-TLS server to which the queries will be forwarded
([CA+hostname authentication docs](https://knot-resolver.readthedocs.io/en/stable/modules.html#ca-hostname-authentication)).

#### `KRESD_DNS{1..4}_PIN_SHA256` (default: empty)
Certificate hash of the DNS-over-TLS server to which the queries will be forwarded
([key-pinned authentication docs](https://knot-resolver.readthedocs.io/en/stable/modules.html#key-pinned-authentication)).

#### `KRESD_WATCHDOG_QNAME` (default: `cloudflare.com.`)
Query name to check the health status of kresd.

#### `KRESD_WATCHDOG_QTYPE` (default: `A`)
Query type to check the health status of kresd.

#### `KRESD_WATCHDOG_INTERVAL` (default: `10000`)
Interval in seconds to check the health status of kresd.

#### `KRESD_CERT_MANAGED` (default: `true`)
If equals `true`, a self-signed certificate will be generated. You can provide your own certificate with these options:
```
  --env KRESD_CERT_MANAGED=false \
  --mount type=bind,src='/path/to/server.key',dst='/var/lib/knot-resolver/ssl/server.key',ro \
  --mount type=bind,src='/path/to/server.crt',dst='/var/lib/knot-resolver/ssl/server.crt',ro \
```
> **Note:** for a more advanced setup, look at the [following example](examples/caddy) with [Let's Encrypt](https://letsencrypt.org) and
[Caddy](https://caddyserver.com/).

#### `KRESD_NIC` (default: empty)
If defined, kresd will only listen on the specified interface. Some users observed a considerable, close to 100%, performance gain in Docker
containers when they bound the daemon to a single interface:ip address pair
([dynamic configuration docs](https://knot-resolver.readthedocs.io/en/latest/daemon.html?highlight=docker#dynamic-configuration),
[CZ-NIC/knot-resolver#32](https://github.com/CZ-NIC/knot-resolver/pull/32)).

#### `KRESD_VERBOSE` (default: `false`)
If equals `true`, verbose logging will be enabled.

## Additional configuration

Main Knot DNS Resolver configuration is located in `/etc/knot-resolver/kresd.conf`. If you would like to add additional configuration, add one or more
`*.conf` files under `/etc/knot-resolver/kresd.conf.d/`.

## License

See the [license](LICENSE.md) file.
