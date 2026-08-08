#!/bin/sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"

TARGET="aarch64-apple-ios"

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
	echo "Missing firefox source at $FIREFOX_DIR"
	echo "Add the submodule, then run tools/development/update-gecko.sh."
	exit 1
fi

MOZCONFIG="$FIREFOX_DIR/.mozconfig"
MOZCONFIG_BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reynard-mozconfig.XXXXXX")"
MOZCONFIG_BACKUP="$MOZCONFIG_BACKUP_DIR/.mozconfig"
HAD_MOZCONFIG=0

if [ -e "$MOZCONFIG" ]; then
	mv "$MOZCONFIG" "$MOZCONFIG_BACKUP"
	HAD_MOZCONFIG=1
fi

restore_mozconfig() {
	rm -f "$MOZCONFIG"
	if [ "$HAD_MOZCONFIG" -eq 1 ]; then
		mv "$MOZCONFIG_BACKUP" "$MOZCONFIG"
	fi
	rmdir "$MOZCONFIG_BACKUP_DIR"
}

trap restore_mozconfig EXIT

{
	echo "ac_add_options --enable-application=mobile/ios"
	echo "ac_add_options --target=$TARGET"
	echo "ac_add_options --enable-ios-target=13.0"
	echo "ac_add_options --enable-webrtc"
	echo "ac_add_options --enable-optimize"
	echo "ac_add_options --enable-release"
	echo "ac_add_options --enable-rust-simd"
	echo "ac_add_options --disable-debug"
	echo "ac_add_options --disable-tests"
} > "$MOZCONFIG"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
	rustup target add "$TARGET"
fi

cd "$FIREFOX_DIR"
./mach build

trap - EXIT
restore_mozconfig
