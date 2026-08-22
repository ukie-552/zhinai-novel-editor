#!/bin/bash
# 制作未公证的 GitHub Release 安装镜像。
# 用法: ./macos/build_dmg.sh [版本号]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="织奈编辑器"
VERSION="${1:-1.0.0}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME-$VERSION-intel.dmg"

if [[ ! -d "$APP" ]]; then
  echo "未找到 $APP，先执行 macos/build_app.sh。" >&2
  exit 1
fi

STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zhinai-dmg.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG"

echo "==> 制作 DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG"

echo "==> 校验 DMG…"
hdiutil verify "$DMG"
(
  cd "$BUILD_DIR"
  shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256"
)

echo "✅ 已生成：$DMG"
