#!/bin/bash
# Packages AI Usage as a distributable .dmg disk image (for a GitHub Release).
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE="AI Usage.app"
DMG="AI Usage.dmg"
VOLUME="AI Usage"

echo "[1/3] Building app bundle"
./build-app.sh >/dev/null

if [[ ! -d "${BUNDLE}" ]]; then
    echo "ERROR: ${BUNDLE} not found" >&2
    exit 1
fi

echo "[2/3] Staging disk image contents"
TMP="$(mktemp -d)"
STAGE="${TMP}/${VOLUME}"
mkdir -p "${STAGE}"
cp -R "${BUNDLE}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"   # drag-to-install target

echo "[3/3] Creating ${DMG}"
rm -f "${DMG}"
hdiutil create -volname "${VOLUME}" -srcfolder "${STAGE}" \
    -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${TMP}" "${BUNDLE}"

echo ""
echo "  Created: $(pwd)/${DMG}"
echo "  GitHub Release 에 이 파일을 업로드하세요."
