#!/usr/bin/make -f

SHELL := /bin/sh
.SHELLFLAGS := -eu -c

DOCKER := $(shell command -v docker 2>/dev/null)
GIT := $(shell command -v git 2>/dev/null)
M4 := $(shell command -v m4 2>/dev/null)

DISTDIR := ./dist

IMAGE_NAMESPACE := hectormolinero
IMAGE_NAME := hblock-resolver
IMAGE_VERSION := v0

# If git is available and the directory is a repository, use the latest tag as IMAGE_VERSION.
ifeq ([$(notdir $(GIT))][$(wildcard .git/.)],[git][.git/.])
	IMAGE_VERSION := $(shell '$(GIT)' describe --abbrev=0 --tags 2>/dev/null || printf '%s' '$(IMAGE_VERSION)')
endif

IMAGE_LATEST_TAG := $(IMAGE_NAMESPACE)/$(IMAGE_NAME):latest
IMAGE_VERSION_TAG := $(IMAGE_NAMESPACE)/$(IMAGE_NAME):$(IMAGE_VERSION)

IMAGE_NATIVE_DOCKERFILE := $(DISTDIR)/Dockerfile
IMAGE_NATIVE_TARBALL := $(DISTDIR)/$(IMAGE_NAME).tgz

IMAGE_AMD64_DOCKERFILE := $(DISTDIR)/Dockerfile.amd64
IMAGE_AMD64_TARBALL := $(DISTDIR)/$(IMAGE_NAME).amd64.tgz

IMAGE_ARM32V7_DOCKERFILE := $(DISTDIR)/Dockerfile.arm32v7
IMAGE_ARM32V7_TARBALL := $(DISTDIR)/$(IMAGE_NAME).arm32v7.tgz

IMAGE_ARM64V8_DOCKERFILE := $(DISTDIR)/Dockerfile.arm64v8
IMAGE_ARM64V8_TARBALL := $(DISTDIR)/$(IMAGE_NAME).arm64v8.tgz

DOCKERFILE_TEMPLATE := ./Dockerfile.m4

##################################################
## "all" target
##################################################

.PHONY: all
all: save-native-image

##################################################
## "build-*" targets
##################################################

.PHONY: build-native-image
build-native-image: $(IMAGE_NATIVE_DOCKERFILE)

$(IMAGE_NATIVE_DOCKERFILE): $(DOCKERFILE_TEMPLATE)
	mkdir -p '$(DISTDIR)'
	'$(M4)' \
		--prefix-builtins \
		'$(DOCKERFILE_TEMPLATE)' | cat --squeeze-blank > '$@'
	'$(DOCKER)' build \
		--tag '$(IMAGE_VERSION_TAG)' \
		--tag '$(IMAGE_LATEST_TAG)' \
		--file '$@' ./

.PHONY: build-cross-images
build-cross-images: build-amd64-image build-arm32v7-image build-arm64v8-image

.PHONY: build-amd64-image
build-amd64-image: $(IMAGE_AMD64_DOCKERFILE)

$(IMAGE_AMD64_DOCKERFILE): $(DOCKERFILE_TEMPLATE)
	mkdir -p '$(DISTDIR)'
	'$(M4)' \
		--prefix-builtins \
		-D CROSS_ARCH=amd64 \
		-D CROSS_QEMU=/usr/bin/qemu-x86_64-static \
		'$(DOCKERFILE_TEMPLATE)' | cat --squeeze-blank > '$@'
	'$(DOCKER)' build \
		--tag '$(IMAGE_VERSION_TAG)-amd64' \
		--tag '$(IMAGE_LATEST_TAG)-amd64' \
		--file '$@' ./

.PHONY: build-arm32v7-image
build-arm32v7-image: $(IMAGE_ARM32V7_DOCKERFILE)

