#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <Reynard.app> <output.ipa>"
    exit 64
fi

SOURCE_APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_IPA="$(mkdir -p "$(dirname "$2")" && cd "$(dirname "$2")" && pwd)/$(basename "$2")"
WORK_DIR="$(dirname "$OUTPUT_IPA")/unsigned-ipa-work"
PAYLOAD_DIR="$WORK_DIR/Payload"
APP_PATH="$PAYLOAD_DIR/Reynard.app"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "App bundle not found: $SOURCE_APP"
    exit 66
fi

for command_name in codesign ditto file unzip zip; do
    command -v "$command_name" >/dev/null || {
        echo "$command_name is required."
        exit 69
    }
done

rm -rf "$WORK_DIR"
mkdir -p "$PAYLOAD_DIR"
ditto "$SOURCE_APP" "$APP_PATH"

find "$APP_PATH" -type d -name '_CodeSignature' -prune -exec rm -rf {} +
find "$APP_PATH" -type f \( -name 'embedded.mobileprovision' -o -name 'CodeResources' \) -delete

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist")"
for required_path in \
    "$APP_PATH/Info.plist" \
    "$APP_PATH/$EXECUTABLE_NAME" \
    "$APP_PATH/PlugIns/OpenIn.appex" \
    "$APP_PATH/PlugIns/Reynard Helper.appex" \
    "$APP_PATH/Frameworks/GeckoView.framework" \
    "$APP_PATH/Frameworks/XUL"; do
    if [[ ! -e "$required_path" ]]; then
        echo "Cannot package incomplete app; missing: $required_path"
        exit 65
    fi
done

if find "$APP_PATH" \( -type d -name '_CodeSignature' -o -type f -name 'embedded.mobileprovision' \) -print -quit | grep -q .; then
    echo "Signing metadata remains in the app bundle."
    exit 70
fi

# Xcode can copy Apple-signed compatibility Swift runtimes even when app code
# signing is disabled. Strip those embedded Mach-O signatures from the copied
# Payload so the IPA contains no signing identity of any kind.
while IFS= read -r -d '' candidate; do
    if file "$candidate" | grep -q 'Mach-O' && codesign --display "$candidate" >/dev/null 2>&1; then
        codesign --remove-signature "$candidate"
    fi
done < <(find "$APP_PATH" -type f -print0)

while IFS= read -r -d '' candidate; do
    if file "$candidate" | grep -q 'Mach-O' && codesign --display "$candidate" >/dev/null 2>&1; then
        echo "A signed Mach-O was found in the unsigned build: $candidate"
        exit 70
    fi
done < <(find "$APP_PATH" -type f -print0)

rm -f "$OUTPUT_IPA"
(
    cd "$WORK_DIR"
    zip -qry "$OUTPUT_IPA" Payload -x '._*' -x '*.DS_Store' -x '__MACOSX/*'
)

unzip -tq "$OUTPUT_IPA" >/dev/null
unzip -l "$OUTPUT_IPA" | grep -q 'Payload/Reynard.app/PlugIns/OpenIn.appex/'
unzip -l "$OUTPUT_IPA" | grep -q 'Payload/Reynard.app/PlugIns/Reynard Helper.appex/'
unzip -l "$OUTPUT_IPA" | grep -q 'Payload/Reynard.app/Frameworks/GeckoView.framework/'

rm -rf "$WORK_DIR"
echo "Created unsigned IPA from source-built app: $OUTPUT_IPA"
