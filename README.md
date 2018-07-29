[![Docker Build Status](https://img.shields.io/docker/build/hectormolinero/hblock-resolver.svg)](https://hub.docker.com/r/hectormolinero/hblock-resolver/)
[![Docker Image Size](https://img.shields.io/microbadger/image-size/hectormolinero/hblock-resolver/latest.svg)](https://hub.docker.com/r/hectormolinero/hblock-resolver/)
[![Docker Image Layers](https://img.shields.io/microbadger/layers/hectormolinero/hblock-resolver/latest.svg)](https://hub.docker.com/r/hectormolinero/hblock-resolver/)

***

# hBlock Resolver

A Docker image of [Knot DNS Resolver](https://www.knot-resolver.cz) configured to automatically block ads, tracking and malware domains with [hBlock](https://github.com/hectorm/hblock).

## Start an instance

```sh
docker run --detach \
  --name hblock-resolver \
  --hostname hblock-resolver \
  --restart on-failure:3 \
  --log-opt max-size=32m \
  --publish 53:53/tcp \
  --publish 53:53/udp \
  --publish 127.0.0.1:8053:8053/tcp \
  --mount type=volume,src=hblock-resolver-data,dst=/var/lib/knot-resolver/ \
  hectormolinero/hblock-resolver:latest
```
> It is likely that port 53 is already being used, the solution is left as an exercise for the reader.

## Environment variables

#### `HBLOCK_SOURCES`
If defined, the value will be passed to the [`--sources` option](https://github.com/hectorm/hblock#script-arguments) of hBlock.

#### `HBLOCK_WHITELIST`
If defined, the value will be passed to the [`--whitelist` option](https://github.com/hectorm/hblock#script-arguments) of hBlock.

#### `HBLOCK_BLACKLIST`
If defined, the value will be passed to the [`--blacklist` option](https://github.com/hectorm/hblock#script-arguments) of hBlock.

## License
See the [license](LICENSE.md) file.
