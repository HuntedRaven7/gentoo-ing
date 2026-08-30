#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# CLEAN_ROOT: filesystem prefix applied to all paths.
# Defaults to "/" so the variable is never empty (satisfies SC2115).
# Set to a temp directory during unit tests.
CLEAN_ROOT="${CLEAN_ROOT:-/}"

# Gentoo build-time residue. The curated binhost (/var/cache/binhost/gentoo-ing)
# is the whole point of this image — it ships so runtime `emerge --getbinpkg`
# works. Everything else from the build is scrap.
rm -rf "${CLEAN_ROOT}/var/cache/distfiles"
rm -rf "${CLEAN_ROOT}/var/cache/binhost/gentoo"
rm -rf "${CLEAN_ROOT}/var/log/portage"
find "${CLEAN_ROOT}/var/tmp" -mindepth 1 -maxdepth 1 -name '._unmerge_*' -exec rm -rf {} + 2>/dev/null || true

rm -rf "${CLEAN_ROOT}/.gitkeep"
# /var: drop build-time subdirs, keep cache (which holds the binhost).
find "${CLEAN_ROOT}/var" -mindepth 1 -maxdepth 1 -type d \! -name cache -exec rm -fr {} \;
# /var/cache: keep only the curated binhost.
mkdir -p "${CLEAN_ROOT}/var/cache"
find "${CLEAN_ROOT}/var/cache" -mindepth 1 -maxdepth 1 -type d \! -name 'gentoo-ing' -exec rm -fr {} \;

# Clear tmpfs-backed runtime directories without deleting the directories
# themselves. Buildah may have bind mounts in these paths during RUN, so
# replacing the mountpoint can fail with EBUSY.
for runtime_dir in tmp boot; do
	mkdir -p "${CLEAN_ROOT:?}/${runtime_dir}"
	find "${CLEAN_ROOT:?}/${runtime_dir}" -mindepth 1 -maxdepth 1 -print0 |
		while IFS= read -r -d '' entry; do
			if mountpoint -q "${entry}" 2>/dev/null; then
				continue
			fi
			rm -rf "${entry}"
		done
done

# /run can contain nested bind mounts created by the build container. Walk it
# depth-first so we can remove image-owned residues while leaving mounted files
# and any directories that still contain them alone.
mkdir -p "${CLEAN_ROOT:?}/run"
find "${CLEAN_ROOT:?}/run" -mindepth 1 -depth -print0 |
	while IFS= read -r -d '' entry; do
		if mountpoint -q "${entry}" 2>/dev/null; then
			continue
		fi
		if [[ -d "${entry}" ]]; then
			rmdir "${entry}" 2>/dev/null || true
			continue
		fi
		rm -f "${entry}"
	done

echo "::endgroup::"