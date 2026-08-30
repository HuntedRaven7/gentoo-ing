###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: gentoo-ing
#
# This image is a bootc-ready Gentoo system (architecture follows
# HuntedRaven7/blueprint's gentoo variant):
#
#   - Base:     gentoo/stage3:systemd
#   - Binhost:  official Gentoo binhost (priority 9999) provides the prebuilt
#               packages; ghcr.io/HuntedRaven7/gentoo-ing-packages (curated
#               overlay, priority 10000, COPY --from= pinned by digest below)
#               overrides any package we seed/publish — no source rebuilds
#   - Builder:  compiles bootc from source, stage area in /output
#   - System:   emerges the OSTree/kernel/dracut/Podman stack, builds the
#               initramfs, writes prepare-root.conf, boots
#
# The project name defined here is the single source of truth for your
# custom image's identity. When changing it, update all references in:
#   - Justfile: export IMAGE_NAME := env("IMAGE_NAME", "gentoo-ing")
#   - README.md: # gentoo-ing (title)
#   - artifacthub-repo.yml: repositoryID: gentoo-ing
#   - custom/ujust/README.md: localhost/gentoo-ing:stable (bootc switch example)
#   - .github/workflows/clean.yml: packages: gentoo-ing
#   - iso/iso.toml: ghcr.io/HuntedRaven7/gentoo-ing:stable
###############################################################################

###############################################################################
# MULTI-STAGE BUILD ARCHITECTURE
###############################################################################
# The finpilot factory pattern, rebased onto Gentoo. The main image NEVER
# compiles a package: every atom comes prebuilt from a binhost.
#
# 1. Binhost stage (pkgs) - the binary package cache from
#    ghcr.io/HuntedRaven7/gentoo-ing-packages. Its content is:
#      /var/cache/binhost/gentoo-ing          -> binpkg tree + Packages index
#      /var/cache/binhost/gentoo-ing-ebuilds  -> ebuild overlay (bootc, + any
#                                                package ::gentoo lacks)
#    The gentoo-ing-packages factory seeds the official binhost's set and
#    BUILDS the gaps (bootc, kernel, firmware, skopeo, flatpak, gum, just, iwd,
#    jq) once, publishing them as binpkgs so this repo stays compile-free.
#
# 2. System stage - the actual image: binrepos.conf with the curated overlay at
#    priority 10000 above the official binhost (9999), emerge of the
#    kernel/firmware/OSTree/Podman/skopeo/systemd stack with --getbinpkg +
#    --usepkgonly (hard failure if a binpkg is missing — never a source build),
#    dracut initramfs, prepare-root.conf (composefs + readonly sysroot), and
#    bootc container lint. Final layers are bootable via /sbin/init.
#
# See: https://github.com/HuntedRaven7/blueprint/blob/main/docs/GENTOO.md
###############################################################################

# Curated binhost produced by the gentoo-ing-packages factory. Digest is pinned
# by Renovate; a floating tag initially while the first publish is seeded.
ARG GENTOO_PACKAGES_IMAGE="ghcr.io/HuntedRaven7/gentoo-ing-packages:latest"
FROM ${GENTOO_PACKAGES_IMAGE} AS pkgs

# Context stage - combine local build scripts, system files, and custom files
FROM scratch AS ctx

COPY build /build
COPY custom /custom
COPY system_files /system_files

# Base image - Gentoo stage3 with systemd. Renovate will keep the digest pin
# current.
ARG GENTOO_IMAGE="gentoo/stage3:systemd"
FROM ${GENTOO_IMAGE} AS system

# Re-declare identity ARGs for the system stage
ARG IMAGE_NAME="gentoo-ing"
ARG IMAGE_VENDOR="HuntedRaven7"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="gentoo"
ARG GENTOO_PROFILE="23.0"
ARG VERSION=""

# Curated binhost + ebuild overlay for the runtime image (usable with
# emerge --getbinpkg --usepkgonly). The binhost is pure binaries; the ebuild
# overlay carries the few atoms ::gentoo lacks (bootc) so their versions
# resolve during dependency calculation.
COPY --from=pkgs /var/cache/binhost/gentoo-ing /var/cache/binhost/gentoo-ing
COPY --from=pkgs /var/cache/binhost/gentoo-ing-ebuilds /var/cache/binhost/gentoo-ing-ebuilds

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build/00-image-info.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build/10-build.sh

### /var
## bootc requires a writable /var for the sysroot; the build script lays out the
## /var symlink structure (home, roothome, srv, mnt, opt, usrlocal).

### INIT
## Required for bootc images
CMD ["/sbin/init"]

### LINTING
## Verify final image and contents are correct. --fatal-warnings catches issues.
LABEL containers.bootc=1
RUN bootc container lint --fatal-warnings