$(IMAGE_ARM32V7_DOCKERFILE): $(DOCKERFILE_TEMPLATE)
	mkdir -p '$(DISTDIR)'
	'$(M4)' \
		--prefix-builtins \
		-D CROSS_ARCH=arm32v7 \
		-D CROSS_QEMU=/usr/bin/qemu-arm-static \
		'$(DOCKERFILE_TEMPLATE)' | cat --squeeze-blank > '$@'
	'$(DOCKER)' build \
		--tag '$(IMAGE_VERSION_TAG)-arm32v7' \
		--tag '$(IMAGE_LATEST_TAG)-arm32v7' \
		--build-arg KNOT_RESOLVER_CONFIG_TESTS=disabled \
		--file '$@' ./

.PHONY: build-arm64v8-image
build-arm64v8-image: $(IMAGE_ARM64V8_DOCKERFILE)

$(IMAGE_ARM64V8_DOCKERFILE): $(DOCKERFILE_TEMPLATE)
	mkdir -p '$(DISTDIR)'
	'$(M4)' \
		--prefix-builtins \
		-D CROSS_ARCH=arm64v8 \
		-D CROSS_QEMU=/usr/bin/qemu-aarch64-static \
		'$(DOCKERFILE_TEMPLATE)' | cat --squeeze-blank > '$@'
	'$(DOCKER)' build \
		--tag '$(IMAGE_VERSION_TAG)-arm64v8' \
		--tag '$(IMAGE_LATEST_TAG)-arm64v8' \
		--build-arg KNOT_RESOLVER_CONFIG_TESTS=disabled \
		--file '$@' ./

##################################################
## "save-*" targets
##################################################

define save_image
	'$(DOCKER)' save '$(1)' | gzip -n > '$(2)'
endef

.PHONY: save-native-image
save-native-image: $(IMAGE_NATIVE_TARBALL)

$(IMAGE_NATIVE_TARBALL): $(IMAGE_NATIVE_DOCKERFILE)
	$(call save_image,$(IMAGE_VERSION_TAG),$@)

.PHONY: save-cross-images
save-cross-images: save-amd64-image save-arm32v7-image save-arm64v8-image

.PHONY: save-amd64-image
save-amd64-image: $(IMAGE_AMD64_TARBALL)

$(IMAGE_AMD64_TARBALL): $(IMAGE_AMD64_DOCKERFILE)
	$(call save_image,$(IMAGE_VERSION_TAG)-amd64,$@)

.PHONY: save-arm32v7-image
save-arm32v7-image: $(IMAGE_ARM32V7_TARBALL)

$(IMAGE_ARM32V7_TARBALL): $(IMAGE_ARM32V7_DOCKERFILE)
	$(call save_image,$(IMAGE_VERSION_TAG)-arm32v7,$@)

.PHONY: save-arm64v8-image
save-arm64v8-image: $(IMAGE_ARM64V8_TARBALL)

$(IMAGE_ARM64V8_TARBALL): $(IMAGE_ARM64V8_DOCKERFILE)
	$(call save_image,$(IMAGE_VERSION_TAG)-arm64v8,$@)

##################################################
## "load-*" targets
##################################################

define load_image
	'$(DOCKER)' load -i '$(1)'
endef

define tag_image
	'$(DOCKER)' tag '$(1)' '$(2)'
endef

.PHONY: load-native-image
load-native-image:
	$(call load_image,$(IMAGE_NATIVE_TARBALL))
	$(call tag_image,$(IMAGE_VERSION_TAG),$(IMAGE_LATEST_TAG))

.PHONY: load-cross-images
load-cross-images: load-amd64-image load-arm32v7-image load-arm64v8-image

.PHONY: load-amd64-image
load-amd64-image:
	$(call load_image,$(IMAGE_AMD64_TARBALL))
	$(call tag_image,$(IMAGE_VERSION_TAG)-amd64,$(IMAGE_LATEST_TAG)-amd64)

.PHONY: load-arm32v7-image
load-arm32v7-image:
	$(call load_image,$(IMAGE_ARM32V7_TARBALL))
	$(call tag_image,$(IMAGE_VERSION_TAG)-arm32v7,$(IMAGE_LATEST_TAG)-arm32v7)

