# Elixos. Start with AGENTS.md; `make help` lists targets.
#
# Every target is safe to re-run. Tests are gated by the MILESTONE file
# (docs/TESTING.md): tests for later milestones exist but are skipped.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

MILESTONE := $(shell cat MILESTONE)
BUILD ?= build
export ELIXOS_BUILD := $(abspath $(BUILD))

# QEMU test images need the elixos.test.* hooks compiled into the shim.
# Images for real hardware must use `make release-shim` instead.
TEST_HOOKS ?= true

# From M4 on, generation 0 (the factory) goes into the image.
NEEDS_FACTORY := $(shell [ $(MILESTONE) -ge 4 ] && echo yes)

.PHONY: help check-tools test test-shim test-os test-qemu ci image kernel shim release-shim \
        factory initramfs disk uefi-image qemu format clean distclean audit

help: ## List targets
	@awk -F':.*## ' '/^[a-z-]+:.*## / { printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo "  (MILESTONE=$(MILESTONE))"

check-tools: ## Report missing host tools and versions
	@scripts/check-tools.sh

test: test-shim test-os ## Fast tests: shim unit tests + Elixir unit tests (no QEMU)

test-shim: ## Zig unit tests for the PID 1 shim
	zig build test -Dmilestone=$(MILESTONE) --summary all

test-os: ## ExUnit tests for the Elixir userland (no QEMU)
	cd os && ELIXOS_MILESTONE=$(MILESTONE) mix test

test-qemu: image ## Boot real images in QEMU (slow): os/test/integration
	cd os && ELIXOS_QEMU=1 ELIXOS_MILESTONE=$(MILESTONE) mix test test/integration

ci: test test-qemu ## Everything for the current milestone

audit: ## Fail if a shipped test, Zig test block or vector changed without an ADR
	scripts/audit-tests.sh

kernel: $(BUILD)/bzImage ## Pinned mainline kernel: configured, never patched (ADR-001)

$(BUILD)/bzImage: kernel/VERSION kernel/elixos.config scripts/build-kernel.sh scripts/check-kernel-config.sh
	scripts/build-kernel.sh

shim: ## The PID 1 shim for QEMU test images (with test hooks)
	zig build -Drelease -Dtest-hooks=$(TEST_HOOKS)

release-shim: ## The PID 1 shim for real hardware (no test hooks)
	zig build -Drelease -Dtest-hooks=false

factory: ## Generation 0 into build/rootfs (M4+)
	scripts/build-factory.sh

initramfs: kernel shim $(if $(NEEDS_FACTORY),factory) ## build/initramfs.cpio.gz
	scripts/build-initramfs.sh

disk: $(BUILD)/disk.img ## Pristine persistent disk (tests boot copies of it)

$(BUILD)/disk.img:
	scripts/mkdisk.sh

image: kernel initramfs disk ## Everything QEMU boots

uefi-image: image ## ESP with the EFI-stub kernel (M13)
	scripts/build-uefi-image.sh

qemu: image ## Boot interactively (Ctrl-A X quits). ARGS="elixos.safe" appends to the cmdline
	scripts/run-qemu.sh $(ARGS)

format: ## Format Zig and Elixir sources
	zig fmt build.zig shim/src
	cd os && mix format

clean: ## Remove build outputs, keeping downloads and the kernel tree
	rm -rf zig-out .zig-cache os/_build $(BUILD)/initramfs.* $(BUILD)/disk.img $(BUILD)/rootfs $(BUILD)/esp.img

distclean: clean ## Remove everything under build/
	rm -rf $(BUILD)
