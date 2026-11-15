# smartcard-tools

Utilities to assist with use of smartcards, including:

- **`p11cert.sh`** – Generate short-lived self-signed certificates from PKCS#11 private keys (smartcard keys) for use with `libpam-p11`
- **PAM profile** – A managed `pam-auth-update` profile for `pam_p11` with local password fallback support

These tools enable smartcard-based authentication for `sudo` and general system login with a seamless fallback to local passwords.

## Features

- Automatic PKCS#11 private key discovery and selection
- Certificate generation using modern OpenSSL PKCS#11 provider or legacy pkcs11 engine
- Atomic certificate bundle updates
- Duplicate certificate detection (prevents duplicate entries)
- Support for any PKCS#11-compatible smartcard or hardware security module
- Integrated PAM profile for system-wide smartcard login support

## TL;DR

```bash
# Enable smartcard authentication for sudo and login
pam-auth-update --package --enable smartcard-p11-fallback

# Generate a certificate from your smartcard (auto-discovers keys)
p11cert.sh

# Or with an explicit PKCS#11 URL
p11cert.sh 'pkcs11:token=MyCard;id=%01'
```

Your certificate is now at `~/.eid/authorized_certificates` and smartcard login is enabled with password fallback.

## Installation

See [BUILD.md](./BUILD.md) for detailed build and installation instructions.


```bash
p11cert.sh [pkcs11-url]
```

See the `p11cert.sh(1)` man page for full usage details.

## Requirements

- **libpam-p11** – PAM module for smartcard authentication
- **gnutls-bin** – Tools for certificate and key handling
- **openssl** – OpenSSL cryptography toolkit with PKCS#11 support
- **opensc** or **opensc-pkcs11** – PKCS#11 driver for smartcards

## License

This project is licensed under the MIT license. See [`LICENSE`](./LICENSE).
