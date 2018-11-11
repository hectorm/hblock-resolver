[![Pipeline Status](https://gitlab.com/hectorm/hblock-resolver/badges/master/pipeline.svg)](https://gitlab.com/hectorm/hblock-resolver/pipelines)
[![Docker Image Size](https://img.shields.io/microbadger/image-size/hectormolinero/hblock-resolver/latest.svg)](https://hub.docker.com/r/hectormolinero/hblock-resolver/)
[![Docker Image Layers](https://img.shields.io/microbadger/layers/hectormolinero/hblock-resolver/latest.svg)](https://hub.docker.com/r/hectormolinero/hblock-resolver/)
[![License](https://img.shields.io/github/license/hectorm/hblock-resolver.svg)](LICENSE.md)

***

# hBlock Resolver
A Docker image of [Knot DNS Resolver](https://www.knot-resolver.cz) configured to automatically block ads, tracking and malware domains with
[hBlock](https://github.com/hectorm/hblock).

## Start an instance
```sh
docker run --detach \
  --name hblock-resolver \
  --hostname hblock-resolver \
  --restart on-failure:3 \
  --log-opt max-size=32m \
  --publish 53:53/tcp \
  --publish 53:53/udp \
  --publish 853:853/tcp \
  --publish 127.0.0.1:8053:8053/tcp \
  --mount type=volume,src=hblock-resolver-data,dst=/var/lib/knot-resolver/ \
  hectormolinero/hblock-resolver:latest
```
> **Warning:** do not expose this service to the open internet. An open DNS resolver represents a significant threat and it can be used in a number of
different attacks, such as [DNS amplification attacks](https://www.cloudflare.com/learning/ddos/dns-amplification-ddos-attack/).

## Environment variables
#### `HBLOCK_SOURCES`
If defined, the value will be passed to the [`--sources` option](https://github.com/hectorm/hblock#script-arguments) of hBlock.

#### `HBLOCK_WHITELIST`
If defined, the value will be passed to the [`--whitelist` option](https://github.com/hectorm/hblock#script-arguments) of hBlock.

#### `HBLOCK_BLACKLIST`
If defined, the value will be passed to the [`--blacklist` option](https://github.com/hectorm/hblock#script-arguments) of hBlock.

#### `KRESD_NIC`
If defined, kresd will only listen on the specified interface. Some users observed a considerable, close to 100%, performance gain in Docker
containers when they bound the daemon to a single interface:ip address pair ([CZ-NIC/knot-resolver#32](https://github.com/CZ-NIC/knot-resolver/pull/32),
[dynamic configuration docs](https://knot-resolver.readthedocs.io/en/latest/daemon.html?highlight=docker#dynamic-configuration)).

#### `KRESD_CERT_MODE`
If equals to `self-signed` (**default**), a self-signed certificate will be generated. You can provide your own certificate with these options:
```
  --mount type=bind,src='/path/to/server.key',dst='/var/lib/knot-resolver/ssl/server.key',ro \
  --mount type=bind,src='/path/to/server.crt',dst='/var/lib/knot-resolver/ssl/server.crt',ro \
  --env KRESD_CERT_MODE=external \
```

## Additional configuration
Main Knot DNS Resolver configuration is located in `/etc/knot-resolver/kresd.conf`. If you would like to add additional configuration, add one or more
`*.conf` files under `/etc/knot-resolver/kresd.conf.d/`.

## License
See the [license](LICENSE.md) file.
