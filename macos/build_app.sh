#!/bin/bash
# 构建 macOS 原生应用：织奈编辑器.app（纯 SwiftUI，零依赖）
# 用法: ./macos/build_app.sh
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="织奈编辑器"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
SWIFT_FILES=(
  macos/Models.swift macos/DB.swift macos/LLM.swift macos/Skills.swift macos/VectorStore.swift macos/AppState.swift
  macos/MainApp.swift macos/ContentView.swift macos/SidebarView.swift macos/VectorWorkspaceView.swift
  macos/ChatView.swift macos/EditorView.swift macos/Sheets.swift
)

echo "==> 清理旧构建…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Swift 应用…"
swiftc -O -swift-version 5 -target x86_64-apple-macosx13.0 "${SWIFT_FILES[@]}" \
  -o "$APP/Contents/MacOS/ZhinaiNovelEditor" \
  -framework SwiftUI -framework AppKit -lsqlite3

echo "==> 写入 Info.plist…"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"

echo "==> 生成应用图标…"
SOURCE_ICON="$ROOT/assets/AppIcon.png"
ICONSET="$BUILD_DIR/icon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/icon.icns"
cp "$BUILD_DIR/icon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> 写入默认背景…"
cp "$ROOT/assets/DefaultBackground.jpeg" "$APP/Contents/Resources/DefaultBackground.jpeg"

echo "==> 本地签名…"
codesign --force --sign - "$APP" 2>/dev/null || true

echo ""
echo "✅ 构建完成：$APP"
echo "运行：open \"$APP\""
echo "（可将其拖入「应用程序」文件夹常驻使用）"
