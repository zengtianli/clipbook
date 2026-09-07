#!/bin/bash
# 构建 Clipbook（菜单栏常驻剪贴板历史 · 全 Swift 原生 · 无后端进程 · 无网络）并装 /Applications。
# 形态 = 裸 SwiftUI 源码 → swiftc 直编 → 手搓最小 .app → plutil 注入 → 签名 → 装机。
#
# 门，全部 fail-closed（禁 `|| true` / 禁 `2>/dev/null`）：
#   ① 舰队通用 CodingKeys × convertFromSnakeCase 静态门
#   ② 二进制 --selftest（Store/Classifier/Importer/Watcher 全走生产函数）
#   ③ 装机后 Info.plist 回读 ⟺ catalog.yaml

if [ "${SKIP_FLEET_GATE:-0}" != "1" ]; then
  _GATE="$HOME/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py"
  if [ -f "$_GATE" ]; then
    /opt/homebrew/bin/python3 "$_GATE" "$(cd "$(dirname "$0")" && pwd)" \
      || { echo "❌ CodingKey 契约门未过，拒绝构建（临时绕过 SKIP_FLEET_GATE=1）"; exit 1; }
  else
    echo "❌ 找不到舰队门 ${_GATE} —— 拒绝静默跳过"; exit 1
  fi
fi

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="Clipbook"
DISPLAY_NAME="$(grep -E '^display_name:' catalog.yaml | head -1 | sed -E 's/^display_name:[[:space:]]*//; s/[[:space:]]*#.*//')"
BUNDLE_ID="$(grep -E '^bundle_id:' catalog.yaml | head -1 | sed -E 's/^bundle_id:[[:space:]]*//; s/[[:space:]]*#.*//')"
[ -n "$DISPLAY_NAME" ] && [ -n "$BUNDLE_ID" ] || { echo "❌ catalog.yaml 缺 display_name / bundle_id"; exit 1; }

_XCODE_ENV_SH=/Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
[ -f "$_XCODE_ENV_SH" ] || { echo "❌ 缺总部 Xcode SSOT $_XCODE_ENV_SH" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_XCODE_ENV_SH"
xcode_env_use macosx

echo "→ swiftc 编译（release）…"
mkdir -p build
# glob 不手列：手列的话新增 .swift 会被静默漏编
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
  Sources/Native/*.swift Sources/ClipbookApp.swift \
  -o "build/${APP_NAME}"

echo "→ 跑 --selftest…"
"build/${APP_NAME}" --selftest || { echo "❌ selftest 未过，拒绝出包"; exit 1; }

echo "→ 打包 .app…"
APP="build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "build/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
[ -f icon/AppIcon.icns ] || { echo "❌ 缺 icon/AppIcon.icns（make_icon.py 生成，禁白板出厂）"; exit 1; }
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>${APP_NAME}</string>
	<key>CFBundleName</key><string>${APP_NAME}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>LSUIElement</key><true/>
	<key>CFBundleURLTypes</key>
	<array><dict>
		<key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
		<key>CFBundleURLSchemes</key><array><string>clipbook</string></array>
	</dict></array>
</dict>
</plist>
PLIST

echo "→ post-build：DisplayName / BundleID / Icon / Version…"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier  -string "$BUNDLE_ID"    "$APP/Contents/Info.plist"
plutil -replace CFBundleIconFile    -string "AppIcon"       "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion     -string "$(git -C "$DIR" rev-list --count HEAD)" "$APP/Contents/Info.plist"

# 签名：优先用本机的 Apple Development 证书。理由不是分发（不分发），是 TCC：
# 辅助功能授权按「代码签名身份」记，adhoc 签名每次重编都换 cdhash，授权就得重点一次；
# 用固定证书，授权一次以后每次重编都还在。没证书就退回 adhoc（授权会失效，build 输出会说）。
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p' | head -1)}"
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
  echo "   签名：$SIGN_ID"
else
  codesign --force -s - "$APP"
  echo "   ⚠ 未找到 Apple Development 证书，adhoc 签名 —— 每次重编后辅助功能授权要重新点"
fi

if [ "${1:-}" = "--build-only" ]; then
  echo "Built: $APP"
  exit 0
fi
DEST="/Applications/$DISPLAY_NAME.app"
if [ -e "$DEST" ]; then
  ARCHIVE="$HOME/.Trash/app-previous-$(date +%s)"
  mkdir -p "$ARCHIVE"
  mv "$DEST" "$ARCHIVE/"
fi
ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Installed: $DEST"
_GOT_DN="$(plutil -extract CFBundleDisplayName raw "$DEST/Contents/Info.plist")"
_GOT_ID="$(plutil -extract CFBundleIdentifier  raw "$DEST/Contents/Info.plist")"
if [ "$_GOT_DN" != "$DISPLAY_NAME" ] || [ "$_GOT_ID" != "$BUNDLE_ID" ]; then
  echo "❌ 装机 plist 与 catalog.yaml 漂移：[$_GOT_DN/$_GOT_ID] vs [$DISPLAY_NAME/$BUNDLE_ID]"; exit 1
fi
echo "✅ 已安装 → ${DEST}"
echo "   启动: open -a \"${DISPLAY_NAME}\"   菜单栏常驻，点图标开窗口；自动化 open 'clipbook://show'（无快捷键）"
