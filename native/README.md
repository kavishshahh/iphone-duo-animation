# Still for Mac — free prototype

Still adds a perspective-and-frost effect to a temporary desktop snapshot. It includes an image preview, a four-second desktop demo, and sensor-driven closing/reversal on compatible MacBooks.

**Status:** native source is implemented but has not yet been compiled or exercised on macOS. This project was authored on Windows. Do not distribute it as a tested or notarized release.

The fastest way to get a first compile without a Mac at hand is to push this folder to GitHub: `.github/workflows/mac-build.yml` runs the tests and builds `Still.app` on a macOS runner and attaches it as a downloadable artifact.

## Build on your Mac

Requires macOS 14+, Xcode 15+ or its Command Line Tools, and an Apple Silicon Mac. The Swift package can also target Intel, but Intel support is untested.

1. Download and unzip the source archive.
2. In Terminal, enter the extracted folder.
3. Run:

```sh
bash native/scripts/build.sh
open native/build/Still.app
```

If developer tools are missing, run `xcode-select --install` first. You can also double-click `Build Still.command` after macOS permits it. The build script runs the core tests before producing `native/build/Still.app`. No paid Apple Developer account is needed for this local build.

## Try it

- Use the slider or Play in the preview window. No capture permission is needed.
- Choose **Your Mac → Allow** for Screen Recording, following any restart prompt from macOS.
- Choose **Preview on desktop** to play one four-second snapshot animation. It clears automatically.
- On a compatible laptop, set your normal working angle and turn on **Follow lid**.
- Use the Still menu bar item to pause or quit. Escape clears the effect while Still's window has keyboard focus; it is intentionally not a system-wide keyboard hook.

The M1 Air and 13-inch M1/M2 MacBook Pro do not have the required sensor according to current community hardware research. Their manual preview remains usable. A detected sensor is capability evidence, not a guarantee for every model or OS.

## Prototype limits

- Captures one image at the start of a gesture. Video and changing windows look frozen during the effect.
- Uses IOKit to read an undocumented Apple HID feature report at approximately 30 Hz. This interface may vary by hardware and macOS version.
- Automatic mode only affects the internal display. The explicit manual demo can run on the main display if no internal one exists.
- Reverses as the lid opens while the session is awake. Sleep/lock pauses automatic mode; re-enable it after unlocking. No login-screen animation.
- No Accessibility permission, keyboard injection, window manipulation, sleep prevention, account, telemetry, network requests, payment code or licensing code.
- Appearance is a visual overlay. Underlying app hit targets are not transformed.
- Display/Spaces/HDR/protected-media behavior and performance still require physical Mac tests.

## Before calling this a release

On a real Mac: build and run tests, confirm the Metal shader compiles, grant/revoke capture access, exercise open-close-reverse gestures, check sleep/lock and rapid display changes, verify the snapshot disappears on errors, and profile idle/active load. Test an M1 manual fallback and at least one compatible Air and Pro.

For public DMG distribution, use Developer ID signing, hardened runtime and notarization. The current build performs only ad-hoc local signing.

## Compile-readiness pass (Sept 2026)

A review pass before the first Mac build fixed the things most likely to fail on `swift build` or misbehave at runtime:

- Every `Timer` and `NotificationCenter` callback now hops onto the main actor with `MainActor.assumeIsolated`. Those blocks are `@Sendable` in the macOS 14 SDK, so calling `@MainActor` methods from them directly is a compile error.
- `LidSensor` follows the discovery pattern that is known to work in the wild: match Apple product `0x8104` on the Sensor usage page, probe each candidate with open → read → close, release the `IOHIDManager`, then re-open only the device that answered. The old code closed the manager while still holding a device it had opened through it. Report byte 0 is no longer required to equal 1, and a hardware-present-but-unreadable interface now gets its own message instead of "not found".
- The sensor callback is typed `@MainActor`, so `AppModel` no longer converts an isolated closure to a nonisolated one.
- `captureAllowed` is set in `init` rather than as a stored-property default, which avoids the isolated-default-value ambiguity between Swift 5.9 and 5.10.
- The desktop overlay fades in over 120 ms instead of popping.
- The app activates itself on launch; `LSUIElement` apps otherwise open their first window behind everything else.

The web demo shares the projection math. `node --test site/test/*.test.mjs` runs the same assertions as `FoldCoreTests` against `fold-math.mjs`, and the CI workflow runs both.

## Architecture

- `FoldCore`: pure projection, smoothing and gesture state.
- `LidSensor`: serial background HID reads, invalid report rejection.
- `DesktopCapture`: ScreenCaptureKit screenshot; Still is excluded.
- `FoldSurface`: on-demand Metal rendering with mipmap-based progressive frost.
- `AppModel`: capture cancellation, stale-result guards, sensor timeout and power/session cleanup.

The mathematical implementation and app code are original. The HID report layout follows the documented findings of [Sam Henri Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor). No code from the unlicensed macTilt repository has been included. The wallpaper was generated specifically for this project.
