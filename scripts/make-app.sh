#!/bin/bash
# ============================================================
#  MobaLike 打包脚本：把 SPM 可执行文件组装成 .app 并 ad-hoc 签名
#  用法：
#    ./scripts/make-app.sh            # debug 构建
#    ./scripts/make-app.sh release    # release 构建
#  产物：build/MobaLike.app
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="MobaLike"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

# 可切换编译器：默认 $(swift)（Xcode 装好后即系统 swift）；
# 还没有 Xcode 时可指向解包的官方工具链，例如：
#   export SWIFT=/path/to/Swift-6.0.3-RELEASE/usr/bin/swift
SWIFT="${SWIFT:-swift}"

echo "==> \$SWIFT=$SWIFT ; build -c $CONFIG"
$SWIFT build -c "$CONFIG"

# 定位可执行文件（新版 SPM 可能放在架构子目录）
BIN=""
for candidate in \
  ".build/$CONFIG/$APP_NAME" \
  ".build/arm64-apple-macosx/$CONFIG/$APP_NAME" \
  ".build/x86_64-apple-macosx/$CONFIG/$APP_NAME"; do
  if [ -f "$candidate" ]; then BIN="$candidate"; break; fi
done
if [ -z "$BIN" ]; then
  echo "找不到构建产物 $APP_NAME" >&2
  exit 1
fi

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.mobalike.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>MobaLike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc 签名"
codesign --force --deep -s - "$APP" 2>/dev/null || echo "   （签名失败可忽略，本地仍可运行）"

echo
echo "完成：$APP"
echo "直接双击打开，或执行： open \"$APP\""
