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
if [ "$SIGN_IDENTITY" != "-" ] && [ -z "$MACOS_CERT_SHA1" ]; then
    echo "❌ 无法确定签名证书 SHA-1，已停止打包；应用内更新必须钉住签名身份。" >&2
    exit 1
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
RESOURCE_BUNDLE="$(dirname "$BIN_PATH")/MenuBarMijia_MijiaCore.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "❌ 缺少本地化资源包 MenuBarMijia_MijiaCore.bundle" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/MenuBarMijia_MijiaCore.bundle"

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
    <!-- #57 External URL Scheme: menumijia://toggle?device=…, scene?name=…, ask?text=…
         App Intents themselves need Metadata.appintents, which Xcode's
         appintentsmetadataprocessor emits; SwiftPM does not produce the compiler's const-value
         side outputs, so Shortcuts discovery may require an Xcode-project build. The URL Scheme
         and in-app execution are unaffected. -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.jryang1997.MenuBarMijia.external</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>menumijia</string>
            </array>
        </dict>
    </array>
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

# App Intents 元数据（必需，#57）：快捷指令 / Siri / Spotlight 只从包内的
# Contents/Resources/Metadata.appintents 发现动作。Xcode 由 ExtractAppIntentsMetadata 构建阶段生成
# 它（真实调用参数已核对：--output 指向 `<Target>.appintents` 目录本身，另需 --bundle-identifier），
# 而 `swift build` 从不运行该阶段。缺这份元数据，动作在快捷指令里彻底不可见——是功能缺失而非可选
# 优化，所以拿不到 extract.actionsdata 时打包直接失败退出，绝不静默产出「动作未注册」的 App。
#
# 为什么主路径是 xcodebuild 而不是手动传旗标：
# - 处理器唯一的事实来源是 swiftc 写出的 `*.swiftconstvalues`（SupplementaryOutput）。
# - 驱动这份输出的 `-const-gather-protocols-list` 目前只存在于未发布的 swift main；已发布的
#   6.0/6.1/6.2/6.3 的 Options.td 里都没有它，Xcode 自己用的是 `-const-gather-protocols-file`
#   加 JSON 清单。用 `-Xswiftc` 硬塞这些参数在正式工具链上必然会失败或产不出文件。
# - Xcode 的构建图知道当前工具链的正确组合，因此让 xcodebuild 生成元数据、再取出
#   `<Target>.appintents`，是唯一在受支持工具链上可持续的保证方式。
# 若本机确实已由 `swift build` 落盘了 const values（未来 SwiftPM 支持），仍会先用它们跑一次，
# 省掉整包构建。
APP_INTENTS_MODULE="MenuBarMijiaApp"
APP_INTENTS_BUNDLE_ID="com.jryang1997.MenuBarMijia"
APP_INTENTS_DEPLOYMENT_TARGET="14.0"

# Xcode writes `extract.actionsdata` directly into `--output`; accept either that layout or a
# nested Metadata.appintents so both the processor and xcodebuild outputs can be harvested.
app_intents_bundle_dir() {
    local candidate="$1"
    if [ -f "$candidate/extract.actionsdata" ]; then
        printf '%s\n' "$candidate"
    elif [ -f "$candidate/Metadata.appintents/extract.actionsdata" ]; then
        printf '%s\n' "$candidate/Metadata.appintents"
    fi
}

generate_app_intents_metadata_via_xcode() {
    # Xcode's build graph requests const values itself and runs ExtractAppIntentsMetadata per target.
    local derived="$ROOT/.build/appintents-derived"
    command -v xcodebuild >/dev/null 2>&1 || return 1
    rm -rf "$derived"
    mkdir -p "$derived"

    # SwiftPM exposes one scheme per product; consult the list instead of assuming a name.
    local listing name
    local -a candidates=()
    listing="$(xcodebuild -list -json -derivedDataPath "$derived" 2>/dev/null || true)"
    while IFS= read -r name; do
        [ -n "$name" ] && candidates+=("$name")
    done < <(printf '%s' "$listing" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    candidates+=("$APP_INTENTS_MODULE")

    local built=0 scheme
    # macOS ships bash 3.2, where expanding an empty array under `set -u` is an error.
    for scheme in "${candidates[@]+"${candidates[@]}"}"; do
        case "$scheme" in
        *"$APP_INTENTS_MODULE"*) ;;
        *) continue ;;
        esac
        if xcodebuild \
            -scheme "$scheme" \
            -destination 'platform=macOS' \
            -configuration Release \
            -derivedDataPath "$derived" \
            build >/dev/null 2>&1; then
            built=1
            break
        fi
    done
    if [ "$built" = "0" ]; then
        echo "   （xcodebuild 未能构建含 $APP_INTENTS_MODULE 的 scheme；可用 xcodebuild -list 查看）" >&2
        rm -rf "$derived"
        return 1
    fi

    local bundle="" candidate resolved
    while IFS= read -r candidate; do
        resolved="$(app_intents_bundle_dir "$candidate")"
        if [ -n "$resolved" ]; then
            bundle="$resolved"
            break
        fi
    done < <(find "$derived" -type d -name '*appintents' 2>/dev/null)
    if [ -z "$bundle" ]; then
        rm -rf "$derived"
        return 1
    fi
    rm -rf "$APP_DIR/Contents/Resources/Metadata.appintents"
    cp -R "$bundle" "$APP_DIR/Contents/Resources/Metadata.appintents"
    rm -rf "$derived"
    return 0
}

