#!/usr/bin/env bash

set -euo pipefail

# Shared Gentoo bootstrap for gentoo-ing. Sourced by 10-build.sh.
# Idempotent: safe to run more than once in a build.
#
# The image NEVER compiles a package. Portage is wired for strict binary
# consumption: --usepkgonly (hard failure if a binpkg is missing from the
# overlay — never a source fallback).
#
# The ONLY source of packages is the gentoo-ing-packages overlay (priority
# 10000): the factory mirrors the official binhost's set and compiles the
# gaps, so this image never talks to distfiles.gentoo.org.
#
# Configures:
#   - Portage tree (fresh webrsync each build so ebuild metadata covers the
#     overlay's current versions)
#   - profile symlink
#   - make.conf defaults (stable keywords, getbinpkg + usepkgonly, nproc -j)
#   - package.license / package.accept_keywords drop-ins
#   - ebuild overlay for atoms ::gentoo lacks (bootc/gum/just) from the binhost image
#   - binrepos.conf: the gentoo-ing overlay (priority 10000), sole binrepo

BRANCH_PROFILE="default/linux/amd64/23.0/systemd"
BINHOST_OVERLAY="/var/cache/binhost/gentoo-ing"
EBUILD_OVERLAY="/var/cache/binhost/gentoo-ing-ebuilds"

# 1. Portage tree. Always pull a fresh snapshot: the overlay publishes current
#    stable versions and the stage3 tree could lag them, which would make
#    resolution fail (no matching ebuild) even though the binary is present.
emerge-webrsync || emerge --sync

# 2. Profile
rm -f /etc/portage/make.profile
ln -s "/var/db/repos/gentoo/profiles/${BRANCH_PROFILE}" /etc/portage/make.profile

# 3. make.conf (idempotent appends). Stable keywords only: everything must
# resolve as a binpkg on the overlay (10000) or the official binhost (9999).
touch /etc/portage/make.conf
grep -q '^ACCEPT_LICENSE=' /etc/portage/make.conf \
    || echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf
grep -q '^FEATURES=.*getbinpkg' /etc/portage/make.conf \
    || echo 'FEATURES="-manifest getbinpkg binpkg-multi-instance parallel-fetch parallel-install"' >> /etc/portage/make.conf
NPROC=$(nproc)
grep -q '^MAKEOPTS=' /etc/portage/make.conf \
    || echo "MAKEOPTS=\"-j${NPROC}\"" >> /etc/portage/make.conf
grep -q '^EMERGE_DEFAULT_OPTS=' /etc/portage/make.conf \
    || echo 'EMERGE_DEFAULT_OPTS="--getbinpkg --usepkgonly --binpkg-respect-use=y"' >> /etc/portage/make.conf

# 4. Accept everything from the curated overlay + official binhost
mkdir -p /etc/portage/package.license
echo '*/* *' > /etc/portage/package.license/00-all

mkdir -p /etc/portage/package.accept_keywords
# leave empty: stable-only resolution — the overlay supplies any testing dep
# as a prebuilt binpkg.

# gentoo-kernel-bin generates its initramfs via installkernel[+dracut]; the
# overlay builds it that way, so the binpkg matches --binpkg-respect-use=y.
mkdir -p /etc/portage/package.use
echo 'sys-kernel/installkernel dracut' > /etc/portage/package.use/installkernel

# 5. Ebuild overlay for atoms ::gentoo does not package (sys-apps/bootc,
# app-shells/gum, dev-util/just), shipped inside the gentoo-ing-packages image
# so their versions resolve. Section name == repo_name (profiles/repo_name).
if [ -f "${EBUILD_OVERLAY}/metadata/layout.conf" ]; then
    cat > /etc/portage/repos.conf/gentoo-ing-ebuilds.conf <<EOF
[gentoo-ing-ebuilds]
location = ${EBUILD_OVERLAY}
priority = 50
EOF
fi

# 6. Binhost. The gentoo-ing-packages overlay is the consumer's ONLY binrepo:
# it mirrors the full official binhost set (same USE, same profile) and
# compiles the atoms the official host does not ship, so every package --
# atoms AND dependency closure -- resolves as a local binpkg. A missing binpkg
# is a build error, not a silent source build. verify-signature=false: the
# overlay bins are unsigned (our own factory, sealed supply chain).
mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/00-gentoo-ing.conf <<EOF
[gentoo-ing]
priority = 10000
location = ${BINHOST_OVERLAY}
verify-signature = false
EOF
