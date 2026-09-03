# gentoo-ing

A template for building custom bootc operating system images based on the lessons from [Universal Blue](https://universal-blue.org/) and [Bluefin](https://projectbluefin.io). It is designed to be used manually, but is optimized to be bootstraped by GitHub Copilot. After set up you'll have your own custom Linux.

This template uses the **multi-stage build architecture** from @projectbluefin/distroless, combining resources from multiple OCI containers for modularity and maintainability. See the [Architecture](#architecture) section below for details.

**Unlike previous templates, you are not modifying Bluefin and making changes.**: You are assembling your own Bluefin in the same exact way that Bluefin, Aurora, and Bluefin LTS are built. This is way more flexible and better for everyone since the image-agnostic and desktop things we love about Bluefin lives in @projectbluefin/common.

Instead, you create your own OS repository based on this template, allowing full customization while leveraging Bluefin's robust build system and shared components.

> Be the one who moves, not the one who is moved.

## What Makes this Raptor Different?

This image is a **Gentoo** system, not a Fedora desktop. It abandons the RPM world (dnf5, COPR, rpm-ostree, Homebrew) for Portage on `gentoo/stage3:systemd`, while keeping the finpilot/Universal Blue bootc build system (multi-stage Containerfile, keyless signing, Renovate, main→stable promotion).

### Package Delivery (the big one)

- **Official Gentoo binhost** (`distfiles.gentoo.org`, amd64/23.0) does the heavy lifting: most packages are installed prebuilt with `--getbinpkg --usepkgonly`, so this repo **never compiles anything** — a missing binpkg fails the build rather than falling back to a source build.
- **`HuntedRaven7/gentoo-ing-packages` binhost overlay** sits above the official host (priority 10000 vs 9999). It carries the packages the official host lacks — `bootc`, the kernel, firmware, `skopeo`, `flatpak`, `iwd`, `gum`, `just`, `jq` — as prebuilt binpkgs, plus a tiny ebuild overlay for the atoms `::gentoo` doesn't package at all (`bootc`, `gum`, `just`). Those gaps are compiled once in the factory's GH Actions, then consumed as binaries here.
- Config lives in `build/00-gentoo-common.sh` (binrepos.conf + make.conf) and `build/10-build.sh` (the PACKAGES array).

### Added Packages (Build-time)

- **Kernel/OSTree stack**: `gentoo-kernel-bin`, `linux-firmware`, `dracut`, `ostree`, `systemd`, and `bootc` — all as binpkgs from the overlay/official host
- **Container host**: `podman`, `skopeo`, `bubblewrap`, `btrfs-progs` + filesystem tools, `systemd-networkd`/`resolved`, `iwd`
- **System**: `openssh`, `sudo`, `chrony`, `shadow`, `vim`/`tmux` (via the binhost overlay)

### Boot/OSTree Configuration

- composefs + readonly sysroot (`prepare-root.conf`), hostonly=no zstd initramfs built per-kernel by dracut
- `/var` overlay layout (home, roothome, srv, mnt, opt, usrlocal) for bootc
- Enabled: `sshd`, `iwd`, `chronyd`, `systemd-networkd`, `systemd-resolved`; masked: `systemd-firstboot`

### Removed vs Finpilot

- Fedora base image, dnf5/RPM tooling, COPR helpers, Homebrew runtime (Brewfiles + ujust), `@projectbluefin/common` desktop config

### Configuration Changes

- Stable keywords only (matches what the binhosts prebuilt), accept-all licenses, `FEATURES=getbinpkg binpkg-multi-instance`, nproc builds
- Runtime software is installed via Flatpak or containers; native packages are baked in at build time (the rootfs is read-only under bootc)

_Last updated: 2026-08-30_

> Update this section whenever you add or remove packages, apps, or configuration. It is what tells users how your image differs from the base.

## Guided Copilot Mode

This template works best with **phased prompts** that let Copilot bootstrap your image in three stages.

### Phase 1 — Bootstrap

Use this prompt first to get your fork building:

```
Bootstrap a new custom OS from @projectbluefin/finpilot. Name it after this repository. Use the `finpilot-onboarding` skill first, then:
1. Rename `finpilot` in the 7 required files
2. Enable GitHub Actions and set RENOVATE_TOKEN (classic PAT with `repo` +
   `workflow` scopes, or a fine-grained token with **Dependabot alerts:
   Read-only** and **Contents: Read and write**)
3. Configure branch protection for `main` with `validate` as a required status check
4. Enable auto-merge
5. Trigger the first green build on `main`
6. Add the "What Makes this Raptor Different" section to README.md (with placeholders)
```

### Phase 2 — Customize

Once the first build is green, use this prompt to add packages:

```
Use the `finpilot-packages` and `finpilot-custom` skills, then:
1. Add one system package to the image in `build/10-build.sh` (or the gentoo-ing-packages overlay)
2. Add one GUI app to `custom/flatpaks/default.preinstall`
3. Add shortcuts in `custom/ujust/custom-apps.just` to install them
4. Update the README "What Makes this Raptor Different" section with the new entries
5. Run `just build && just build-qcow2 && just run-vm-qcow2` to verify locally
6. Open a PR and merge once `validate` passes
```

### Phase 3 — Production

When you are ready for production, use this prompt to harden the setup:

```
Use the `finpilot-maintain` and `finpilot-ci` skills, then:
1. Verify keyless image signing works: cosign verify --certificate-identity-regexp="https://github.com/USER/REPO/.github/workflows/" --certificate-oidc-issuer="https://token.actions.githubusercontent.com" ghcr.io/USER/REPO:stable
2. Follow the maintenance schedule in the `finpilot-maintain` skill
```

## What's Included

### Build System

- Automated builds via GitHub Actions on every commit
- Self-hosted Renovate for automated dependency updates
- Automatic cleanup of old images (90+ days) to keep it tidy
- Pull request workflow - test changes before merging to main
  - PRs build and validate before merge
  - `main` builds `:stable-testing`; merging the auto-opened promotion PR to `stable` publishes `:stable`
- Validates your files on pull requests so you never break a build:
  - Justfile, ShellCheck, Renovate config, and it'll even check to make sure the flatpak you add exists on Flathub
- Production Grade Features
  - Container signing with keyless OIDC

### Gentoo Binhost Integration

- Curated binhost overlay (`HuntedRaven7/gentoo-ing-packages`) consumed by `COPY --from=` and pinned by digest; seeds and custom builds land in `packages/` there
- Module binhost overlay (`HuntedRaven7/gentoo-ing-akmods`, priority 10100) prebuilds the out-of-tree nvidia kernel module against this image's exact kernel; a `.kver` lockstep gate in `10-build.sh` fails the build if the two ever disagree
- Official Gentoo binhost as the load-bearing source — `emerge --getbinpkg` installs prebuilt binaries, so CI compiles only what both hosts miss
- See [build/00-gentoo-common.sh](build/00-gentoo-common.sh) for the binrepos wiring

### Flatpak Support

- Ship your favorite flatpaks
- Automatically installed on first boot after user setup
- See [custom/flatpaks/README.md](custom/flatpaks/README.md) for details

### ujust Commands

- User-friendly command shortcuts via `ujust`
- Pre-configured examples for app installation and system maintenance for you to customize
- See [custom/ujust/README.md](custom/ujust/README.md) for details

### Build Scripts

- Modular numbered scripts (00-common, 10-build, clean-stage) run in order
- Example scripts included for extra packages, desktops, and NVIDIA
- Gentoo-native (emerge --getbinpkg, portage drop-ins); no COPR helpers
- See [build/README.md](build/README.md) for details

## Quick Start

### 1. Create Your Repository

Click "Use this template" to create a new repository from this template.

### 2. Rename the Project

Important: Change `finpilot` to your repository name in these 7 files:

1. `Containerfile` (`# Name:` comment and `ARG IMAGE_NAME`): `# Name: your-repo-name`
2. `Justfile` (`export IMAGE_NAME := env("IMAGE_NAME", ...)`): `your-repo-name`
3. `README.md` (title): `# your-repo-name`
4. `artifacthub-repo.yml` (`repositoryID`): `repositoryID: your-repo-name`
5. `custom/ujust/README.md` (bootc switch example): `localhost/your-repo-name:stable`
6. `.github/workflows/clean.yml` (`packages`): `packages: your-repo-name`
7. `iso/iso.toml` (bootc switch URL): `ghcr.io/YOUR_USERNAME/your-repo-name:stable`

### 3. Enable GitHub Actions

- Go to the "Actions" tab in your repository
- Click "I understand my workflows, go ahead and enable them"

Your first build will start automatically!

Note: Images are signed automatically with keyless OIDC signing — no keys or secrets to configure. See "Image Signing" below for details.

### 4. Enable Renovate (Required)

Renovate automatically updates dependencies and GitHub Actions (including workflow files). This template uses a self-hosted Renovate runner via `projectbluefin/actions`.

**One-time setup:**

1. Go to GitHub → Settings → Developer settings → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token (classic)**
3. Set a note like `renovate-finpilot`
4. Select scopes: **`repo`** (full control) and **`workflow`** (update workflows)
5. Click **Generate token** and copy the value
6. Go to your repository → Settings → Secrets and variables → Actions
7. Add a new secret: **`RENOVATE_TOKEN`** (paste the token value)
8. Enable **Settings → General → Pull Requests → Allow auto-merge** so Renovate can merge low-risk updates after checks pass
9. **Configure branch protection for `main`** (required for automerge to work):
   - Go to Settings → Branches → Add rule
   - Set **Branch name pattern** to `main`
   - Enable **"Require a pull request before merging"**
   - Enable **"Require status checks to pass before merging"**
   - Add `validate` as a required status check
   - Enable **"Require branches to be up to date before merging"** (recommended)

Renovate will run every 6 hours and on config changes. It pins GitHub Actions to SHAs and updates tracked image digests automatically.

### 5. Maintain Your Template

Repositories created with **Use this template** are independent repositories.
Renovate keeps pinned dependencies current, but it does not copy arbitrary
changes from finpilot's `Containerfile`, build scripts, or workflows.

For a template improvement or build-system change, file a scoped
[finpilot issue](https://github.com/projectbluefin/finpilot/issues/new/choose)
instead of merging unrelated histories:

- Select **"Opt in to a clanker working on my issue"** when creating your own
  issue to send it directly to `3-clanker-queue`.
- Maintainers can move any accepted issue to `3-clanker-queue`.
- A Hive-connected agent opens a focused pull request; humans review and merge
  it.

Review and port structural changes into your custom image deliberately through
a pull request. This preserves your image-specific changes while sharing
improvements with every future finpilot user.

### 6. Customize Your Image

Choose your base image in `Containerfile` (the `FROM` line):

```dockerfile
ARG GENTOO_IMAGE="gentoo/stage3:systemd"
FROM ${GENTOO_IMAGE} AS system
```

Add your packages in `build/10-build.sh`:

```bash
emerge --getbinpkg --usepkgonly --verbose sys-apps/foo
```

Customize your apps:

- Add Flatpaks in `custom/flatpaks/` ([guide](custom/flatpaks/README.md))
- Add ujust commands in `custom/ujust/` ([guide](custom/ujust/README.md))
- Prefer seeding updated packages into the `gentoo-ing-packages` overlay instead of compiling in CI

### 7. Development Workflow

All changes should be made via pull requests:

1. Open a pull request on GitHub with the change you want.
2. The PR will automatically trigger:
   - Build validation
   - Brewfile, Flatpak, Justfile, and shellcheck validation
   - Test image build
3. Once checks pass, merge the PR
4. Merging to `main` publishes a `:stable-testing` image; the promotion PR it opens publishes `:stable` when merged

### 8. Promote to Stable

The template uses a two-branch release model:

| Branch   | Image tag                        | Audience                       |
| -------- | -------------------------------- | ------------------------------ |
| `main`   | `:stable-testing` (+ `:testing`) | Testers and release candidates |
| `stable` | `:stable`                        | Production systems             |

When `stable` differs from `main`, the [`promote-main-to-stable`](.github/workflows/promote-main-to-stable.yml) workflow opens a squash promotion PR automatically, enables auto-merge, and runs a release gate that verifies image signatures on `:testing`. Direct pushes to `stable` are not part of the workflow; hotfixes made there are merged back into `main` by [`sync-stable-to-main`](.github/workflows/sync-stable-to-main.yml).

For the automated promotion PR to open, your repository needs:

- An **organization-owned repo with a `maintainers` team** — the workflow requests review from `<owner>/maintainers` when creating the PR. Personal-account forks can replace `.github/workflows/promote-main-to-stable.yml` with a local version that skips reviewer requests.
- Branch protection on `stable`: **0 required approvals** means fully automatic promotion; **1 approval** means review, then auto-merge.
- The release gate is advisory by default — make the promote workflow a required check on `stable` if a `release/blocked` result should block merging.

### 9. Deploy Your Image

Test the candidate from `main` first:

```bash
sudo bootc switch --transport registry ghcr.io/your-username/your-repo-name:stable-testing
sudo systemctl reboot
```

After merging the promotion PR, deploy production:

```bash
sudo bootc switch --transport registry ghcr.io/your-username/your-repo-name:stable
sudo systemctl reboot
```

## Image Signing

Images are signed automatically with **keyless OIDC signing** via Cosign and GitHub Actions. No manual key generation, `cosign.key`, or `cosign.pub` files are required — the signature is created using GitHub's OIDC token via Fulcio during each build.

### Why Sign Images?

- Verify image authenticity and integrity
- Prevent tampering and supply chain attacks
- Required for some enterprise/security-focused deployments
- Industry best practice for production images
- **Required for promotion**: the `main → stable` release gate verifies signatures on `:testing` and blocks promotion of unsigned images

### Verify a Signed Image

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/your-username/your-repo-name/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/your-username/your-repo-name:stable
```

### Disabling Signing (Not Recommended)

To disable, comment out the `Sign and publish` step in `.github/workflows/build-image.yml`. Be aware that unsigned images will fail the promotion release gate, so `main → stable` promotions will report `release/blocked` until signing is re-enabled.

## Love Your Image? Let's Go to Production

Ready to take your custom OS to production? Enable these features for enhanced security, reliability, and performance:

### Production Checklist

- [ ] **Verify Image Signing**
  - Provides cryptographic verification of your images
  - Prevents tampering and ensures authenticity
  - Uses keyless OIDC signing via GitHub Actions — no keys or secrets required
  - Verify it works with the `cosign verify` command in the "Image Signing" section above

- [ ] **Enable Image Rechunking** (Recommended)
  - Optimizes bootc image layers for better update performance
  - Improves download resumability with evenly sized layers
  - Set `ENABLE_RECHUNKING: "true"` in `.github/workflows/build-image.yml`
  - Uses OCI-native chunkah; `/usr/libexec/bootc-base-imagectl` is not required
  - Status: **Not enabled by default** (optional optimization)

#### Adding Image Rechunking

The old rechunking recipe used `/usr/libexec/bootc-base-imagectl`, which is absent from many Universal Blue images. Do not copy that recipe or install a legacy rechunker: its layer format is not a safe migration path to the current implementation.

Finpilot instead uses the OCI-native [`bootc-build/chunka`](https://github.com/projectbluefin/actions/tree/main/bootc-build/chunka) action. The action runs chunkah from a pinned container and replaces the locally built image before the existing tag and push steps. The default Fedora Silverblue-based finpilot image is RPM-based, so chunkah can discover components from its RPM database without `bootc-base-imagectl`.

To enable it, change the workflow environment value:

```yaml
env:
  ENABLE_RECHUNKING: "true"
  RECHUNK_MAX_LAYERS: "128"
```

Rechunking runs only for publish builds, not pull requests. It requires additional runner time and temporary storage. Keep `ENABLE_RECHUNKING` set to `"false"` if those costs are more important than smaller OTA deltas.

**Custom base images:** This switch is supported for the template's default RPM-based image. BuildStream-produced images strip the component xattrs chunkah needs and require an `xattr-manifest`; changing to one of those images is not a one-line setup. See the action's `xattr-manifest` input before replacing the default base.

**Optional package cadence:** Basic rechunking does not require package cadence data. Advanced deployments can run [`bootc-build/apply-pkg-intervals`](https://github.com/projectbluefin/actions/tree/main/bootc-build/apply-pkg-intervals) before rechunking and maintain `files/pkg-intervals.tsv` with the reusable package-cadence workflow. That workflow requires a repository GitHub App ID and private key, so configure it separately rather than treating it as part of basic enablement.

**References:**

- [chunkah](https://github.com/coreos/chunkah)
- [projectbluefin/actions rechunking](https://github.com/projectbluefin/actions/tree/main/bootc-build/chunka)
- [bootc documentation](https://containers.github.io/bootc/)

### After Enabling Production Features

Your workflow will:

- Sign all images using keyless OIDC signing
- Provide cryptographic proof of authenticity via SLSA build provenance attestation

## Detailed Guides

- [Binhost / Package Delivery](build/00-gentoo-common.sh) - binrepos + make.conf wiring
- [Flatpak Preinstall](custom/flatpaks/README.md) - GUI application setup
- [ujust Commands](custom/ujust/README.md) - User convenience commands
- [Build Scripts](build/README.md) - Build-time customization

## Architecture

This template follows the **multi-stage build architecture** from @projectbluefin/distroless, as documented in the [Bluefin Contributing Guide](https://docs.projectbluefin.io/contributing/).

### Multi-Stage Build Pattern

**Stage 1: Context (ctx)** - Combines resources from a single source:

- Local build scripts (`/build`)
- Local system drop-ins (`/system_files`)
- Local custom files (`/custom`)

**Stage 1: Binhost (pkgs)** - The curated binary package host:

- `ghcr.io/HuntedRaven7/gentoo-ing-packages` - data-only image consumed by `COPY --from=` and pinned by digest (Renovate keeps the pin current). Contains the binpkg tree under `/var/cache/binhost/gentoo-ing` *and* the ebuild overlay under `/var/cache/binhost/gentoo-ing-ebuilds`

**Stage 2: System** - The bootable image:

- `gentoo/stage3:systemd` base, copies in the binhost + ebuild overlay, emerges the bootc/OSTree/Podman/kernel stack with `--getbinpkg --usepkgonly` (strict binary diet — a missing binpkg is a build error, never a source build), builds the initramfs, writes `prepare-root.conf`, lints with `bootc container lint`

### Benefits of This Architecture

- **Modularity**: Compose your image from reusable OCI containers
- **Maintainability**: Update the binhost overlay independently of the image
- **Reproducibility**: Renovate automatically updates OCI tags to SHA digests
- **Binary-cache economics**: prebuilt packages from the official binhost + the factory-built overlay keep GH Actions cold — nothing is compiled in this repo

### OCI Container Resources

The template imports files from these OCI containers at build time:

```dockerfile
FROM ghcr.io/HuntedRaven7/gentoo-ing-packages:latest AS pkgs
FROM gentoo/stage3:systemd AS system
COPY --from=pkgs /var/cache/binhost/gentoo-ing /var/cache/binhost/gentoo-ing
COPY --from=pkgs /var/cache/binhost/gentoo-ing-ebuilds /var/cache/binhost/gentoo-ing-ebuilds
```

**Note**: Renovate automatically updates `:latest` tags to SHA digests for reproducible builds.

## Local Testing

Test your changes before pushing:

```bash
just build              # Build container image
just build-qcow2        # Build VM disk image
just run-vm-qcow2       # Test in browser-based VM
```

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion](https://github.com/bootc-dev/bootc/discussions)

## Learn More

- [Universal Blue Documentation](https://universal-blue.org/)
- [bootc Documentation](https://containers.github.io/bootc/)
- [Video Tutorial by TesterTech](https://www.youtube.com/watch?v=IxBl11Zmq5wE)

## Security

This template provides security features for production use:

- Image signing with keyless OIDC cosign for cryptographic verification
- Automated security updates via Renovate
- Build provenance tracking

Signing and Renovate run automatically; see the "Love Your Image? Let's Go to Production" section above for optional production hardening like rechunking.

## Troubleshooting

### Flatpaks not preinstalled after bootc switch (fixes #49)

Flatpaks are installed on first boot via `flatpak-preinstall.service`, not during `bootc switch`. Ensure:

- Internet is available on first boot
- `flatpak-preinstall.service` completes (`systemctl status flatpak-preinstall.service`)
- Wait until the service finishes before checking for flatpaks

### flatpak-preinstall errors about adw-gtk3 runtimes (fixes #30)

The `adw-gtk3-dark` runtime is not available on Flathub. These warnings are cosmetic and do not prevent other flatpaks from installing. To suppress, remove `adw-gtk3-dark` from your flatpak list in `custom/flatpaks/`.

### Host packages missing after bootc switch

The rootfs is read-only under bootc, so `emerge` cannot install into `/usr` at runtime. Add native packages to the `PACKAGES` array in `build/10-build.sh`, or seed them into the `gentoo-ing-packages` overlay, then rebuild. Runtime software goes in Flatpaks or containers.
