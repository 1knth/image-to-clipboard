# Clippy

A native macOS menu bar app: select a screen region, recognize text locally with Apple's Vision framework, and copy it to your clipboard. Requires macOS 14+ and Xcode command line tools to build.

## Build and run

```bash
bash scripts/build.sh
open build/Clippy.app
```

Press **Control–Shift–T** (T for text), drag over text, and release. Paste with **Command–V**. Escape cancels selection. Grant Clippy screen capture access when prompted; if necessary, quit and reopen after changing the permission.

Clippy launches directly into the menu bar without opening a window. Look for the **paperclip** icon. Choose **Capture Text** or **Settings…** from that menu. Reopening the app does not create a launcher window. Screen capture consent appears only when you initiate a capture. A compact native-style status panel uses macOS message typography and sizes to fit its text.

For startup diagnostics, run the executable directly in Terminal:

```bash
build/Clippy.app/Contents/MacOS/Clippy
```

Quit the existing instance first. Successful registration prints `shortcut registered` with the combination; capture actions print `capture requested`. These messages do not contain screen content.

### Permission recovery after rebuilding

macOS labels the permission **Screen & System Audio Recording**; Clippy sets audio capture to false. Rebuilding this ad-hoc signed development app can invalidate a previous permission grant. Quit all Clippy instances, remove the old Clippy entry in that settings pane, add the current `build/Clippy.app` with the plus button, enable it, and reopen the app using `open build/Clippy.app`. Avoid granting access to a different copy in Applications. Capture failures now show the failed stage, framework error code, and running app path so an enabled permission is not mistaken for a verified working capture.

The menu contains Capture Text, Cancel Capture, Settings, literal text mode, and a link to screen capture permissions. In **Settings**, click the shortcut recorder and press your preferred combination, then **Save Changes**. Include Control, Option, or Command; Escape cancels recording. **Restore Control–Shift–T** restores the default. Conflicting shortcuts are rejected without replacing the previous binding. Shortcuts use physical key positions and persist across launches. Capture shortcuts are paused while settings are open so recording does not trigger a scan.

Settings also provides a dropdown of supported OCR languages and a spelling-correction checkbox. Automatic detection is the default. Existing multi-language preferences are preserved. Disable correction for code and identifiers. Cancel discards unsaved changes.

## Verification

```bash
bash scripts/test.sh
```

Checks cover shortcut parsing, display geometry, Retina pixel sizing, line ordering, and actual Vision OCR on a generated text image. Real screen permission, selection exclusion, Spaces, external displays, shortcut registration, and pasteboard interaction need an interactive smoke test.

## Packaging

The build creates `build/Clippy.app`, including the executable at `Contents/MacOS/Clippy`. It is ad-hoc signed for local development. To use your own signing identity:

```bash
SCANNER_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/build.sh
```

Copy the app to Applications if desired. Production distribution still requires signing/notarization with your credentials. A stable identity helps avoid repeated permission grants after rebuilds.

The installed app is `/Applications/Clippy.app`. Open **Clippy** through Raycast's application search, or use `open /Applications/Clippy.app`. Builds update the workspace copy; copying a new build to Applications is a separate step. The existing bundle identifier is retained so preferences from Scanner migrate to Clippy.

The icon source is `Resources/Clippy.png`; `scripts/make-icon.sh` packages its standard macOS sizes into `Resources/Clippy.icns`. The build refreshes the icon package when its source changes.

## Behavior and limits

- Screenshots stay in memory; no screenshot files or OCR history are saved.
- Select within one display. You can start on any attached display.
- Capture occurs after release; moving content can change during selection.
- Plain text and line breaks are supported; exact code spacing and tables are not reconstructed.
- Captures above 32 megapixels or 12,000 pixels on either axis are rejected to bound memory use.
- Cancellation and failures before the clipboard commit preserve its contents. A pasteboard write failure after clearing cannot guarantee rollback.
- Cancellation during OCR prevents copying, but the in-flight OCR worker drains before another capture can begin.

Architecture and intended release requirements: [system design](SYSTEM_DESIGN.md) and [technical spec](TECHNICAL_SPEC.md). Settings uses native AppKit controls with custom shortcut recording. Optional login-at-startup is not implemented.