.PHONY: load-arm64v8-image
load-arm64v8-image:
	$(call load_image,$(IMAGE_ARM64V8_TARBALL))
	$(call tag_image,$(IMAGE_VERSION_TAG)-arm64v8,$(IMAGE_LATEST_TAG)-arm64v8)

##################################################
## "push-*" targets
##################################################

define push_image
	'$(DOCKER)' push '$(1)'
endef

define push_cross_manifest
	'$(DOCKER)' manifest create --amend '$(1)' '$(2)-amd64' '$(2)-arm32v7' '$(2)-arm64v8'
	'$(DOCKER)' manifest annotate '$(1)' '$(2)-amd64' --os linux --arch amd64
	'$(DOCKER)' manifest annotate '$(1)' '$(2)-arm32v7' --os linux --arch arm --variant v7
	'$(DOCKER)' manifest annotate '$(1)' '$(2)-arm64v8' --os linux --arch arm64 --variant v8
	'$(DOCKER)' manifest push --purge '$(1)'
endef

.PHONY: push-native-image
push-native-image:
	@printf '%s\n' 'Unimplemented'

.PHONY: push-cross-images
push-cross-images: push-amd64-image push-arm32v7-image push-arm64v8-image

.PHONY: push-amd64-image
push-amd64-image:
	$(call push_image,$(IMAGE_VERSION_TAG)-amd64)
	$(call push_image,$(IMAGE_LATEST_TAG)-amd64)

.PHONY: push-arm32v7-image
push-arm32v7-image:
	$(call push_image,$(IMAGE_VERSION_TAG)-arm32v7)
	$(call push_image,$(IMAGE_LATEST_TAG)-arm32v7)

.PHONY: push-arm64v8-image
push-arm64v8-image:
	$(call push_image,$(IMAGE_VERSION_TAG)-arm64v8)
	$(call push_image,$(IMAGE_LATEST_TAG)-arm64v8)

push-cross-manifest:
	$(call push_cross_manifest,$(IMAGE_VERSION_TAG),$(IMAGE_VERSION_TAG))
	$(call push_cross_manifest,$(IMAGE_LATEST_TAG),$(IMAGE_LATEST_TAG))

##################################################
## "binfmt-*" targets
##################################################

.PHONY: binfmt-register
binfmt-register:
	'$(DOCKER)' run --rm --privileged multiarch/qemu-user-static:register

.PHONY: binfmt-reset
binfmt-reset:
	'$(DOCKER)' run --rm --privileged multiarch/qemu-user-static:register --reset

##################################################
## "version" target
##################################################

.PHONY: version
version:
	@if printf -- '%s' '$(IMAGE_VERSION)' | grep -q '^v[0-9]\{1,\}$$'; then \
		NEW_IMAGE_VERSION=$$(awk -v 'v=$(IMAGE_VERSION)' 'BEGIN {printf "v%.0f", substr(v,2)+1}'); \
		printf -- '%s\n' "$${NEW_IMAGE_VERSION}" > ./VERSION; \
		'$(GIT)' add ./VERSION; '$(GIT)' commit -m "$${NEW_IMAGE_VERSION}"; \
		'$(GIT)' tag -a "$${NEW_IMAGE_VERSION}" -m "$${NEW_IMAGE_VERSION}"; \
	else \
		>&2 printf -- 'Malformed version string: %s\n' '$(IMAGE_VERSION)'; \
		exit 1; \
	fi

##################################################
## "clean" target
##################################################

.PHONY: clean
clean:
	rm -f '$(IMAGE_NATIVE_DOCKERFILE)' '$(IMAGE_AMD64_DOCKERFILE)' '$(IMAGE_ARM32V7_DOCKERFILE)' '$(IMAGE_ARM64V8_DOCKERFILE)'
	rm -f '$(IMAGE_NATIVE_TARBALL)' '$(IMAGE_AMD64_TARBALL)' '$(IMAGE_ARM32V7_TARBALL)' '$(IMAGE_ARM64V8_TARBALL)'
	if [ -d '$(DISTDIR)' ] && [ -z "$$(ls -A '$(DISTDIR)')" ]; then rmdir '$(DISTDIR)'; fi
