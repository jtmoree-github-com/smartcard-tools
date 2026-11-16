#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CL="$PROJECT_ROOT/debian/changelog"
DEFAULT_OUTPUT_DIR="$(dirname "$PROJECT_ROOT")"

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  if command -v getent >/dev/null 2>&1; then
    SUDO_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  else
    SUDO_HOME="$(eval echo "~$SUDO_USER")"
  fi
  if [ -n "${SUDO_HOME:-}" ] && [ -d "$SUDO_HOME" ]; then
    export HOME="$SUDO_HOME"
    if [ -z "${XDG_CONFIG_HOME:-}" ] || [ "${XDG_CONFIG_HOME:-}" = "/root/.config" ]; then
      export XDG_CONFIG_HOME="$SUDO_HOME/.config"
    fi
  fi
fi

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/smartcard-tools/ppa.env"
DEVSCRIPTS_FILE="$HOME/.devscripts"

SERIES=""
PPA_REV="1"
PPA_OWNER="${SMARTCARD_PPA_OWNER:-${LUKS_PPA_OWNER:-${LP_PPA_OWNER:-}}}"
PPA_NAME="${SMARTCARD_PPA_NAME:-${LUKS_PPA_NAME:-${LP_PPA_NAME:-}}}"
SIGN_KEY="${SMARTCARD_DEBSIGN_KEYID:-${LUKS_DEBSIGN_KEYID:-${DEBSIGN_KEYID:-}}}"
LTS_SERIES="${SMARTCARD_LTS_SERIES:-${LUKS_LTS_SERIES:-resolute}}"
LTS_SERIES_NUM="${SMARTCARD_LTS_SERIES_NUM:-${LUKS_LTS_SERIES_NUM:-26.04}}"
BUILD_OUTPUT_DIR="${SMARTCARD_BUILD_OUTPUT_DIR:-${LUKS_BUILD_OUTPUT_DIR:-${BUILD_OUTPUT_DIR:-}}}"
UBUNTU_SERIES_NUM=""
NO_BUILD=0
UNSIGNED=0

usage() {
  cat <<'EOF'
Usage: build-ppa-source.sh --series <resolute|questing|noble|jammy|lts> [options]

Prepares debian/changelog for a Launchpad PPA upload and optionally builds a signed source package.

Required:
  --series <name>          Ubuntu series name (resolute, questing, noble, jammy, or lts)

Options:
  --ppa-rev <n>            PPA revision in version suffix (default: 1)
  --ppa-owner <id>         Launchpad owner/team id for dput command output
                            (default from config/env)
  --ppa-name <name>        Launchpad PPA name for dput command output
                            (default from config/env)
  --sign-key <keyid>       GPG signing key id/fingerprint for dpkg-buildpackage
                            (default from config/env)
  --ubuntu-series-num <v>  Override the Ubuntu series number in the suffix (e.g. 24.04)
  --no-build               Only rewrite the changelog entry; skip source builds
  --unsigned               Build an unsigned source package (-us -uc)
  --print-config           Show the config path and resolved output dir without building
  --help                   Show this help text

Default config file:
  $XDG_CONFIG_HOME/smartcard-tools/ppa.env (or ~/.config/smartcard-tools/ppa.env)
  Supported variables:
    SMARTCARD_PPA_OWNER=jtmoree
    SMARTCARD_PPA_NAME=<ppa-name>
    SMARTCARD_DEBSIGN_KEYID=<keyid-or-fingerprint>
    SMARTCARD_GNUPGHOME=<path-to-gnupg-home>
    SMARTCARD_LTS_SERIES=resolute
    SMARTCARD_LTS_SERIES_NUM=26.04
    SMARTCARD_BUILD_OUTPUT_DIR=<where-built-artifacts-are-stored>
    BUILD_OUTPUT_DIR=<absolute-path-for-built-artifacts>

Examples:
  ./scripts/build-ppa-source.sh --series resolute --ppa-owner jtmoree --ppa-name security-tools
  ./scripts/build-ppa-source.sh --series resolute --ppa-rev 1
  ./scripts/build-ppa-source.sh --series resolute --ppa-rev 2
  ./scripts/build-ppa-source.sh --series questing --ppa-rev 1
  ./scripts/build-ppa-source.sh --series jammy --ppa-rev 2
  ./scripts/build-ppa-source.sh --series lts --ppa-rev 2 --no-build
EOF
}

