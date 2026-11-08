#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# A development certificate is not a distribution identity. Preview DMGs use
# ad hoc signing unless a distribution identity is explicitly supplied.
export BARTIDY_SIGN_IDENTITY="${BARTIDY_SIGN_IDENTITY:--}"
Tools/build.sh

app="$PWD/build/Bilby.app"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
architecture="$(/usr/bin/lipo -archs "$app/Contents/MacOS/BarTidy")"
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "Expected a three-component app version, got: $app_version"
    exit 1
fi
if [[ "$minimum_os" != "27.2" || "$architecture" != "arm64" ]]; then
    print -u2 "DMG packaging requires macOS 27.2 / arm64 app metadata."
    exit 1
fi

dmg_name="Bilby-${app_version}-macOS-arm64.dmg"
dmg_file="$PWD/build/$dmg_name"
if [[ -e "$dmg_file" || -e "$dmg_file.sha256" ]]; then
    print -u2 "Output already exists: $dmg_file"
    exit 1
fi
dmg_stage="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
cleanup() { rm -rf "$dmg_stage"; }
trap cleanup EXIT
ditto "$app" "$dmg_stage/Bilby.app"
ln -s /Applications "$dmg_stage/Applications"
cat > "$dmg_stage/Install.txt" <<EOF
Bilby $app_version — preview / 预发布

Requires macOS 27.2 and Apple Silicon.
1. Drag Bilby.app into Applications.
2. Open Bilby and grant Accessibility access in System Settings.

This preview is not notarized by Apple. If macOS blocks the first launch,
review Apple's guidance before choosing whether to allow this specific app:
https://support.apple.com/en-us/102445

需要 macOS 27.2 和 Apple Silicon。
将 Bilby.app 拖入 Applications，然后打开应用并授予辅助功能权限。
本预发布版尚未经过 Apple 公证。首次打开若被系统拦截，请参考上方
Apple 官方说明，由你决定是否允许此应用。

Source / 源码: https://github.com/Evenss/Bilby/tree/v$app_version
Licenses / 许可证: Bilby.app/Contents/Resources
EOF

hdiutil create -volname "Bilby $app_version" -srcfolder "$dmg_stage" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$dmg_file"
hdiutil verify "$dmg_file"
(
    cd "$PWD/build"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
    shasum -a 256 -c "$dmg_name.sha256"
)
print -r -- "$dmg_file"
print -r -- "$dmg_file.sha256"
