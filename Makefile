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

.PHONY: help check-tools test test-shim deps test-os test-qemu test-qemu-aarch64 check ci audit demo demos \
        image images reproducible uefi-image disk qemu format clean distclean

help: ## List targets
	@awk -F':.*## ' '/^[a-z0-9-]+:.*## / { printf "  %-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo "  (MILESTONE=$(MILESTONE))"

check-tools: ## Report missing host tools and versions
	@scripts/check-tools.sh

test: test-shim test-os ## Fast tests: shim unit tests + Elixir unit tests (no QEMU)

test-shim: ## Zig unit tests for the PID 1 shim
	zig build test -Dmilestone=$(MILESTONE) --summary all

deps: ## Fetch the locked Elixir dependency set for the OS
	cd os && mix deps.get

test-os: deps ## ExUnit tests for the Elixir userland (no QEMU)
	cd os && ELIXOS_MILESTONE=$(MILESTONE) mix test

test-qemu: deps image uefi-image ## Boot real images in QEMU (slow): os/test/integration
	cd os && ELIXOS_QEMU=1 ELIXOS_MILESTONE=$(MILESTONE) mix test test/integration

test-qemu-aarch64: images ## The aarch64 smoke set, on qemu-system-aarch64 (TCG: slow)
	cd os && ELIXOS_QEMU=1 ELIXOS_QEMU_AARCH64=1 ELIXOS_MILESTONE=$(MILESTONE) \
	  mix test test/integration/m16_aarch64_test.exs

ci: test test-qemu images ## Everything for the current milestone, both architectures

check: image ## While working on one milestone: host tests + its own integration tests, not the suite (M=26)
	@[ -n "$(M)" ] || { echo "usage: make check M=<milestone>" >&2; exit 1; }
	zig build test -Dmilestone=$(M) --summary all
	cd os && ELIXOS_MILESTONE=$(M) mix test
	cd os && ELIXOS_QEMU=1 ELIXOS_MILESTONE=$(M) mix test test/integration/m$(M)_*.exs

audit: ## Fail if a shipped test, Zig test block or vector changed without an ADR
	scripts/audit-tests.sh

demo: ## Record and check one demo: make demo M=4 (demos/README.md)
	@[ -n "$(M)" ] || { echo "usage: make demo M=<milestone>" >&2; exit 1; }
	demos/demo.sh $(M)

demos: ## Record and check every demo up to MILESTONE
	demos/demo.sh --all

image: ## This machine's image, incrementally (M16: melange + apko, ADR-041)
	scripts/build-image.sh
	scripts/mkdisk.sh

images: image ## Both architectures; aarch64 kernel and OTP are cross-built natively
	scripts/build-image.sh aarch64
	scripts/mkdisk.sh aarch64

reproducible: ## Assemble the x86_64 rootfs twice from the lockfile; print the one digest
	scripts/build-image.sh x86_64

uefi-image: image ## ESP with the EFI-stub kernel (M13)
	scripts/build-uefi-image.sh

disk: ## Pristine persistent disk (tests boot copies of it); unpacks the toolchain package
	scripts/mkdisk.sh

qemu: image ## Boot interactively (Ctrl-A X quits). ARGS="elixos.safe" appends to the cmdline
	scripts/run-qemu.sh $(ARGS)

format: ## Format Zig and Elixir sources
	zig fmt build.zig shim/src
	cd os && mix format

clean: ## Remove build outputs and the locally built packages
	rm -rf zig-out .zig-cache os/_build $(BUILD)/initramfs.* $(BUILD)/disk.img $(BUILD)/x86_64 \
	  $(BUILD)/aarch64 $(BUILD)/melange-src $(BUILD)/initramfs-scratch $(BUILD)/apk

distclean: clean ## Remove everything under build/
	rm -rf $(BUILD)