print_config() {
  echo "Config file: ${CONFIG_FILE}"
  if [ -r "$CONFIG_FILE" ]; then
    echo "Config file status: present"
  else
    echo "Config file status: not found"
  fi
  echo "Default output dir: ${DEFAULT_OUTPUT_DIR}"
  echo "Resolved output dir: ${BUILD_OUTPUT_DIR}"
}

if [ -r "$CONFIG_FILE" ]; then
  set +u
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  set -u
  PPA_OWNER="${PPA_OWNER:-${SMARTCARD_PPA_OWNER:-${LUKS_PPA_OWNER:-${LP_PPA_OWNER:-}}}}"
  PPA_NAME="${PPA_NAME:-${SMARTCARD_PPA_NAME:-${LUKS_PPA_NAME:-${LP_PPA_NAME:-}}}}"
  SIGN_KEY="${SIGN_KEY:-${SMARTCARD_DEBSIGN_KEYID:-${LUKS_DEBSIGN_KEYID:-${DEBSIGN_KEYID:-}}}}"
  LTS_SERIES="${LTS_SERIES:-${SMARTCARD_LTS_SERIES:-${LUKS_LTS_SERIES:-resolute}}}"
  LTS_SERIES_NUM="${LTS_SERIES_NUM:-${SMARTCARD_LTS_SERIES_NUM:-${LUKS_LTS_SERIES_NUM:-26.04}}}"
  BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-${SMARTCARD_BUILD_OUTPUT_DIR:-${LUKS_BUILD_OUTPUT_DIR:-}}}"
fi

if [ -n "${SMARTCARD_GNUPGHOME:-${LUKS_GNUPGHOME:-}}" ]; then
  GNUPGHOME="${SMARTCARD_GNUPGHOME:-${LUKS_GNUPGHOME:-}}"
fi

if [ -n "${GNUPGHOME:-}" ]; then
  export GNUPGHOME
fi

if [ -z "$SIGN_KEY" ] && [ -r "$DEVSCRIPTS_FILE" ]; then
  DEVSCRIPTS_KEY="$(sed -n 's/^[[:space:]]*DEBSIGN_KEYID[[:space:]]*=[[:space:]]*\([^#[:space:]]\+\).*$/\1/p' "$DEVSCRIPTS_FILE" | tail -n1)"
  SIGN_KEY="${DEVSCRIPTS_KEY:-}"
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --series)
      SERIES="${2:-}"
      shift 2
      ;;
    --ppa-rev)
      PPA_REV="${2:-}"
      shift 2
      ;;
    --ppa-owner)
      PPA_OWNER="${2:-}"
      shift 2
      ;;
    --ppa-name)
      PPA_NAME="${2:-}"
      shift 2
      ;;
    --sign-key)
      SIGN_KEY="${2:-}"
      shift 2
      ;;
    --ubuntu-series-num)
      UBUNTU_SERIES_NUM="${2:-}"
      shift 2
      ;;
    --no-build)
      NO_BUILD=1
      shift
      ;;
    --unsigned)
      UNSIGNED=1
      shift
      ;;
    --print-config)
      print_config
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$SERIES" ] || { echo "--series is required" >&2; usage >&2; exit 2; }
case "$SERIES" in
  resolute)
    DEFAULT_UBUNTU_SERIES_NUM="26.04"
    ;;
  questing)
    DEFAULT_UBUNTU_SERIES_NUM="25.10"
    ;;
  noble)
    DEFAULT_UBUNTU_SERIES_NUM="24.04"
    ;;
  lts)
    SERIES="$LTS_SERIES"
    DEFAULT_UBUNTU_SERIES_NUM="$LTS_SERIES_NUM"
    ;;
  jammy)
    DEFAULT_UBUNTU_SERIES_NUM="22.04"
    ;;
  *)
    echo "Unsupported series: $SERIES (supported: resolute, questing, noble, jammy, lts)" >&2
    exit 2
    ;;
