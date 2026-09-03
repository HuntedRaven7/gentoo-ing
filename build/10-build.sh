#!/usr/bin/env bash

set -euo pipefail

# System stage: populate the main image. Adapted from
# HuntedRaven7/blueprint build_files/base/build-gentoo.sh, with strict binary
# consumption (00-gentoo-common.sh): every package below is prebuilt on the
# curated overlay or the official Gentoo binhost, and emerge --usepkgonly fails
# the build rather than compile anything.
#
# Emerges the OSTree/bootc/kernel/dracut/Podman stack and the full GNOME
# desktop (gnome-base/gnome, GDM + NetworkManager) plus the nvidia kernel
# module (x11-drivers/nvidia-drivers, prebuilt by the gentoo-ing-akmods
# factory against this image's exact kernel) — all binaries only — builds the
# initramfs, writes prepare-root.conf (composefs + readonly sysroot) and the
# /var layout bootc requires.

# shellcheck disable=SC1091 # sourced from the ctx stage, absent on the host
source /ctx/build/00-gentoo-common.sh

# System drop-ins (global + gentoo flavor) copied in from the context stage.
cp -avf "/ctx/system_files/global"/. /
cp -avf "/ctx/system_files/gentoo"/. /

PACKAGES=(
    sys-apps/bootc
    sys-kernel/gentoo-kernel-bin
    sys-kernel/linux-firmware
    sys-apps/systemd
    sys-kernel/dracut
    dev-util/ostree
    sys-fs/btrfs-progs
    sys-fs/dosfstools
    sys-fs/e2fsprogs
    sys-fs/xfsprogs
    sys-fs/cryptsetup
    sys-fs/lvm2
    net-misc/openssh
    net-misc/curl
    net-misc/wget
    app-containers/skopeo
    app-containers/podman
    app-admin/sudo
    net-misc/chrony
    app-arch/cpio
    app-arch/xz-utils
    sys-apps/bubblewrap
    dev-libs/glib
    sys-apps/dbus
    sys-apps/shadow
    app-shells/gum
    dev-util/just
    app-misc/jq
    sys-apps/flatpak
    gnome-base/gnome
    gnome-base/gdm
    net-misc/networkmanager
    net-wireless/iwd
    x11-drivers/nvidia-drivers
    app-crypt/tpm2-tss
    net-vpn/tailscale
    gui-apps/wl-clipboard
    media-video/ffmpeg
    media-plugins/gst-plugins-meta
)

emerge --verbose -g --deep --newuse "${PACKAGES[@]}" | tee /tmp/emerge.log
if grep -qE '^\[ebuild ' /tmp/emerge.log; then
    echo "FATAL: a source compile was scheduled; this image is binpkg-only." >&2
    exit 1
fi

# Kernel-module lockstep. Out-of-tree modules (nvidia) are built by the
# gentoo-ing-akmods factory against exactly ONE kernel, recorded in its .kver.
# The kernel we install comes from gentoo-ing-packages, so the two agree only
# when both factories ship the same gentoo-kernel-bin. Fail the build rather
# than ship a module that will never load.
IMAGE_KVER="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)"
AKMODS_KVER="$(cat "${AKMODS_OVERLAY}/.kver" 2>/dev/null || true)"
if [ -n "${AKMODS_KVER}" ] && [ "${AKMODS_KVER}" != "${IMAGE_KVER}" ]; then
    echo "FATAL: gentoo-ing-akmods built module(s) for kernel ${AKMODS_KVER}," >&2
    echo "      but this image's kernel is ${IMAGE_KVER}. A mismatched module" >&2
    echo "      would fail to load on every boot." >&2
    echo "Fix: set config/kernel-pin.txt in gentoo-ing-akmods to ${IMAGE_KVER}," >&2
    echo "     let it rebuild, and re-pin its digest in the Containerfile." >&2
    exit 1
fi

echo "uninitialized" > /etc/machine-id
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
# shellcheck disable=SC2015
sed -i 's|^HOME=.*|HOME=/var/home|' /etc/default/useradd || true

systemctl enable systemd-resolved chronyd sshd NetworkManager gdm
systemctl mask systemd-firstboot.service

# Runtime user-command layer (finpilot-style, Gentoo-native): ujust recipes are
# composed into a single justfile and run through a thin /usr/bin/ujust wrapper.
# The flatpak-preinstall helper installs custom/flatpaks/default.preinstall on
# first boot.
mkdir -p /usr/share/ublue-os/just
cat /ctx/custom/ujust/*.just > /usr/share/ublue-os/just/60-custom.just

cat > /usr/bin/ujust <<'EOF'
#!/usr/bin/bash
# Thin Universal Blue-style ujust wrapper: run the gentoo-ing justfile.
case "${1}" in
    list|--list|-l) exec /usr/bin/just --justfile /usr/share/ublue-os/just/60-custom.just --list ;;
esac
exec /usr/bin/just --justfile /usr/share/ublue-os/just/60-custom.just "$@"
EOF
chmod +x /usr/bin/ujust

cat > /usr/bin/ujust-chsh <<'EOF'
#!/usr/bin/bash
exec /usr/bin/chsh "$@"
EOF
chmod +x /usr/bin/ujust-chsh

printf '%s\n' 'd /usr/share/ublue-os 0755 root root -' > /usr/lib/tmpfiles.d/ublue-os.conf

# Flatpak preinstall on first boot
install -D -m 0644 /ctx/custom/flatpaks/default.preinstall /usr/share/ublue-os/flatpaks/default.preinstall

cat > /usr/lib/systemd/system/flatpak-preinstall.service <<'EOF'
[Unit]
Description=Install Flatpak applications from default.preinstall
ConditionFirstBoot=yes
ConditionPathExists=/usr/share/ublue-os/flatpaks/default.preinstall
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/lib/ublue-os/flatpak-preinstall.sh
TimeoutSec=15min

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/lib/ublue-os/flatpak-preinstall.sh <<'EOF'
#!/usr/bin/bash
set -euo pipefail
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
mapfile -t apps < /usr/share/ublue-os/flatpaks/default.preinstall
for app in "${apps[@]}"; do
    [[ "${app}" =~ ^# || -z "${app}" ]] && continue
    flatpak install -y flathub "${app}" || true
done
EOF
chmod +x /usr/lib/ublue-os/flatpak-preinstall.sh
systemctl enable flatpak-preinstall.service

printf 'L! /etc/resolv.conf - - - - /run/systemd/resolve/stub-resolv.conf\n' > /usr/lib/tmpfiles.d/resolv-conf.conf

KVER=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n 1)
dracut --force --no-hostonly --reproducible --zstd --verbose \
    --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img"

printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' > /usr/lib/ostree/prepare-root.conf

printf 'd /var/home 0755 root root -\nd /var/srv 0755 root root -\nd /var/mnt 0755 root root -\nd /var/opt 0755 root root -\nd /var/usrlocal 0755 root root -\nd /var/roothome 0700 root root -\nd /run/media 0755 root root -\n' > /usr/lib/tmpfiles.d/bootc-base-dirs.conf

# bootc /var layout: move the mutable trees under /var, then relink.
# shellcheck disable=SC2114 # the exploded stage layout is scrapped on purpose
rm -rf /{boot,home,root,srv,mnt,var,usr/local,opt}

mkdir -p /sysroot /boot /usr/lib/ostree /var /var/tmp

ln -sT sysroot/ostree /ostree
ln -sT var/roothome /root
ln -sT var/srv /srv
ln -sT var/mnt /mnt
ln -sT var/opt /opt
ln -sT var/home /home
ln -sT ../var/usrlocal /usr/local
