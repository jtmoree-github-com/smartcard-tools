# smartcard-tools

Utilities to assist with use of smartcards.

This repository includes a Debian packaging script that builds a `.deb`
containing:

- [`p11cert.sh`](/home/jt/Documents/smartcard-tools/bin/p11cert.sh)
- a managed `pam-auth-update` profile for `pam_p11`:
  - `Smartcard login (PIN or local password)`

This profile is the supported choice for `sudo` and regular admin auth.

The packaged script is installed to `/usr/bin/p11cert.sh`.

## Build

```bash
chmod +x ./build-deb.sh
./build-deb.sh 0.1.0
```

The package is generated under [`dist/`](/home/jt/Documents/smartcard-tools/dist).

### Debian-native build (dpkg-buildpackage)

```bash
dpkg-buildpackage -us -uc -b
```

This uses the [`debian/`](/home/jt/Documents/smartcard-tools/debian) directory.

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

This project is licensed under the BSD 2-Clause license. See
[`LICENSE`](/home/jt/Documents/smartcard-tools/LICENSE).