esac

if [ -z "$UBUNTU_SERIES_NUM" ]; then
  UBUNTU_SERIES_NUM="$DEFAULT_UBUNTU_SERIES_NUM"
fi

if ! [[ "$PPA_REV" =~ ^[0-9]+$ ]]; then
  echo "--ppa-rev must be numeric" >&2
  exit 2
fi

if [ -z "$BUILD_OUTPUT_DIR" ]; then
  BUILD_OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
fi

mkdir -p "$BUILD_OUTPUT_DIR"

cd "$PROJECT_ROOT"

TOP_LINE="$(head -1 "$CL")"
SRC_NAME="${TOP_LINE%% *}"
CUR_VERSION="$(printf '%s' "$TOP_LINE" | sed -n 's/.*(\([^)]*\)).*/\1/p')"

[ -n "$SRC_NAME" ] || { echo "Could not parse source package name from $CL" >&2; exit 1; }
[ -n "$CUR_VERSION" ] || { echo "Could not parse version from $CL" >&2; exit 1; }

BASE_VERSION="${CUR_VERSION%%~ppa*}"
NEW_VERSION="${BASE_VERSION}~ppa${PPA_REV}~ubuntu${UBUNTU_SERIES_NUM}.1"
NEW_TOP_LINE="${SRC_NAME} (${NEW_VERSION}) ${SERIES}; urgency=medium"

sed -i "1s|^.*$|$NEW_TOP_LINE|" "$CL"

echo "Updated changelog top entry:"
echo "  $NEW_TOP_LINE"

if [ "$NO_BUILD" -eq 1 ]; then
  echo "Skipping build (--no-build)."
  exit 0
fi

if [ "$UNSIGNED" -eq 1 ]; then
  echo "[1/2] Building unsigned source package"
  dpkg-buildpackage -S -sa -us -uc
else
  echo "[1/2] Building signed source package"
  if [ -n "$SIGN_KEY" ]; then
    dpkg-buildpackage -S -sa -k"$SIGN_KEY"
  else
    dpkg-buildpackage -S -sa
  fi
fi

echo "[2/2] Artifacts"
CHANGES_FILE="${DEFAULT_OUTPUT_DIR}/${SRC_NAME}_${NEW_VERSION}_source.changes"
if [ "$BUILD_OUTPUT_DIR" != "$DEFAULT_OUTPUT_DIR" ]; then
  ORIG_CHANGES_FILE="$CHANGES_FILE"
  if [ -f "$ORIG_CHANGES_FILE" ]; then
    while read -r file_name; do
      [ -n "$file_name" ] || continue
      if [ -f "${DEFAULT_OUTPUT_DIR}/${file_name}" ]; then
        mv -f "${DEFAULT_OUTPUT_DIR}/${file_name}" "${BUILD_OUTPUT_DIR}/"
      fi
    done < <(awk '/^Files:/ {in_files=1; next} in_files && NF==5 {print $5} in_files && NF!=5 {exit}' "$ORIG_CHANGES_FILE")
    mv -f "$ORIG_CHANGES_FILE" "${BUILD_OUTPUT_DIR}/"
  fi
  CHANGES_FILE="${BUILD_OUTPUT_DIR}/${SRC_NAME}_${NEW_VERSION}_source.changes"
fi

ls -1 "${BUILD_OUTPUT_DIR}"/"${SRC_NAME}"_* || true

if [ -f "$CHANGES_FILE" ]; then
  echo
  echo "Source changes file: $CHANGES_FILE"
  if [ -n "$PPA_OWNER" ] && [ -n "$PPA_NAME" ]; then
    echo "Upload command:"
    if [ -n "${GNUPGHOME:-}" ]; then
      echo "  env GNUPGHOME=\"$GNUPGHOME\" dput ppa:${PPA_OWNER}/${PPA_NAME} $CHANGES_FILE"
    else
      echo "  dput ppa:${PPA_OWNER}/${PPA_NAME} $CHANGES_FILE"
    fi
  else
    echo "Provide --ppa-owner and --ppa-name to print an exact dput command."
  fi
else
  echo "Warning: expected source changes file not found: $CHANGES_FILE" >&2
fi
