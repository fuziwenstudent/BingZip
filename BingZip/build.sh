#!/bin/bash
# Build BingZip.app — a native macOS archiver GUI on top of the 7-Zip 26.05 engine.
# Produces Universal 2 binaries (arm64 + x86_64) when both slices build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
APP="$ROOT/dist/BingZip.app"
CONFIG="${1:-release}"

echo "==> Building 7zz engine (arm64 + x86_64)"
ENGINE_ARM64="$REPO/CPP/7zip/Bundles/Alone2/b/m_arm64/7zz"
ENGINE_X64="$REPO/CPP/7zip/Bundles/Alone2/b/m_x64/7zz"
if [ ! -x "$ENGINE_ARM64" ]; then
  ( cd "$REPO/CPP/7zip/Bundles/Alone2" && make -f ../../cmpl_mac_arm64.mak -j8 )
fi
if [ ! -x "$ENGINE_X64" ]; then
  ( cd "$REPO/CPP/7zip/Bundles/Alone2" && make -f ../../cmpl_mac_x64.mak -j8 )
fi

echo "==> Building extra CLI tools (7zr, lzma)"
SEVENZR_ARM64="$REPO/CPP/7zip/Bundles/Alone7z/b/m_arm64/7zr"
SEVENZR_X64="$REPO/CPP/7zip/Bundles/Alone7z/b/m_x64/7zr"
if [ ! -x "$SEVENZR_ARM64" ]; then
  ( cd "$REPO/CPP/7zip/Bundles/Alone7z" && make -f ../../cmpl_mac_arm64.mak -j8 )
fi
if [ ! -x "$SEVENZR_X64" ]; then
  ( cd "$REPO/CPP/7zip/Bundles/Alone7z" && make -f ../../cmpl_mac_x64.mak -j8 )
fi
LZMACON_ARM64="$REPO/CPP/7zip/Bundles/LzmaCon/b/m_arm64/lzma"
LZMACON_X64="$REPO/CPP/7zip/Bundles/LzmaCon/b/m_x64/lzma"
if [ ! -x "$LZMACON_ARM64" ]; then
  ( cd "$REPO/CPP/7zip/Bundles/LzmaCon" && make -f ../../cmpl_mac_arm64.mak -j8 )
fi
if [ ! -x "$LZMACON_X64" ]; then
  ( cd "$REPO/CPP/7zip/Bundles/LzmaCon" && make -f ../../cmpl_mac_x64.mak -j8 )
fi

echo "==> Building BingZip GUI ($CONFIG, universal)"
cd "$ROOT"
if swift build -c "$CONFIG" --arch arm64 --arch x86_64 2>/dev/null; then
  if [ "$CONFIG" = "release" ]; then
    BIN="$ROOT/.build/out/Products/Release/BingZip"
  else
    BIN="$ROOT/.build/out/Products/Debug/BingZip"
  fi
else
  echo "    (universal build unavailable, falling back to host arch)"
  swift build -c "$CONFIG"
  BIN="$ROOT/.build/$CONFIG/BingZip"
fi
[ -x "$BIN" ] || BIN="$ROOT/.build/debug/BingZip"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BingZip"
if [ -x "$ENGINE_X64" ]; then
  lipo -create "$ENGINE_ARM64" "$ENGINE_X64" -output "$APP/Contents/MacOS/7zz"
else
  cp "$ENGINE_ARM64" "$APP/Contents/MacOS/7zz"
fi
chmod +x "$APP/Contents/MacOS/7zz"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Extra command-line tools: keep copies in dist/tools and bundle them inside
# the app so a shared BingZip.app is fully self-contained.
mkdir -p "$ROOT/dist/tools" "$APP/Contents/MacOS/tools"
if [ -x "$SEVENZR_X64" ]; then
  lipo -create "$SEVENZR_ARM64" "$SEVENZR_X64" -output "$ROOT/dist/tools/7zr"
else
  cp "$SEVENZR_ARM64" "$ROOT/dist/tools/7zr"
fi
if [ -x "$LZMACON_X64" ]; then
  lipo -create "$LZMACON_ARM64" "$LZMACON_X64" -output "$ROOT/dist/tools/lzma"
else
  cp "$LZMACON_ARM64" "$ROOT/dist/tools/lzma"
fi
chmod +x "$ROOT/dist/tools/7zr" "$ROOT/dist/tools/lzma"
cp "$ROOT/dist/tools/7zr" "$APP/Contents/MacOS/tools/7zr"
cp "$ROOT/dist/tools/lzma" "$APP/Contents/MacOS/tools/lzma"
chmod +x "$APP/Contents/MacOS/tools/7zr" "$APP/Contents/MacOS/tools/lzma"

# Icon (generated if missing)
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Building Finder Sync extension (Finder right-click menu)"
APPEX="$APP/Contents/PlugIns/BingZipFinder.appex"
FINDER_SRC="$ROOT/FinderSync/FinderSync.swift"
rm -rf "$APPEX"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

build_appex_slice() {
  local arch="$1"
  local output="$2"
  xcrun swiftc -O -swift-version 5 \
    -module-name BingZipFinder \
    -target "${arch}-apple-macos11.0" \
    -application-extension \
    -parse-as-library \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -framework Cocoa -framework FinderSync \
    -o "$output" "$FINDER_SRC"
}

