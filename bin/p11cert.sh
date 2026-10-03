#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: p11cert.sh [pkcs11-url]

Generate a short-lived self-signed certificate from a PKCS#11 private key and
append it to ~/.eid/authorized_certificates.

Positional arguments:
  pkcs11-url            Optional explicit PKCS#11 URL to use

Options:
  -h, --help            Show this help text

Behavior:
  - If no PKCS#11 URL is provided, the script asks p11tool to list private keys
    and tries to select an encryption/authentication key first.
  - If the output directory does not exist, it is created as ~/.eid.
  - The certificate bundle is updated atomically.
  - A certificate for the same PKCS#11 public key is not appended twice.

Runtime requirements:
  - p11tool
  - openssl
EOF
}

if [ "$#" -eq 1 ]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
fi

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  URL="$1"
  if ! printf '%s\n' "$URL" | grep -q '^pkcs11:'; then
    echo "Provided URL must start with pkcs11:" >&2
    exit 2
  fi
fi

for cmd in p11tool openssl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

HOME_DIR="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
AUTH_DIR="$HOME_DIR/.eid"
AUTH_CERTS="$AUTH_DIR/authorized_certificates"
USER_NAME="${USER:-$(id -un)}"

if [ ! -d "$AUTH_DIR" ]; then
  mkdir -p "$AUTH_DIR"
  chmod 0755 "$AUTH_DIR"
fi

if [ -z "${URL:-}" ]; then
  URL=$(p11tool --list-all-privkeys --only-urls 2>/dev/null | \
    grep -Eiv 'sig|signature' | \
    grep -Ei 'auth|enc|decrypt' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  URL=$(p11tool --list-all-privkeys --only-urls 2>/dev/null | \
    grep -Ei 'sig|signature' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  URL=$(p11tool --list-all-privkeys --only-urls 2>/dev/null | head -n 1)
fi

if [ -z "${URL:-}" ]; then
  echo "Unable to find an encryption/authentication PKCS#11 key URL." >&2
  exit 1
fi

req_pem=$(mktemp "${TMPDIR:-/tmp}/p11cert-req.XXXXXX.pem")
tmp_authorized=$(mktemp "$AUTH_DIR/.authorized_certificates.XXXXXX")
existing_dir=""

cleanup() {
  rm -f "$req_pem" "$tmp_authorized"
  if [ -n "$existing_dir" ]; then
    rm -rf "$existing_dir"
  fi
}

trap cleanup EXIT HUP INT TERM

openssl req -engine pkcs11 -new -x509 -key "$URL" -keyform engine -out "$req_pem" -subj "/CN=$USER_NAME"

new_pubkey_fpr=$(openssl x509 -pubkey -noout -in "$req_pem" | openssl dgst -sha256 -r | awk '{print $1}')

if [ -f "$AUTH_CERTS" ]; then
  existing_dir=$(mktemp -d "$AUTH_DIR/.authorized_certificates.XXXXXX")
  awk -v outdir="$existing_dir" '
    /BEGIN CERTIFICATE/ {
      cert++
      file = sprintf("%s/cert.%06d.pem", outdir, cert)
    }
    file { print > file }
    /END CERTIFICATE/ { close(file) }
  ' "$AUTH_CERTS"

  for cert in "$existing_dir"/*.pem; do
    [ -e "$cert" ] || continue
    existing_pubkey_fpr=$(openssl x509 -pubkey -noout -in "$cert" | openssl dgst -sha256 -r | awk '{print $1}')
    if [ "$existing_pubkey_fpr" = "$new_pubkey_fpr" ]; then
      exit 0
    fi
  done
fi

if [ -f "$AUTH_CERTS" ]; then
  cat "$AUTH_CERTS" > "$tmp_authorized"
fi
cat "$req_pem" >> "$tmp_authorized"
mv "$tmp_authorized" "$AUTH_CERTS"
chmod 0644 "$AUTH_CERTS"