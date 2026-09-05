###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: gentoo-ing
#
# This image is a bootc-ready Gentoo system (architecture follows
# HuntedRaven7/blueprint's gentoo variant):
#
#   - Base:     gentoo/stage3:systemd
#   - Binhosts: ghcr.io/HuntedRaven7/gentoo-ing-packages (curated overlay,
#               priority 10000, COPY --from= pinned by digest below) is the
#               source of normal packages — it mirrors the official Gentoo
#               binhost set and compiles every gap, so no source rebuilds and
#               no runtime dependency on distfiles.gentoo.org;
#               ghcr.io/HuntedRaven7/gentoo-ing-akmods (priority 10100) ships
#               the out-of-tree kernel modules (nvidia) prebuilt against this
#               image's exact kernel (see .kver lockstep gate in 10-build.sh)
#   - System:   emerges the OSTree/kernel/dracut/Podman stack plus the full
#               GNOME desktop entirely from the overlay binrepo (no compiler
#               anywhere), builds the initramfs, writes prepare-root.conf,
#               boots; runs the default/linux/amd64/23.0/desktop/gnome/systemd
#               profile so its USE match the overlay's compiled closure
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
# 1. Binhost stages - the binary package caches from the two factories:
#    ghcr.io/HuntedRaven7/gentoo-ing-packages contains:
#      /var/cache/binhost/gentoo-ing          -> binpkg tree + Packages index
#      /var/cache/binhost/gentoo-ing-ebuilds  -> ebuild overlay (bootc, + any
#                                                package ::gentoo lacks)
#    The gentoo-ing-packages factory seeds the official binhost's set and
#    BUILDS the gaps (bootc, kernel, firmware, skopeo, flatpak, gum, just, iwd,
#    jq, GNOME) once, publishing them as binpkgs so this repo stays compile-free.
#    ghcr.io/HuntedRaven7/gentoo-ing-akmods contains:
#      /var/cache/binhost/gentoo-ing-akmods  -> module binpkg tree (.tbz2 +
#                                                Packages index + .manifest)
#                                                + .kver (exact build kernel)
#    The gentoo-ing-akmods factory prebuilds out-of-tree kernel modules
#    (x11-drivers/nvidia-drivers) against the consumer's kernel — the only way
#    a sealed --usepkgonly image can carry a kernel-loaded module.
#
# 2. System stage - the actual image: binrepos.conf points at the curated
#    overlay (priority 10000) for normal packages and the module overlay
#    (priority 10100) for nvidia, emerge of the kernel/firmware/OSTree/Podman/
#    skopeo/systemd stack + GNOME + nvidia with --getbinpkg + --usepkgonly (hard
#    failure if a binpkg is missing — never a source build), dracut initramfs,
#    prepare-root.conf (composefs + readonly sysroot), and bootc container lint.
#    Final layers are bootable via /sbin/init.
#
# See: https://github.com/HuntedRaven7/blueprint/blob/main/docs/GENTOO.md
###############################################################################

# Image references are declared as GLOBAL ARGs (before the first FROM) so every
# following FROM can see them; buildah resolves FROM ${VAR} to empty otherwise
# ("no FROM statement found"). Digests are pinned by Renovate.

# Curated binhost produced by the gentoo-ing-packages factory.
ARG GENTOO_PACKAGES_IMAGE="ghcr.io/huntedraven7/gentoo-ing-packages@sha256:6aa7669680b4fc249b4e9cbe347091957cdfdc14149798ad18a7b042957aa433"
# Module binhost produced by the gentoo-ing-akmods factory: out-of-tree kernel
# modules prebuilt against the exact kernel this image ships (its .kver gate).
# The pinned digest must always be rebuilt after a kernel bump, or the
# 10-build.sh .kver lockstep gate fails the build.
ARG GENTOO_AKMODS_IMAGE="ghcr.io/huntedraven7/gentoo-ing-akmods@sha256:cc18a9f94fb337c3fa3bc4595add55baabd15e69d55670d5f1c76b521d32b535"
# Base image - Gentoo stage3 with systemd. Renovate will keep the digest pin
# current.
ARG GENTOO_IMAGE="gentoo/stage3:systemd"

FROM ${GENTOO_PACKAGES_IMAGE} AS pkgs
FROM ${GENTOO_AKMODS_IMAGE} AS akmods

# Context stage - combine local build scripts, system files, and custom files
FROM scratch AS ctx

COPY build /build
COPY custom /custom
COPY system_files /system_files

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
# Module binhost: prebuilt out-of-tree kernel modules + their closure, plus
# the .kver (exact kernel) and .manifest (kept for tooling/inspection purposes).
COPY --from=akmods /var/cache/binhost/gentoo-ing-akmods /var/cache/binhost/gentoo-ing-akmods

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