APPEX_ARM64="$APPEX/Contents/MacOS/BingZipFinder.arm64"
APPEX_X64="$APPEX/Contents/MacOS/BingZipFinder.x86_64"
if build_appex_slice arm64 "$APPEX_ARM64"; then
  if build_appex_slice x86_64 "$APPEX_X64"; then
    lipo -create "$APPEX_ARM64" "$APPEX_X64" \
      -output "$APPEX/Contents/MacOS/BingZipFinder"
    rm -f "$APPEX_ARM64" "$APPEX_X64"
  else
    echo "    (x86_64 extension slice unavailable, shipping arm64 only)"
    mv "$APPEX_ARM64" "$APPEX/Contents/MacOS/BingZipFinder"
  fi
else
  echo "    (arm64 extension build failed, trying host architecture)"
  build_appex_slice "$(uname -m)" "$APPEX/Contents/MacOS/BingZipFinder"
fi
cp "$ROOT/FinderSync/Info.plist" "$APPEX/Contents/Info.plist"
printf 'XPC!' > "$APPEX/Contents/PkgInfo"

echo "==> Signing nested code and app (ad-hoc)"
# Nested code must be signed before the outer application bundle.
if ! codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/7zz"; then
  echo "    warning: failed to sign the 7zz engine"
fi
for tool in "$APP/Contents/MacOS/tools/7zr" "$APP/Contents/MacOS/tools/lzma"; do
  if [ -x "$tool" ] && ! codesign --force --sign - --timestamp=none "$tool"; then
    echo "    warning: failed to sign $(basename "$tool")"
  fi
done
if ! codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT/FinderSync/BingZipFinder.entitlements" \
    "$APPEX"; then
  echo "    warning: failed to sign the Finder Sync extension"
fi
if ! codesign --force --sign - --timestamp=none "$APP"; then
  echo "    warning: failed to sign BingZip.app"
fi

echo "==> Creating shareable package"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$APP/Contents/Info.plist" 2>/dev/null || echo "1.2")
ARCHS=$(lipo -archs "$APP/Contents/MacOS/BingZip" 2>/dev/null || echo "unknown")
ARCH_LABEL=$(echo "$ARCHS" | tr ' ' '-')
SHARE_DIR="$ROOT/dist/share"
ZIP_PATH="$ROOT/dist/BingZip-$VERSION-macos-$ARCH_LABEL.zip"
DMG_PATH="$ROOT/dist/BingZip-$VERSION.dmg"

rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR"
ditto "$APP" "$SHARE_DIR/BingZip.app"
ln -sfn /Applications "$SHARE_DIR/Applications"

cat > "$SHARE_DIR/README-FIRST.txt" <<EOF
BingZip $VERSION
压缩引擎:7-Zip 26.05(7zz),已内置在 App 内
架构:$ARCHS

安装
  把 BingZip.app 拖到“应用程序”文件夹即可。
  引擎、7zr、lzma 与 Finder 右键扩展均随 App 一起分发,无需另装 7-Zip。

首次打开
  如果提示“无法验证开发者”,请右键点击 BingZip.app → 打开 → 再确认“打开”。
  也可以执行:
    xattr -dr com.apple.quarantine /Applications/BingZip.app

权限
  首次启动按“权限设置…”完成:
    • Finder 右键菜单:一键启用
    • 完全磁盘访问:打开一次即可覆盖桌面、文稿、下载、外接磁盘和网络卷
  授权后请退出并重新打开 BingZip。

说明
  RAR 创建需要另行安装 RARLAB 的 rar 工具;解压 RAR 无需安装。
  压缩引擎为 7-Zip(Igor Pavlov),遵循 GNU LGPL 与 unRAR 许可限制。
EOF

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc "$SHARE_DIR" "$ZIP_PATH"

DMG_CREATED=0
rm -f "$DMG_PATH"
if hdiutil create -volname "BingZip $VERSION" -srcfolder "$SHARE_DIR" \
    -ov -format UDZO "$DMG_PATH" >/dev/null 2>&1; then
  DMG_CREATED=1
else
  echo "    warning: DMG creation failed (ZIP is still available)"
fi

rm -f "$ROOT/dist/SHA256SUMS.txt"
(
  cd "$ROOT/dist"
  shasum -a 256 "$(basename "$ZIP_PATH")" >> SHA256SUMS.txt
  if [ "$DMG_CREATED" = "1" ]; then
    shasum -a 256 "$(basename "$DMG_PATH")" >> SHA256SUMS.txt
  fi
)

echo "==> Done: $APP"
echo "    Architectures: $(lipo -archs "$APP/Contents/MacOS/BingZip" 2>/dev/null || echo unknown) / 7zz: $(lipo -archs "$APP/Contents/MacOS/7zz" 2>/dev/null || echo unknown)"
echo "    Finder extension: $(lipo -archs "$APPEX/Contents/MacOS/BingZipFinder" 2>/dev/null || echo unknown)"
echo "    Share ZIP: $ZIP_PATH"
if [ "$DMG_CREATED" = "1" ]; then
  echo "    Share DMG: $DMG_PATH"
else
  echo "    Share DMG: not created"
fi
echo "    Checksums: $ROOT/dist/SHA256SUMS.txt"
echo "    Run: open \"$APP\""