generate_app_intents_metadata() {
    local developer_dir toolchain sdk_root xcode_version target_triple tmp processor
    local resources="$APP_DIR/Contents/Resources/Metadata.appintents"

    developer_dir="$(xcode-select -p 2>/dev/null || true)"
    toolchain="${developer_dir}/Toolchains/XcodeDefault.xctoolchain"
    sdk_root="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    xcode_version="$(xcodebuild -version 2>/dev/null | awk '/Build/ {print $3; exit}' || true)"
    target_triple="$(uname -m)-apple-macos${APP_INTENTS_DEPLOYMENT_TARGET}"
    processor="$toolchain/usr/bin/appintentsmetadataprocessor"

    rm -rf "$resources"

    # Fast path: SwiftPM already emitted const values (only on toolchains that support it).
    local constvals
    constvals="$(find "$ROOT/.build" -path "*$APP_INTENTS_MODULE.build*" -name '*.swiftconstvalues' 2>/dev/null || true)"
    if [ -n "$constvals" ] && [ -x "$processor" ]; then
        tmp="$(mktemp -d)"
        find "$ROOT/Sources/$APP_INTENTS_MODULE" -name '*.swift' > "$tmp/sources.txt"
        printf '%s\n' "$constvals" > "$tmp/constvals.txt"
        "$processor" \
            --toolchain-dir "$toolchain" \
            --module-name "$APP_INTENTS_MODULE" \
            --sdk-root "$sdk_root" \
            --xcode-version "$xcode_version" \
            --platform-family macOS \
            --deployment-target "$APP_INTENTS_DEPLOYMENT_TARGET" \
            --bundle-identifier "$APP_INTENTS_BUNDLE_ID" \
            --output "$tmp/Metadata.appintents" \
            --target-triple "$target_triple" \
            --binary-file "$BIN_PATH" \
            --source-file-list "$tmp/sources.txt" \
            --swift-const-vals-list "$tmp/constvals.txt" \
            --force --compile-time-extraction --no-app-shortcuts-localization \
            || true
        if [ -f "$tmp/Metadata.appintents/extract.actionsdata" ]; then
            cp -R "$tmp/Metadata.appintents" "$resources"
        fi
        rm -rf "$tmp"
    fi

    if [ ! -f "$resources/extract.actionsdata" ]; then
        echo "ℹ️ 生成 App Intents 元数据（xcodebuild ExtractAppIntentsMetadata）..."
        if ! generate_app_intents_metadata_via_xcode; then
            echo "❌ 无法生成 App Intents 元数据（Metadata.appintents）。" >&2
            echo "   缺了它，快捷指令 / Siri / Spotlight 看不到任何动作，属于 #57 的交付缺失，已中止打包。" >&2
            echo "   排查：xcode-select -p 必须指向完整 Xcode；xcodebuild -list 应列出 $APP_INTENTS_MODULE。" >&2
            exit 1
        fi
    fi

    if [ ! -f "$resources/extract.actionsdata" ]; then
        echo "❌ 元数据目录缺少 extract.actionsdata，动作不会被系统注册，已中止打包。" >&2
        exit 1
    fi

    echo "🧩 已嵌入 App Intents 元数据：$(du -h "$resources/extract.actionsdata" | awk '{print $1}') extract.actionsdata（快捷指令 / Siri 可发现）"
}
generate_app_intents_metadata

if [ -n "$MACOS_CERT_SHA1" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    /usr/libexec/PlistBuddy -c "Delete :MijiaCodeSignCertSHA1" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :MijiaCodeSignCertSHA1 string $MACOS_CERT_SHA1" "$APP_DIR/Contents/Info.plist"
    echo "🔏 已钉住代码签名证书 SHA-1：$MACOS_CERT_SHA1"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "⚠️ 未设置 MACOS_SIGNING_IDENTITY：使用 ad-hoc 签名，仅适合本机运行，应用内更新已禁用；发布包必须用固定证书签名。"
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
