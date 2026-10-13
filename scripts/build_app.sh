#!/bin/bash
# 构建并组装 build/IPPure Bar.app
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="IPPure Bar"
EXEC_NAME="IPPureBar"
APP_DIR="build/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="${BIN_DIR}/${EXEC_NAME}"

echo "==> 组装 ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN}" "${APP_DIR}/Contents/MacOS/${EXEC_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

echo "==> 生成 AppIcon.icns"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
ICONSET="${TMP_DIR}/AppIcon.iconset"
mkdir -p "${ICONSET}"
if "${BIN}" --render-appicon "${TMP_DIR}/icon_1024.png" && [ -f "${TMP_DIR}/icon_1024.png" ]; then
    gen() { sips -z "$1" "$1" "${TMP_DIR}/icon_1024.png" --out "${ICONSET}/$2" >/dev/null; }
    gen 16   icon_16x16.png
    gen 32   icon_16x16@2x.png
    gen 32   icon_32x32.png
    gen 64   icon_32x32@2x.png
    gen 128  icon_128x128.png
    gen 256  icon_128x128@2x.png
    gen 256  icon_256x256.png
    gen 512  icon_256x256@2x.png
    gen 512  icon_512x512.png
    cp "${TMP_DIR}/icon_1024.png" "${ICONSET}/icon_512x512@2x.png"
    iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
    echo "警告: 图标生成失败，跳过" >&2
fi

echo "==> codesign (ad-hoc)"
codesign --force --deep -s - "${APP_DIR}"

echo "==> 完成: ${APP_DIR}"
