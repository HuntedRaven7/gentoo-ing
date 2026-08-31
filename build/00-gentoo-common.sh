#!/usr/bin/env bash

set -euo pipefail

# Shared Gentoo bootstrap for gentoo-ing. Sourced by 10-build.sh.
# Idempotent: safe to run more than once in a build.
#
# The image NEVER compiles a package. Portage is wired for strict binary
# consumption: --getbinpkg --usepkgonly (hard failure if a binpkg is missing
# from the overlay or the official host — never a source fallback).
#
# Configures:
#   - Portage tree (emerge-webrsync fallback for fresh stage images)
#   - profile symlink
#   - make.conf defaults (stable keywords, getbinpkg + usepkgonly, nproc -j)
#   - package.license / package.accept_keywords drop-ins
#   - ebuild overlay for atoms ::gentoo lacks (bootc) from the binhost image
#   - binrepos.conf: curated overlay (priority 10000) + official binhost (9999)

BRANCH_PROFILE="default/linux/amd64/23.0/systemd"
BINHOST_OVERLAY="/var/cache/binhost/gentoo-ing"
EBUILD_OVERLAY="/var/cache/binhost/gentoo-ing-ebuilds"
OFFICIAL_BINHOST="https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/"

# 1. Portage tree. stage3 images ship it, but a fresh/base image may not.
if [ ! -d /var/db/repos/gentoo/profiles ]; then
    emerge-webrsync || emerge --sync
fi

# 2. Profile
rm -f /etc/portage/make.profile
ln -s "/var/db/repos/gentoo/profiles/${BRANCH_PROFILE}" /etc/portage/make.profile

# 3. make.conf (idempotent appends). Stable keywords only: everything must
# resolve as a binpkg on the overlay (10000) or the official binhost (9999).
touch /etc/portage/make.conf
grep -q '^ACCEPT_LICENSE=' /etc/portage/make.conf \
    || echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
grep -q '^FEATURES=.*getbinpkg' /etc/portage/make.conf \
    || echo 'FEATURES="-manifest getbinpkg binpkg-multi-instance binpkg-request-signature parallel-fetch parallel-install"' >> /etc/portage/make.conf
# shellcheck disable=SC2016 # $(nproc) must reach make.conf unevaluated
grep -q '^MAKEOPTS=' /etc/portage/make.conf \
    || echo 'MAKEOPTS="-j$(nproc)"' >> /etc/portage/make.conf
grep -q '^EMERGE_DEFAULT_OPTS=' /etc/portage/make.conf \
    || echo 'EMERGE_DEFAULT_OPTS="--getbinpkg --usepkgonly --binpkg-respect-use=y"' >> /etc/portage/make.conf

# 4. Accept everything from the curated overlay + official binhost
mkdir -p /etc/portage/package.license
echo '*/* *' > /etc/portage/package.license/00-all

mkdir -p /etc/portage/package.accept_keywords
# leave empty: stable-only resolution — the overlay supplies any testing dep
# as a prebuilt binpkg.

# 5. Ebuild overlay for atoms ::gentoo does not package (sys-apps/bootc,
# app-shells/gum, dev-util/just), shipped inside the gentoo-ing-packages image
# so their versions resolve.
if [ -f "${EBUILD_OVERLAY}/metadata/layout.conf" ]; then
    cat > /etc/portage/repos.conf/gentoo-ing-overlay.conf <<EOF
[gentoo-ing-overlay]
location = ${EBUILD_OVERLAY}
sync-type = none
priority = 50
EOF
fi

# 6. Binhosts. The official Gentoo binhost does the heavy lifting — builds run
# from prebuilt binaries, not source. The curated overlay from
# gentoo-ing-packages sits ABOVE it (higher priority wins in binrepos.conf), so
# any package we build there replaces the official version — updated or gap
# packages (bootc, kernel, ...) never get compiled here. A missing binpkg is a
# build error, not a silent source build.
mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/00-gentoo-ing.conf <<EOF
[gentoo-ing]
priority = 10000
location = ${BINHOST_OVERLAY}
verify-signature = false
EOF
cat > /etc/portage/binrepos.conf/gentoo.conf <<EOF
[gentoo]
priority = 9999
sync-uri = ${OFFICIAL_BINHOST}
verify-signature = false
location = /var/cache/binhost/gentoo
EOF
