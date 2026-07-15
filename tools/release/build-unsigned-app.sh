#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
LOG_DIR="$DIST_DIR/logs"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_SOURCE="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"
XCCONFIG_PATH="$DIST_DIR/Reynard-unsigned.xcconfig"

mkdir -p "$DIST_DIR" "$LOG_DIR" "$ROOT_DIR/build"
rm -rf "$DERIVED_DATA" "$DIST_DIR/Reynard.app"
cp "$XCCONFIG_SOURCE" "$XCCONFIG_PATH"

BUILD_SHA="$(git -C "$ROOT_DIR" rev-parse --short=7 HEAD)"
perl -pi -e "s/^CURRENT_BUILD = .*/CURRENT_BUILD = $BUILD_SHA/" "$XCCONFIG_PATH"

export REYNARD_UNSIGNED_BUILD=1

xcodebuild -list -project "$PROJECT_PATH" | tee "$LOG_DIR/xcode-project-list-build.log"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme Reynard \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -xcconfig "$XCCONFIG_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    'CODE_SIGN_IDENTITY=' \
    'EXPANDED_CODE_SIGN_IDENTITY=' \
    AD_HOC_CODE_SIGNING_ALLOWED=NO \
    'DEVELOPMENT_TEAM=' \
    build 2>&1 | tee "$LOG_DIR/xcode-build.log"

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/Reynard.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Reynard.app was not produced at $APP_PATH"
    exit 65
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist")"
for required_path in \
    "$APP_PATH/Info.plist" \
    "$APP_PATH/$EXECUTABLE_NAME" \
    "$APP_PATH/PlugIns/OpenIn.appex" \
    "$APP_PATH/PlugIns/Reynard Helper.appex" \
    "$APP_PATH/Frameworks/GeckoView.framework" \
    "$APP_PATH/Frameworks/XUL"; do
    if [[ ! -e "$required_path" ]]; then
        echo "Required build product is missing: $required_path"
        exit 65
    fi
done

ditto "$APP_PATH" "$DIST_DIR/Reynard.app"
echo "Built unsigned app: $DIST_DIR/Reynard.app"
