# Building smartcard-tools

This document describes how to build and package smartcard-tools.

## Prerequisites

Building smartcard-tools requires the following tools and libraries:
- `dpkg-dev` and associated Debian packaging tools
- `debhelper-compat (>= 13)`
- Standard build utilities (`make`, `gcc`, etc.)

## Building a Debian Package

### Quick Build

To build a local Debian package:

```bash
chmod +x ./scripts/build-deb.sh
./scripts/build-deb.sh
```

This runs `dpkg-buildpackage -us -uc -b` using the package metadata in [`debian/`](./debian).

### Build Output Configuration

The build scripts check for a per-user config file at:
- `$XDG_CONFIG_HOME/smartcard-tools/ppa.env`, or
- `~/.config/smartcard-tools/ppa.env`

This allows you to redirect artifacts to a writable directory without editing the project:

```bash
mkdir -p ~/.config/smartcard-tools
cat > ~/.config/smartcard-tools/ppa.env <<'EOF'
SMARTCARD_BUILD_OUTPUT_DIR=/tmp/smartcard-tools-build
EOF
```

The package output will then go into `/tmp/smartcard-tools-build` instead of the repository parent directory.

### Bumping the Version

To bump the next patch version in the changelog before building:

```bash
./scripts/build-deb.sh --bump
```

This automatically increments the patch version in `debian/changelog`.

## PPA Source Package

For uploading to Launchpad PPA, use the source-package builder and specify the target Ubuntu series:

```bash
./scripts/build-ppa-source.sh --series resolute
```

This script:
1. Rewrites the first changelog entry into a PPA-compatible version
2. Runs a signed source build
3. Prints the `dput` command for uploading to Launchpad

**Available Ubuntu series:** noble, jammy, and others supported by your PPA.

## Installation

After building, install the package with:

```bash
sudo apt install ./dist/smartcard-tools_0.1.0_$(dpkg --print-architecture).deb
```

During installation, the postinst script will run:

```bash
pam-auth-update --package --enable smartcard-p11-fallback
```

This enables the shipped smartcard profile with local password fallback for authentication.

## Debugging the Build

To see the build scripts available:

```bash
ls -la scripts/build*.sh
```

The main build scripts are:
- `build-deb.sh` - Builds a local .deb package
- `build-ppa-source.sh` - Builds a signed source package for Launchpad
- `build-deps.sh` - Installs build dependencies
