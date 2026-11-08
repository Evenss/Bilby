#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration="${1:-release}"
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
bundle="$PWD/build/Bilby.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_directory/BarTidy" "$bundle/Contents/MacOS/BarTidy"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
for language in en zh-Hans; do
    mkdir -p "$bundle/Contents/Resources/$language.lproj"
    cp "Sources/BarTidy/Resources/$language.lproj/Localizable.strings" "$bundle/Contents/Resources/$language.lproj/Localizable.strings"
done
cp LICENSE "$bundle/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp Resources/GitHubLink.pdf "$bundle/Contents/Resources/GitHubLink.pdf"
cp -R Resources/ThirdParty "$bundle/Contents/Resources/"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
fi
signing_identity="${BARTIDY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*) \([A-F0-9]*\) .*/\1/p' | head -1)}"
codesign --force --options runtime --sign "${signing_identity:--}" "$bundle"
codesign --verify --strict "$bundle"
python3 Tools/audit-input-control.py "$bundle/Contents/MacOS/BarTidy"
print -r -- "$bundle"
