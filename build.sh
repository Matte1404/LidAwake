#!/bin/bash
# Build a macOS 12+ app and optionally install it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
    ""|--no-install) ;;
    *) echo "Usage: $0 [--no-install]" >&2; exit 2 ;;
esac
./scripts/build-app.sh native
if [ "${1:-}" = --no-install ]; then exit 0; fi

DEST="/Applications/LidAwake.app"
if [ -e "$DEST" ]; then
    read -r -p "$DEST already exists. Overwrite? [y/N] " reply
    case "$reply" in
        [yY]*) ;;
        *) echo "Skipped install. Open LidAwake.app to test locally."; exit 0 ;;
    esac
fi
rm -rf "$DEST"
cp -R LidAwake.app "$DEST"
echo "Installed to $DEST"
