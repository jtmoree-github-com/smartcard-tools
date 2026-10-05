#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CL="$PROJECT_ROOT/debian/changelog"
MAINTAINER="JT Moree <jtmoree@users.noreply.github.com>"

usage() {
  cat <<'EOF'
Usage: build-deb.sh [--bump|--source|--binary|--help]

Build the Debian package using the project changelog and native Debian packaging.

Options:
  --bump          bump the patch version in debian/changelog and exit
  --source        build a source package with dpkg-buildpackage -S -sa
  --binary        build a binary package with dpkg-buildpackage -b (default)
  --help          show this help
EOF
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
  --bump)
    bump_patch_version
    exit 0
    ;;
  --source)
    cd "$PROJECT_ROOT"
    dpkg-buildpackage -us -uc -S -sa
    exit 0
    ;;
  --binary|"")
    cd "$PROJECT_ROOT"
    dpkg-buildpackage -us -uc -b
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac
