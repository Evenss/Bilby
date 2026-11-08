#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/build/Bilby.app"
result="$PWD/build/integration-result.json"
fixture_a="/Applications/BarTidy Fixture A.app"
fixture_b="/Applications/BarTidy Fixture B.app"
fixture_pids=()
fixture_paths=()
fixture_domains=()
cleanup() {
    for fixture_pid in "${fixture_pids[@]}"; do kill "$fixture_pid" 2>/dev/null || true; done
    for fixture in "${fixture_paths[@]}"; do rm -rf "$fixture"; done
    for domain in "${fixture_domains[@]}"; do defaults delete "$domain" >/dev/null 2>&1 || true; done
    rm -f /tmp/BarTidy-Fixture-A.json /tmp/BarTidy-Fixture-B.json
}
trap cleanup EXIT
for label in A B; do
    fixture="/Applications/BarTidy Fixture $label.app"
    if [[ -e "$fixture" ]]; then
        print -u2 "Fixture path already exists: $fixture"
        exit 1
    fi
    mkdir -p "$fixture/Contents/MacOS"
    fixture_paths+=("$fixture")
    fixture_domains+=("com.bartidy.fixture.$label")
    cp "$app/Contents/MacOS/BarTidy" "$fixture/Contents/MacOS/BarTidy"
    cp Resources/Info.plist "$fixture/Contents/Info.plist"
    mkdir -p "$fixture/Contents/Resources"
    cp -R "$app/Contents/Resources/en.lproj" "$app/Contents/Resources/zh-Hans.lproj" "$fixture/Contents/Resources/"
    /usr/bin/plutil -replace CFBundleIdentifier -string "com.bartidy.fixture.$label" "$fixture/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleName -string "BarTidy Fixture $label" "$fixture/Contents/Info.plist"
    /usr/bin/plutil -replace CFBundleDisplayName -string "BarTidy Fixture $label" "$fixture/Contents/Info.plist"
    /usr/bin/plutil -insert BTFixture -string "$label" "$fixture/Contents/Info.plist"
    codesign --force --options runtime --sign "$(security find-identity -v -p codesigning | sed -n 's/.*) \([A-F0-9]*\) .*/\1/p' | head -1)" "$fixture"
    open -g "$fixture"
    fixture_pid=""
    for attempt in {1..20}; do
        if fixture_pid="$(pgrep -f "^$fixture/Contents/MacOS/BarTidy$")"; then break; fi
        sleep 0.1
    done
    if [[ -z "$fixture_pid" ]]; then print -u2 "Fixture failed to launch"; exit 1; fi
    fixture_pids+=($fixture_pid)
done
sleep 4
"$app/Contents/MacOS/BarTidy" --integration-test "$result"
python3 - "$result" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
checks = ['accessibility', 'nativeVisibility', 'overflowInventoryPassed',
          'hideConfirmedInInventory', 'cancelPendingKeepsActiveAssertion',
          'systemOrderUnchanged', 'visibilityApplied', 'pointerUnchanged',
          'restorePassed', 'lateActivationCancelled', 'editorInitialHide',
          'editorTemporaryReveal', 'oneSwitchPerApp', 'restoreEndsReveal', 'switchAppliesHide',
          'switchExitsReveal', 'switchAppliesShow', 'switchPreservesStoredOrder',
          'switchAppendsDisplayOrder', 'refreshPreservesDisplayOrder',
          'editorIgnoresLegacyOrder', 'hiddenAppsOutsideSystemOrder',
          'revealedOrderMatchesSystem', 'shownPositionRefreshed',
          'unchangedHiddenSelectionEndsReveal', 'completed']
checks += ['editorBackgroundConfirmation', 'resumeReappliesSavedVisibility', 'resumeHideConfirmedInInventory']
checks += ['nativeErrorLocalized']
if result.get('pointerUnchanged') is False and result.get('pointerInputEvents', 0) > 0:
    print('Pointer-position check inconclusive: mouse movement occurred during sampling; no input was blocked.')
    checks.remove('pointerUnchanged')
print(json.dumps({key: result.get(key) for key in checks}, ensure_ascii=False, indent=2))
if result.get('error'): print(result['error'])
sys.exit(0 if all(result.get(key) is True for key in checks) else 1)
PY
