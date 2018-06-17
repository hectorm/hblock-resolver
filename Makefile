#!/usr/bin/make -f

MKFILE_RELPATH := $(shell printf -- '%s' '$(MAKEFILE_LIST)' | sed 's|^\ ||')
MKFILE_ABSPATH := $(shell readlink -f -- '$(MKFILE_RELPATH)')
MKFILE_DIR := $(shell dirname -- '$(MKFILE_ABSPATH)')

.PHONY: all \
	build build-image \
	clean clean-image clean-container clean-volume clean-dist

all: build

build: dist/hblock-resolver.tgz

build-image:
	docker build \
		--rm \
		--tag hblock-resolver:latest \
		--file Dockerfile \
		'$(MKFILE_DIR)'

dist/:
	mkdir -p dist

dist/hblock-resolver.tgz: dist/ build-image
	docker save hblock-resolver:latest | gzip > dist/hblock-resolver.tgz

clean: clean-image clean-volume clean-dist

clean-image: clean-container
	-docker rmi hblock-resolver:latest

clean-container:
	-docker stop hblock-resolver
	-docker rm hblock-resolver

clean-volume:
	-docker volume rm hblock-resolver-data

clean-dist:
	rm -f dist/hblock-resolver.tgz
	-rmdir dist
