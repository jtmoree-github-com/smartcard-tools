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

info() {
  echo "p11cert.sh: $*" >&2
}

HOME_DIR="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
AUTH_DIR="$HOME_DIR/.eid"
AUTH_CERTS="$AUTH_DIR/authorized_certificates"
USER_NAME="${USER:-$(id -un)}"

if [ ! -d "$AUTH_DIR" ]; then
  mkdir -p "$AUTH_DIR"
  chmod 0755 "$AUTH_DIR"
fi

if [ -z "${URL:-}" ]; then
  info "Discovering PKCS#11 private keys on inserted tokens (PIN prompts are expected)."
  TOKEN_URLS=$(p11tool --list-token-urls --only-urls 2>/dev/null || true)
  CANDIDATE_URLS=""
  PRIMARY_TOKEN_URL=""

  if [ -n "$TOKEN_URLS" ]; then
    for token_url in $TOKEN_URLS; do
      case "$token_url" in
        *token=System%20Trust*|*model=p11-kit-trust*|*manufacturer=PKCS%2311%20Kit*)
          continue
          ;;
      esac

      case "$token_url" in
        *sig*|*signature*)
          [ -n "$PRIMARY_TOKEN_URL" ] || PRIMARY_TOKEN_URL="$token_url"
          ;;
        *)
          PRIMARY_TOKEN_URL="$token_url"
          break
          ;;
      esac
    done

    if [ -n "$PRIMARY_TOKEN_URL" ]; then
      CANDIDATE_URLS=$(p11tool --list-all-privkeys --login --detailed-url --only-urls "$PRIMARY_TOKEN_URL" 2>/dev/null || true)
    fi
  else
    CANDIDATE_URLS=$(p11tool --list-all-privkeys --login --detailed-url --only-urls 2>/dev/null || true)
    if [ -z "$CANDIDATE_URLS" ]; then
      CANDIDATE_URLS=$(p11tool --list-all-privkeys --detailed-url --only-urls 2>/dev/null || true)
    fi
    if [ -z "$CANDIDATE_URLS" ]; then
      CANDIDATE_URLS=$(p11tool --list-all-privkeys --only-urls 2>/dev/null || true)
    fi
  fi

  URL=$(printf '%s\n' "$CANDIDATE_URLS" | \
    grep -vi 'token=System%20Trust' | \
    grep -vi 'model=p11-kit-trust' | \
    grep -vi 'manufacturer=PKCS%2311%20Kit' | \
    grep -Ei '^pkcs11:' | \
    grep -Ei 'type=private|object-type=private' | \
    grep -Eiv 'sig|signature' | \
    grep -Ei 'auth|enc|decrypt' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  URL=$(printf '%s\n' "$CANDIDATE_URLS" | \
    grep -vi 'token=System%20Trust' | \
    grep -vi 'model=p11-kit-trust' | \
    grep -vi 'manufacturer=PKCS%2311%20Kit' | \
    grep -Ei '^pkcs11:' | \
    grep -Ei 'type=private|object-type=private' | \
    grep -Ei 'sig|signature' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  URL=$(printf '%s\n' "$CANDIDATE_URLS" | \
    grep -vi 'token=System%20Trust' | \
    grep -vi 'model=p11-kit-trust' | \
    grep -vi 'manufacturer=PKCS%2311%20Kit' | \
    grep -Ei '^pkcs11:' | \
    grep -Ei 'type=private|object-type=private' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  URL=$(printf '%s\n' "$CANDIDATE_URLS" | \
    grep -vi 'token=System%20Trust' | \
    grep -vi 'model=p11-kit-trust' | \
    grep -vi 'manufacturer=PKCS%2311%20Kit' | \
    grep -Ei '^pkcs11:' | \
    grep -Ei ';id=|[?&]id=' | \
    head -n 1)
fi

if [ -z "${URL:-}" ]; then
  echo "No usable PKCS#11 private key URL found on the token. Generate OpenPGP keys first, then retry." >&2
  echo "Debug: p11tool --list-all-privkeys --login --detailed-url --only-urls" >&2
  exit 1
fi

url_body="${URL#pkcs11:}"
url_body=$(printf '%s' "$url_body" | \
  sed -E 's/(^|;)library-description=[^;]*;?/\1/g; s/(^|;)library-manufacturer=[^;]*;?/\1/g; s/(^|;)library-version=[^;]*;?/\1/g; s/^;+//; s/;;+/;/g; s/;$//')
URL="pkcs11:$url_body"

info "Using PKCS#11 private key URL selected from token."

req_pem=$(mktemp "${TMPDIR:-/tmp}/p11cert-req.XXXXXX.pem")
selected_pubkey=$(mktemp "${TMPDIR:-/tmp}/p11cert-pubkey.XXXXXX.pem")
tmp_authorized=$(mktemp "$AUTH_DIR/.authorized_certificates.XXXXXX")
existing_dir=""

cleanup() {
  rm -f "$req_pem" "$selected_pubkey" "$tmp_authorized"
  if [ -n "$existing_dir" ]; then
    rm -rf "$existing_dir"
  fi
}

trap cleanup EXIT HUP INT TERM

openssl_module_path="${OPENSSL_MODULES:-/usr/lib/x86_64-linux-gnu/ossl-modules}"

info "Checking whether certificate for selected key already exists (PIN prompt may appear)."
if ! p11tool --export-pubkey --login --outfile "$selected_pubkey" "$URL" >/dev/null 2>&1; then
  echo "Failed to export public key from selected PKCS#11 private key URL." >&2
  exit 1
fi

selected_pubkey_fpr=$(openssl pkey -pubin -in "$selected_pubkey" -outform DER 2>/dev/null | openssl dgst -sha256 -r | awk '{print $1}')
if [ -z "$selected_pubkey_fpr" ]; then
  echo "Failed to compute fingerprint for selected PKCS#11 public key." >&2
  exit 1
fi

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
    existing_pubkey_fpr=$(openssl x509 -pubkey -noout -in "$cert" | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -r | awk '{print $1}')
    if [ -z "$existing_pubkey_fpr" ]; then
      echo "Failed to parse existing certificate in $AUTH_CERTS: $cert" >&2
      exit 1
    fi
    if [ "$existing_pubkey_fpr" = "$selected_pubkey_fpr" ]; then
      info "certid=$selected_pubkey_fpr already present. No update needed."
      info "To regenerate, delete the certificate from $AUTH_CERTS and rerun."
      exit 0
    fi
  done
fi

if openssl list -providers -provider-path "$openssl_module_path" -provider pkcs11prov >/dev/null 2>&1; then
  info "Generating self-signed certificate with OpenSSL PKCS#11 provider (PIN prompt may appear)."
  openssl req -new -x509 \
    -provider default \
    -provider pkcs11prov \
    -provider-path "$openssl_module_path" \
    -key "$URL" \
    -out "$req_pem" \
    -subj "/CN=$USER_NAME"
elif openssl req -help 2>&1 | grep -q -- '-engine'; then
  info "Generating self-signed certificate with legacy OpenSSL pkcs11 engine (PIN prompt may appear)."
  openssl req -engine pkcs11 -new -x509 -key "$URL" -keyform engine -out "$req_pem" -subj "/CN=$USER_NAME"
else
  echo "OpenSSL PKCS#11 support is not available. Install the OpenSSL PKCS#11 provider or a legacy OpenSSL build with the pkcs11 engine." >&2
  exit 1
fi

if [ -f "$AUTH_CERTS" ]; then
  cat "$AUTH_CERTS" > "$tmp_authorized"
fi
cat "$req_pem" >> "$tmp_authorized"
mv "$tmp_authorized" "$AUTH_CERTS"
chmod 0644 "$AUTH_CERTS"
info "Updated certificate bundle: $AUTH_CERTS"