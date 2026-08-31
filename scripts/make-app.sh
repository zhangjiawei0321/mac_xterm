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
# 应用显示名（.app 目录/包名/显示名）；SPM 可执行产物名保持 BIN_NAME
APP_NAME="NblityTerm"
BIN_NAME="MobaLike"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

# 可切换编译器：默认 $(swift)（Xcode 装好后即系统 swift）；
# 还没有 Xcode 时可指向解包的官方工具链，例如：
#   export SWIFT=/path/to/Swift-6.0.3-RELEASE/usr/bin/swift
SWIFT="${SWIFT:-swift}"

echo "==> \$SWIFT=$SWIFT ; build -c $CONFIG"
# --disable-sandbox：SPM 清单编译在本机受限沙箱下会失败，关闭 SPM 自带沙箱即可
$SWIFT build -c "$CONFIG" --disable-sandbox

# 定位可执行文件（新版 SPM 可能放在架构子目录）
BIN=""
for candidate in \
  ".build/$CONFIG/$BIN_NAME" \
  ".build/arm64-apple-macosx/$CONFIG/$BIN_NAME" \
  ".build/x86_64-apple-macosx/$CONFIG/$BIN_NAME"; do
  if [ -f "$candidate" ]; then BIN="$candidate"; break; fi
done
if [ -z "$BIN" ]; then
  echo "找不到构建产物 $BIN_NAME" >&2
  exit 1
fi

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
# 应用图标（如存在）
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  ICON_ENTRY=$'  <key>CFBundleIconFile</key><string>AppIcon</string>\n'
else
  ICON_ENTRY=""
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.nblityterm.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  ${ICON_ENTRY}<key>LSMinimumSystemVersion</key><string>13.0</string>
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
