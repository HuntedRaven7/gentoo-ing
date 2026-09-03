# Build Scripts

This directory contains build scripts used during image creation. The default Containerfile explicitly runs the required scripts; extra scripts must be explicitly added to the Containerfile.

## How It Works

Scripts are named with a number prefix (e.g., `10-build.sh`, `20-extra-packages.sh`) and run in ascending order during the container build process.

**Most scripts should NOT be custom here.** On Gentoo the image installs everything with `emerge --getbinpkg --usepkgonly` from the configured binhosts — a strict binary diet. The main repo **never compiles a package**: the curated `gentoo-ing` overlay (`gentoo-ing-packages`) supplies anything the official Gentoo binhost does not. Packages that need building from source (bootc, kernel, firmware, gap tools) are prebuilt in `gentoo-ing-packages` and consumed as binpkgs here; a missing binpkg fails the build rather than triggering a source compile.

## Included Scripts

- **`00-gentoo-common.sh`** - Shared bootstrap: portage tree, profile symlink, make.conf defaults (getbinpkg + usepkgonly, stable keywords), license drop-in, ebuild overlay import for atoms `::gentoo` lacks, binrepos.conf (curated overlay priority 10000 + module overlay 10100 + official binhost 9999), and the nvidia `~amd64`/dist-kernel overrides matching the gentoo-ing-akmods maker
- **`00-image-info.sh`** - Writes `/usr/share/ublue-os/image-info.json` and branding into `/usr/lib/os-release`
- **`10-build.sh`** - Main build: emerges the bootc/OSTree/Podman/kernel stack as binaries, builds the initramfs, writes prepare-root.conf, lays out `/var`
- **`clean-stage.sh`** - Removes build residue before linting (keeps the binhost)

## Example Scripts

- **`20-extra-packages.sh.example`** - Example showing how to install extra packages with `emerge --getbinpkg`
- **`30-desktop.sh.example`** - Example showing how to add a desktop environment (profile changes warn: do early)
- **`40-nvidia.sh.example`** - Example showing how to add NVIDIA `nvidia-drivers` for `gentoo-kernel-bin`

To use an example script:
1. Rename it to remove the `.example` extension (for example, `mv build/20-extra-packages.sh.example build/20-extra-packages.sh`).
2. Add the standard `RUN` block below after the `10-build.sh` block in `Containerfile`, replacing `NN-example.sh` with the renamed script.
3. Run `just build`.

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build/NN-example.sh
```

For anything the binhosts do not carry, source builds are CPU-bound on GH Actions — and deliberately forbidden in this repo. Prebuild those packages in the `gentoo-ing-packages` factory instead.

## Creating Your Own Scripts

Create numbered scripts for different purposes:

```bash
# 10-build.sh - Base system (already exists)
# 20-drivers.sh - Hardware drivers
# 30-development.sh - Development tools
# 40-gaming.sh - Gaming software
# 50-cleanup.sh - Final cleanup tasks
```

### Script Template

```bash
#!/usr/bin/env bash
set -oue pipefail

echo "Running custom setup..."
# Your commands here
```

### Best Practices

- **Use descriptive names**: `40-nvidia.sh` is better than `40-stuff.sh`
- **One purpose per script**: Easier to debug and maintain
- **Clean up after yourself**: Remove temporary files and disable temporary repos
- **Test incrementally**: Add one script at a time and test builds
- **Comment your code**: Future you will thank present you

### Disabling Scripts

To disable an activated script, remove its corresponding `RUN` block from `Containerfile` and rename it back to `.example` (or remove it).

## Execution Order

The template runs scripts explicitly, rather than automatically discovering files by prefix. Place extra script blocks after `10-build.sh` and before `clean-stage.sh`. Use numbered names to communicate the intended order.

## Notes

- Scripts run as root during build
- Build context is available at `/ctx`
- Use `emerge --getbinpkg --usepkgonly` for package management; write overrides to `/etc/portage` drop-ins (make.conf, package.use, package.accept_keywords, binrepos.conf)
- Keep `00-gentoo-common.sh` first in any ordering of build steps that needs portage
