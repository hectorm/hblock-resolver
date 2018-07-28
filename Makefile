#!/usr/bin/make -f

MKFILE_RELPATH := $(shell printf -- '%s' '$(MAKEFILE_LIST)' | sed 's|^\ ||')
MKFILE_ABSPATH := $(shell readlink -f -- '$(MKFILE_RELPATH)')
MKFILE_DIR := $(shell dirname -- '$(MKFILE_ABSPATH)')

DIST_DIR := $(MKFILE_DIR)/dist

DOCKER_IMAGE_NAMESPACE := hectormolinero
DOCKER_IMAGE_NAME := hblock-resolver
DOCKER_IMAGE := $(DOCKER_IMAGE_NAMESPACE)/$(DOCKER_IMAGE_NAME)
DOCKER_CONTAINER := $(DOCKER_IMAGE_NAME)
DOCKERFILE := $(MKFILE_DIR)/Dockerfile

.PHONY: all \
	build build-image save-image \
	clean clean-image clean-container clean-dist

all: build

build: save-image

build-image:
	docker build \
		--tag '$(DOCKER_IMAGE):latest' \
		--build-arg KNOT_RESOLVER_REQUIRE_INSTALLATION_CHECK=true \
		--build-arg KNOT_RESOLVER_REQUIRE_INTEGRATION_CHECK=true \
		--file '$(DOCKERFILE)' \
		-- '$(MKFILE_DIR)'

save-image: build-image
	mkdir -p -- '$(DIST_DIR)'
	docker save -- '$(DOCKER_IMAGE):latest' | gzip > '$(DIST_DIR)/$(DOCKER_IMAGE_NAME).tgz'

clean: clean-image clean-dist

clean-image: clean-container
	-docker rmi -- '$(DOCKER_IMAGE):latest'

clean-container:
	-docker stop -- '$(DOCKER_CONTAINER)'
	-docker rm -- '$(DOCKER_CONTAINER)'

clean-dist:
	rm -f -- '$(DIST_DIR)/$(DOCKER_IMAGE_NAME).tgz'
	-rmdir -- '$(DIST_DIR)'
