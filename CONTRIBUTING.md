# Contributing to Bilby

Issues and pull requests in English or Chinese are welcome.

## Reporting issues

Use the bug report or feature request template. Include your macOS version and
build, Bilby version or commit, the affected app, and steps to reproduce.
For security vulnerabilities, follow [SECURITY.md](SECURITY.md).

## Project scope

- Native SwiftUI / AppKit on Apple Silicon, currently targeting macOS 27.2.
- Per-app icon visibility. No physical menu bar reordering, input simulation,
  cursor control, or accessibility actions against other apps.
- Preserve saved visibility choices and the independent order of the app's list.
- Keep the existing status button behavior, nonactivating panel, and reduced
  motion support. See [AGENTS.md](AGENTS.md) for implementation constraints.

## Build and validation

Install full Xcode and Python 3, then run:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
Tools/build.sh
```

The build includes signature verification and the source / binary input-control
audit. `BARTIDY_SIGN_IDENTITY=- Tools/build.sh` uses an ad hoc signature for local
validation without a signing certificate.

`Tools/package-dmg.sh` builds a preview DMG and a SHA-256 checksum in `build/`.
It defaults to ad hoc signing; a supplied `BARTIDY_SIGN_IDENTITY` can select a
distribution identity. Packaging does not perform Apple notarization. Release
notes must describe the actual signing / notarization status.

Changes to visibility behavior also need integration tests on macOS 27.2 with
Accessibility access. Quit Bilby first so its visibility assertion does not
interfere, then run:

```sh
Tools/integration-test.sh
```

For UI changes, verify real left-click open / close, outside-click dismissal,
Esc / Command-W, and that switching visibility leaves the panel in place. Add
screenshots when they help review. Restore any visibility choices changed while
testing, and remove temporary recordings or captures.

CI uses GitHub's `xcode-27` runner to build the app and DMG, run core tests, and audit the binary.
It does not launch the app or replace macOS 27.2 interaction and visibility tests.
Local validation notes are in [VALIDATION.md](VALIDATION.md).

## Pull requests

Keep changes focused. Describe the problem, resulting behavior, and validation
actually performed. Add meaningful tests for logic changes; documentation-only
edits do not need a Swift build. Keep English and Chinese README content aligned.

Contributions are provided under the project's [MIT License](LICENSE). Preserve
third-party notices and include the source and license of any added dependency.
Community participation follows [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
