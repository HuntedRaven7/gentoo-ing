#!/usr/bin/env bash

set -euo pipefail

# Shared Gentoo bootstrap for gentoo-ing. Sourced by 10-build.sh.
# Idempotent: safe to run more than once in a build.
#
# The image NEVER compiles a package. Portage is wired for strict binary
# consumption: --usepkgonly (hard failure if a binpkg is missing from the
# overlay — never a source fallback).
#
# Packages come from TWO factories, both copied into the image by digest:
#   - gentoo-ing-packages (priority 10000): every normal atom — the mirror of
#     the official binhost set plus the compiled gaps (GNOME desktop, kernel,
#     firmware, bootc, podman, ...).
#   - gentoo-ing-akmods     (priority 10100): out-of-tree kernel modules
#     (x11-drivers/nvidia-drivers) prebuilt against this image's exact kernel.
#     Modules are version-hostage to their kernel, so they can only ship as a
#     binpkg from a kernel-lockstep factory; 10-build.sh gates the build on the
#     akmods .kver matching the installed kernel.
#
# Configures:
#   - Portage tree (fresh webrsync each build so ebuild metadata covers the
#     overlay's current versions)
#   - profile symlink (gnome desktop/systemd — must match the gentoo-ing-packages
#     and gentoo-ing-akmods makers whose overlays this consumer drains, so USE
#     line up)
#   - make.conf defaults (stable keywords, getbinpkg + usepkgonly, nproc -j)
#   - package.license / package.accept_keywords drop-ins
#   - ebuild overlay for atoms ::gentoo lacks (bootc/gum/just) from the binhost image
#   - binrepos.conf: the gentoo-ing overlay (priority 10000) PLUS the
#     gentoo-ing-akmods module overlay (priority 10100)

BRANCH_PROFILE="default/linux/amd64/23.0/desktop/gnome/systemd"
BINHOST_OVERLAY="/var/cache/binhost/gentoo-ing"
EBUILD_OVERLAY="/var/cache/binhost/gentoo-ing-ebuilds"
AKMODS_OVERLAY="/var/cache/binhost/gentoo-ing-akmods"

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
# Exception: nvidia-drivers is built as ~amd64 by the gentoo-ing-akmods maker
# (to ship the LATEST NVIDIA driver). Accept the same keyword here so the
# exactly-matching binpkg resolves; no source fallback is involved.
echo 'x11-drivers/nvidia-drivers ~amd64' > /etc/portage/package.accept_keywords/nvidia

# gentoo-kernel-bin generates its initramfs via installkernel[+dracut]; the
# overlay builds it that way, so the binpkg matches --binpkg-respect-use=y.
# The nvidia-drivers module must ALSO request exactly the flags its
# gentoo-ing-akmods binpkg carries: dist-kernel (rebuild against the installed
# binary kernel). Any USE divergence is rejected by --binpkg-respect-use=y.
mkdir -p /etc/portage/package.use
echo 'sys-kernel/installkernel dracut' > /etc/portage/package.use/installkernel
echo 'x11-drivers/nvidia-drivers dist-kernel' > /etc/portage/package.use/nvidia

# Align expected USE with the official binhost's builds where the bootc/podman
# closure hard-requires flags the official binpkg carries (containers-common ->
# net-firewall/iptables[nftables]; GNOME -> net-fs/samba -> ngtcp2[gnutls]).
# --binpkg-respect-use=y otherwise rejects the official binary and the sealed
# closure cannot resolve.
cat > /etc/portage/package.use/respect-use <<EOF
net-libs/ngtcp2 gnutls
net-firewall/iptables nftables
EOF

# 5. Ebuild overlay for atoms ::gentoo does not package (sys-apps/bootc,
# app-shells/gum, dev-util/just), shipped inside the gentoo-ing-packages image
# so their versions resolve. Section name == repo_name (profiles/repo_name).
if [ -f "${EBUILD_OVERLAY}/metadata/layout.conf" ]; then
    mkdir -p /etc/portage/repos.conf
    cat > /etc/portage/repos.conf/gentoo-ing-ebuilds.conf <<EOF
[gentoo-ing-ebuilds]
location = ${EBUILD_OVERLAY}
priority = 50
EOF
fi

# 6. Binhosts. The gentoo-ing-packages overlay is the base binrepo: it mirrors
# the full official binhost set (same USE, same profile) and compiles the atoms
# the official host does not ship, so every normal package -- atoms AND
# dependency closure -- resolves as a local binpkg. The gentoo-ing-akmods
# overlay sits ABOVE it (priority 10100) and only ships the out-of-tree kernel
# modules (plus their closure), prebuilt against this image's exact kernel;
# its pruned atoms (kernel, installkernel, toolchains) resolve from gentoo-ing.
# A missing binpkg is a build error, not a silent source build.
# verify-signature=false: our own factories, sealed supply chain (unsigned).
mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/00-gentoo-ing.conf <<EOF
[gentoo-ing]
priority = 10000
location = ${BINHOST_OVERLAY}
sync-uri = file://${BINHOST_OVERLAY}
verify-signature = false
EOF
cat > /etc/portage/binrepos.conf/10-gentoo-ing-akmods.conf <<EOF
[gentoo-ing-akmods]
priority = 10100
location = ${AKMODS_OVERLAY}
sync-uri = file://${AKMODS_OVERLAY}
verify-signature = false
EOF
