#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CL="$PROJECT_ROOT/debian/changelog"
MAINTAINER="JT Moree <jtmoree@users.noreply.github.com>"
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
BUILD_OUTPUT_DIR="${SMARTCARD_BUILD_OUTPUT_DIR:-${BUILD_OUTPUT_DIR:-}}"

usage() {
  cat <<'EOF'
Usage: build-deb.sh [--bump|--source|--binary|--help|--print-config]

Build the Debian package using the project changelog and native Debian packaging.

Options:
  --bump          bump the patch version in debian/changelog and exit
  --source        build a source package with dpkg-buildpackage -S -sa
  --binary        build a binary package with dpkg-buildpackage -b (default)
  --print-config  show the resolved config path and output dir without building
  --help          show this help

Build output is configurable per user via:
  $XDG_CONFIG_HOME/smartcard-tools/ppa.env
  or ~/.config/smartcard-tools/ppa.env

Supported variable:
  SMARTCARD_BUILD_OUTPUT_DIR=<absolute-path-for-built-artifacts>
  BUILD_OUTPUT_DIR=<absolute-path-for-built-artifacts>
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
  BUILD_OUTPUT_DIR="${BUILD_OUTPUT_DIR:-${SMARTCARD_BUILD_OUTPUT_DIR:-}}"
fi

if [ -z "$BUILD_OUTPUT_DIR" ]; then
  BUILD_OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
fi

mkdir -p "$BUILD_OUTPUT_DIR"

move_artifacts_to_output_dir() {
  local src_name cur_version changes_file file_name artifact

  src_name="$(dpkg-parsechangelog -S Source)"
  cur_version="$(dpkg-parsechangelog -S Version)"
  changes_file="${DEFAULT_OUTPUT_DIR}/${src_name}_${cur_version}_$(dpkg-architecture -qDEB_BUILD_ARCH).changes"

  if [ "$BUILD_OUTPUT_DIR" != "$DEFAULT_OUTPUT_DIR" ]; then
    if [ -f "$changes_file" ]; then
      while read -r file_name; do
        [ -n "$file_name" ] || continue
        if [ -f "${DEFAULT_OUTPUT_DIR}/${file_name}" ]; then
          mv -f "${DEFAULT_OUTPUT_DIR}/${file_name}" "${BUILD_OUTPUT_DIR}/"
        fi
      done < <(awk '/^Files:/ {in_files=1; next} in_files && NF==5 {print $5} in_files && NF!=5 {exit}' "$changes_file")
      mv -f "$changes_file" "${BUILD_OUTPUT_DIR}/"
    else
      for artifact in "${DEFAULT_OUTPUT_DIR}"/*_"${cur_version}"_*; do
        [ -e "$artifact" ] || continue
        mv -f "$artifact" "${BUILD_OUTPUT_DIR}/"
      done
    fi
  fi

  ls -1 "${BUILD_OUTPUT_DIR}"/smartcard-tools_* || true
}

bump_patch_version() {
  local top_line current_version base_version major minor patch new_version date_stamp

  top_line="$(head -n 1 "$CL")"
  current_version="$(printf '%s' "$top_line" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
  [ -n "$current_version" ] || { echo "Could not parse current version from $CL" >&2; exit 1; }

  base_version="${current_version%-*}"
  IFS='.' read -r major minor patch <<< "$base_version"
  patch="${patch:-0}"
  new_version="${major}.${minor}.$((patch + 1))-1"
  date_stamp="$(date -R)"

  cat > "$CL.new" <<EOF
smartcard-tools (${new_version}) unstable; urgency=medium

  * Bump package version for new build.

 -- ${MAINTAINER}  ${date_stamp}
EOF

  cat "$CL" >> "$CL.new" && mv "$CL.new" "$CL"
  echo "Bumped changelog version to ${new_version}"
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --print-config)
    print_config
    exit 0
    ;;
  --bump)
    bump_patch_version
    exit 0
    ;;
  --source)
    cd "$PROJECT_ROOT"
    dpkg-buildpackage -us -uc -S -sa
    move_artifacts_to_output_dir
    exit 0
    ;;
  --binary|"")
    cd "$PROJECT_ROOT"
    dpkg-buildpackage -us -uc -b
    move_artifacts_to_output_dir
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac
