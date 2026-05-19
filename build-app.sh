#!/bin/bash
# Builds AI Usage and packages it as a double-clickable .app bundle.
# Requires only the Swift toolchain / Command Line Tools (no full Xcode).
set -euo pipefail
cd "$(dirname "$0")"

APP="AIUsage"             # executable name (no spaces)
BUNDLE="AI Usage.app"     # user-visible bundle name

echo "[1/4] Compiling (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP}"
if [[ ! -x "${BIN}" ]]; then
    echo "ERROR: build product not found at ${BIN}" >&2
    exit 1
fi

echo "[2/4] Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN}" "${BUNDLE}/Contents/MacOS/${APP}"
cp Info.plist "${BUNDLE}/Contents/Info.plist"
[[ -f AppIcon.icns ]] && cp AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"

echo "[3/4] Ad-hoc code signing"
codesign --force --deep --sign - "${BUNDLE}"

if [[ "${1:-}" == "--install" ]]; then
    echo "[4/4] Installing to /Applications"
    rm -rf "/Applications/${BUNDLE}"
    cp -r "${BUNDLE}" "/Applications/${BUNDLE}"
    rm -rf "${BUNDLE}"          # keep only the installed copy — avoids duplicates
    echo ""
    echo "  Installed: /Applications/${BUNDLE}"
    echo "  Run:       open \"/Applications/${BUNDLE}\""
else
    echo "[4/4] Done"
    echo ""
    echo "  Built: $(pwd)/${BUNDLE}"
    echo "  Install to /Applications:  ./build-app.sh --install"
fi
