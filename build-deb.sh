#!/usr/bin/env bash
set -euo pipefail
umask 022

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_NAME="smartcard-tools"
MAINTAINER="JT Moree <jtmoree@users.noreply.github.com>"
VERSION="${1:-0.1.0}"
ARCH="${2:-$(dpkg --print-architecture)}"
OUT_DIR="${REPO_ROOT}/dist"
STAGE_DIR="$(mktemp -d)"
PKG_DIR="${STAGE_DIR}/${PKG_NAME}_${VERSION}_${ARCH}"

cleanup() {
  rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

mkdir -p \
  "${PKG_DIR}/DEBIAN" \
  "${PKG_DIR}/usr/bin" \
  "${PKG_DIR}/usr/share/pam-configs" \
  "${PKG_DIR}/usr/share/doc/${PKG_NAME}"

install -m 0755 "${REPO_ROOT}/bin/p11cert.sh" "${PKG_DIR}/usr/bin/p11cert.sh"
install -m 0644 "${REPO_ROOT}/pam/smartcard-p11-fallback" "${PKG_DIR}/usr/share/pam-configs/smartcard-p11-fallback"
install -m 0755 "${REPO_ROOT}/packaging/postinst" "${PKG_DIR}/DEBIAN/postinst"
install -m 0644 "${REPO_ROOT}/LICENSE" "${PKG_DIR}/usr/share/doc/${PKG_NAME}/LICENSE"

cat > "${PKG_DIR}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: libpam-runtime, libpam-p11, opensc-pkcs11 | opensc, gnutls-bin, openssl
Maintainer: ${MAINTAINER}
Description: Smartcard helper tools and PAM profiles for pam_p11
 Installs p11cert.sh and a pam-auth-update profile for
 smartcard login via pam_p11 with local password fallback.
EOF

cat > "${PKG_DIR}/usr/share/doc/${PKG_NAME}/README.Debian" <<'EOF'
This package installs:
 - /usr/bin/p11cert.sh
 - /usr/share/pam-configs/smartcard-p11-fallback

To enable the PAM profile manually:
  pam-auth-update --package --enable smartcard-p11-fallback
EOF

mkdir -p "${OUT_DIR}"
dpkg-deb --root-owner-group --build "${PKG_DIR}" "${OUT_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "Built package: ${OUT_DIR}/${PKG_NAME}_${VERSION}_${ARCH}.deb"
