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
  macos/Models.swift macos/BookProject.swift macos/DB.swift macos/LLM.swift macos/Skills.swift macos/VectorStore.swift macos/WorkspaceTools.swift macos/GovernanceTools.swift macos/ToolGroups.swift macos/AppState.swift macos/ConversationCoordinator.swift
  macos/MainApp.swift macos/BackgroundVideoView.swift macos/ContentView.swift macos/SidebarView.swift macos/VectorWorkspaceView.swift
  macos/ChatView.swift macos/BookCardsView.swift macos/EditorView.swift macos/Sheets.swift
)

# 编辑器、云盘同步等进程可能在较长的优化编译期间触碰源文件，导致 Swift 报
# "input file was modified during the build"。先复制不可变快照再交给编译器。
BUILD_SOURCE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zhinai-build-sources.XXXXXX")
trap 'rm -rf "$BUILD_SOURCE_DIR"' EXIT
SNAPSHOT_FILES=()
for source in "${SWIFT_FILES[@]}"; do
  snapshot="$BUILD_SOURCE_DIR/$(basename "$source")"
  cp "$source" "$snapshot"
  SNAPSHOT_FILES+=("$snapshot")
done

echo "==> 清理旧构建…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Intel Swift 应用…"
swiftc -O -swift-version 5 -target x86_64-apple-macosx13.0 "${SNAPSHOT_FILES[@]}" \
  -o "$APP/Contents/MacOS/ZhinaiNovelEditor" \
  -framework SwiftUI -framework AppKit -framework AVFoundation -lsqlite3

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

echo "==> 写入内置 Agent 头像…"
cp -R "$ROOT/assets/AgentAvatars" "$APP/Contents/Resources/AgentAvatars"

echo "==> 本地签名…"
codesign --force --sign - "$APP" 2>/dev/null || true

echo "==> 验证架构与签名…"
lipo -archs "$APP/Contents/MacOS/ZhinaiNovelEditor"
codesign --verify --deep --strict "$APP"

echo ""
echo "✅ 构建完成：$APP"
echo "运行：open \"$APP\""
echo "（可将其拖入「应用程序」文件夹常驻使用）"
