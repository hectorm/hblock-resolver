#!/usr/bin/make -f

MKFILE_RELPATH := $(shell printf -- '%s' '$(MAKEFILE_LIST)' | sed 's|^\ ||')
MKFILE_ABSPATH := $(shell readlink -f -- '$(MKFILE_RELPATH)')
MKFILE_DIR := $(shell dirname -- '$(MKFILE_ABSPATH)')

DIST_DIR := $(MKFILE_DIR)/dist

DOCKER_IMAGE_NAMESPACE := hectormolinero
DOCKER_IMAGE_NAME := hblock-resolver
DOCKER_IMAGE_VERSION := latest
DOCKER_IMAGE_TAG := $(DOCKER_IMAGE_VERSION)
DOCKER_IMAGE := $(DOCKER_IMAGE_NAMESPACE)/$(DOCKER_IMAGE_NAME)
DOCKER_CONTAINER := $(DOCKER_IMAGE_NAME)
DOCKERFILE := $(MKFILE_DIR)/Dockerfile

.PHONY: all
all: build

.PHONY: build
build: save-image

.PHONY: build-image
build-image:
	docker build \
		--tag '$(DOCKER_IMAGE):$(DOCKER_IMAGE_TAG)' \
		--build-arg KNOT_RESOLVER_REQUIRE_INSTALLATION_CHECK=true \
		--build-arg KNOT_RESOLVER_REQUIRE_INTEGRATION_CHECK=true \
		--file '$(DOCKERFILE)' \
		-- '$(MKFILE_DIR)'

.PHONY: save-image
save-image: build-image
	mkdir -p -- '$(DIST_DIR)'
	docker save -- '$(DOCKER_IMAGE):$(DOCKER_IMAGE_TAG)' | gzip > '$(DIST_DIR)/$(DOCKER_IMAGE_NAME).$(DOCKER_IMAGE_TAG).tgz'

.PHONY: clean
clean: clean-image clean-dist

.PHONY: clean-image
clean-image: clean-container
	-docker rmi -- '$(DOCKER_IMAGE):$(DOCKER_IMAGE_TAG)'

.PHONY: clean-container
clean-container:
	-docker stop -- '$(DOCKER_CONTAINER)'
	-docker rm -- '$(DOCKER_CONTAINER)'

.PHONY: clean-dist
clean-dist:
	rm -rf -- '$(DIST_DIR)'
