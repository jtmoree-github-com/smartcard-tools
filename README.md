# smartcard-tools

Utilities to assist with use of smartcards including generating a certificate for use with libpam-p11 and setting up the system to use it.

This repository includes a Debian packaging script that builds a `.deb`
containing:

The certificate helper uses either the legacy OpenSSL `pkcs11` engine or the
modern libp11 PKCS#11 provider, depending on the OpenSSL build on the host.

- [`p11cert.sh`](./bin/p11cert.sh)
- a managed `pam-auth-update` profile for `pam_p11`:
  - `Smartcard login (PIN or local password)`

This profile is the supported choice for `sudo` and regular admin auth.

The packaged script is installed to `/usr/bin/p11cert.sh`.

## Build

Use the repo’s Debian packaging flow:

```bash
chmod +x ./scripts/build-deb.sh
./scripts/build-deb.sh
```

This runs `dpkg-buildpackage -us -uc -b` using the package metadata in [`debian/`](./debian).

The build scripts check for a per-user config file at `$XDG_CONFIG_HOME/smartcard-tools/ppa.env` or `~/.config/smartcard-tools/ppa.env`. That lets each user redirect artifacts to a writable build directory such as a temp folder without editing the project itself:

```bash
mkdir -p ~/.config/smartcard-tools
cat > ~/.config/smartcard-tools/ppa.env <<'EOF'
SMARTCARD_BUILD_OUTPUT_DIR=/tmp/smartcard-tools-build
EOF
```

Then the package output goes into `/tmp/smartcard-tools-build` instead of the repository parent directory.

To bump the next patch version in the changelog before a build:

```bash
./scripts/build-deb.sh --bump
```

### PPA source build and sign

For Launchpad uploads, use the source-package helper and target the Ubuntu series:

```bash
./scripts/build-ppa-source.sh --series resolute
```

This rewrites the first changelog entry into a PPA-compatible version, then runs a signed source build and prints the `dput` command for Launchpad upload.

## Install

```bash
sudo apt install ./dist/smartcard-tools_0.1.0_$(dpkg --print-architecture).deb
```

During install, `postinst` prints:

```bash
pam-auth-update --package --enable smartcard-p11-fallback
```

This enables the shipped smartcard profile with local password fallback.

## License

This project is licensed under the MIT license. See
[`LICENSE`](./LICENSE).
