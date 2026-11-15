#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root (or with sudo)." >&2
    exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    echo "[build-deps] Detected Debian/Ubuntu; installing Debian build dependencies..."
    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential \
        dpkg-dev \
        debhelper \
        fakeroot
    echo "[build-deps] Debian/Ubuntu build dependencies installed."
    exit 0
fi

if command -v dnf >/dev/null 2>&1; then
    echo "[build-deps] Detected Fedora/RHEL-like system; installing Fedora build dependencies..."
    dnf install -y \
        @development-tools \
        dpkg-dev \
        debhelper \
        fakeroot
    echo "[build-deps] Fedora build dependencies installed."
    exit 0
fi

if command -v yum >/dev/null 2>&1; then
    echo "[build-deps] Detected an older RPM-based system; installing build dependencies..."
    yum install -y \
        @development-tools \
        dpkg-dev \
        debhelper \
        fakeroot
    echo "[build-deps] RPM-based build dependencies installed."
    exit 0
fi

echo "[build-deps] Unsupported system: could not find apt-get, dnf, or yum." >&2
exit 1
