#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -d "$ROOT/.git/hooks" ] && [ ! -e "$ROOT/.git/hooks/pre-commit" ]; then
    ln -s ../../scripts/check.sh "$ROOT/.git/hooks/pre-commit" 2>/dev/null || true
fi

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || echo 1.0.0)"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
# 留空 = 本机临时签名（只能自己用）；发布时需要固定证书：
#   MACOS_SIGNING_IDENTITY  codesign 身份名称（CI secret 导入后自动填）
#   MACOS_CERT_SHA1         该证书的 SHA-1（40 位十六进制），会写进 Info.plist 供更新校验钉住
# SIGN_IDENTITY 为旧调用方式（scripts/release.sh）保留。
SIGN_IDENTITY="${MACOS_SIGNING_IDENTITY:-${SIGN_IDENTITY:--}}"
MACOS_CERT_SHA1="$(printf '%s' "${MACOS_CERT_SHA1:-}" | tr 'A-F' 'a-f')"
if [ "$SIGN_IDENTITY" != "-" ] && [ -z "$MACOS_CERT_SHA1" ]; then
    MACOS_CERT_SHA1="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -v id="$SIGN_IDENTITY" 'index($0, id) { print $2; exit }' \
        | tr 'A-F' 'a-f' || true)"
fi
if [ "$SIGN_IDENTITY" != "-" ] && [ -z "$MACOS_CERT_SHA1" ]; then
    MACOS_CERT_SHA1="$(security find-certificate -c "$SIGN_IDENTITY" -p 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha1 2>/dev/null \
        | sed 's/^.*=//' \
        | tr -d ':' \
        | tr 'A-F' 'a-f' || true)"
fi
if [ -n "$MACOS_CERT_SHA1" ] && ! printf '%s' "$MACOS_CERT_SHA1" | grep -Eq '^[0-9a-f]{40}$'; then
    echo "❌ MACOS_CERT_SHA1 必须是 40 位十六进制证书 SHA-1" >&2
    exit 1
fi

echo "▶ 正在编译 MenuBarMijiaApp $VERSION (Release)..."
swift build -c release --product MenuBarMijiaApp

BIN_PATH="$(swift build -c release --show-bin-path)/MenuBarMijiaApp"
APP_DIR="$ROOT/MenuBarMijia.app"
rm -rf "$ROOT/米家控制中心.app" "$ROOT/MenuMijia.app"  # 清理旧名字产物

WAS_RUNNING=0
if pgrep -x MenuBarMijiaApp >/dev/null 2>&1; then
    WAS_RUNNING=1
    killall MenuBarMijiaApp 2>/dev/null || true
    sleep 0.5
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$ROOT/Resources/AppIcon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/AppIcon/AppIcon-Dark.icns" "$APP_DIR/Contents/Resources/AppIcon-Dark.icns"
cp "$ROOT/Resources/AppIcon/AppIcon-Light.icns" "$APP_DIR/Contents/Resources/AppIcon-Light.icns"
cp "$ROOT/Resources/AppIcon/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/MenuBarMijiaApp"
chmod +x "$APP_DIR/Contents/MacOS/MenuBarMijiaApp"
strip -S -x "$APP_DIR/Contents/MacOS/MenuBarMijiaApp"
if nm -ap "$APP_DIR/Contents/MacOS/MenuBarMijiaApp" | grep -q "/Users/"; then
    echo "❌ MenuBarMijiaApp 符号表中仍残留本地编译路径 (/Users/)！"
    exit 1
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
    <key>CFBundleDisplayName</key>
    <string>MenuBarMijia</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>MenuBarMijiaApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.jryang1997.MenuBarMijia</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MenuBarMijia</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>用于局域网自动发现并实时连接 Home Assistant 及电视等智能家居设备。</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_home-assistant._tcp</string>
    </array>
    <key>NSMicrophoneUsageDescription</key>
    <string>用于通过语音指令直接控制米家智能家居设备。</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>用于将您的中文语音指令实时识别为智能家居控制动作。</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

mkdir -p "$APP_DIR/Contents/Resources/zh-Hans.lproj"
cat > "$APP_DIR/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS_ZH'
"NSLocalNetworkUsageDescription" = "用于局域网自动发现并实时连接 Home Assistant 及电视等智能家居设备。";
"NSMicrophoneUsageDescription" = "用于通过语音指令直接控制米家智能家居设备。";
"NSSpeechRecognitionUsageDescription" = "用于将您的语音指令实时识别为智能家居控制动作。";
STRINGS_ZH

mkdir -p "$APP_DIR/Contents/Resources/en.lproj"
cat > "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS_EN'
"NSLocalNetworkUsageDescription" = "Used to automatically discover and connect to Home Assistant and smart TVs on your local network.";
"NSMicrophoneUsageDescription" = "Used to control your Xiaomi Home smart devices with voice commands.";
"NSSpeechRecognitionUsageDescription" = "Used to transcribe your voice commands into smart home actions in real time.";
STRINGS_EN

if [ -n "$MACOS_CERT_SHA1" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    /usr/libexec/PlistBuddy -c "Delete :MijiaCodeSignCertSHA1" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :MijiaCodeSignCertSHA1 string $MACOS_CERT_SHA1" "$APP_DIR/Contents/Info.plist"
    echo "🔏 已钉住代码签名证书 SHA-1：$MACOS_CERT_SHA1"
elif [ "$SIGN_IDENTITY" != "-" ]; then
    echo "⚠️ 使用了签名身份但拿不到证书 SHA-1；更新校验只能退回 Bundle ID 检查（Ed25519 仍兜底）。"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "⚠️ 未设置 MACOS_SIGNING_IDENTITY：使用 ad-hoc 签名，仅适合本机自更新；发布包必须用固定证书签名。"
    codesign --force --sign - "$APP_DIR"
else
    # 正式签名：开启 Hardened Runtime（苹果公证的前提），并声明麦克风权限。
    # 只有 Apple 签发的证书才向苹果申请时间戳；自签名证书没有 Apple 信任链，申请会失败。
    CODESIGN_ARGS=(--force --options runtime)
    if security find-certificate -c "$SIGN_IDENTITY" -p 2>/dev/null \
        | openssl x509 -noout -issuer 2>/dev/null \
        | grep -q "Apple"; then
        CODESIGN_ARGS+=(--timestamp)
    fi
    codesign "${CODESIGN_ARGS[@]}" \
        --entitlements "$ROOT/scripts/MenuBarMijia.entitlements" \
        --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
echo "✅ 已打包完成：$APP_DIR"

if [ "$WAS_RUNNING" = "1" ]; then
    open "$APP_DIR"
    echo "🔄 已自动重启 MenuBarMijia.app"
fi
