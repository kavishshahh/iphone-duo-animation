# Still for Mac — free prototype

Still adds a perspective-and-frost effect to a temporary desktop snapshot. It includes an image preview, a four-second desktop demo, and sensor-driven closing/reversal on compatible MacBooks.

**Status:** native source is implemented but has not yet been compiled or exercised on macOS. This project was authored on Windows. Do not distribute it as a tested or notarized release.

The fastest way to get a first compile without a Mac at hand is to push this folder to GitHub: `.github/workflows/mac-build.yml` runs the tests and builds `Still.app` on a macOS runner and attaches it as a downloadable artifact.

## Get started on your Mac

Needs macOS 14 or later and an Apple Silicon Mac. No Xcode project and no Apple developer account. If any step fails, open an issue with the full terminal output and your model identifier.

1. **Unzip and open a terminal there.** Double-click `Still-source.zip` in Downloads (or clone the repo), then:
   ```sh
   cd ~/Downloads/Still-source
   ```
2. **Check the developer tools.** You need Apple's command line tools, not full Xcode.
   ```sh
   xcode-select -p
   ```
   If that prints a path you're set. If it errors, run `xcode-select --install`, click Install, wait a few minutes, then carry on.
3. **Build.**
   ```sh
   bash native/scripts/build.sh
   ```
   Tests run first, then a release build. Red text here is a compile error: paste it into an issue.
4. **Open the app.**
   ```sh
   open native/build/Still.app
   ```
   The Still window appears with the slider preview, which needs no permissions. Still also sits in the menu bar (a tilted rectangle icon).
5. **Allow Screen Recording and read the sensor line.** In the **Your Mac** tab click **Allow**. macOS opens System Settings; switch Still on, then quit and reopen the app if it asks. The line above says either "Lid sensor available" with a live angle, or "No readable lid-angle sensor". Note the model identifier under it (for example `Mac15,3`).
6. **Try it.** Click **Preview on desktop** for a four-second run on your real desktop. If the sensor was found, click **Use current lid** while sitting normally, switch on **Follow lid**, and close the lid slowly. Open it back up and the effect clears.

Built locally, so Gatekeeper won't complain; the app is signed ad hoc on your own machine. That also means macOS forgets the Screen Recording permission after each rebuild, which is normal for unsigned dev builds. The M1 Air and every 13-inch MacBook Pro have no lid sensor: on those, step 6 stops at the desktop preview.

Use the Still menu bar item to pause or quit. Escape clears the effect while Still's window has keyboard focus; it is intentionally not a system-wide keyboard hook. A detected sensor is capability evidence, not a guarantee for every model or OS.

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
- `FoldSurface`: on-demand Metal rendering; twelve-tap Poisson frost over a mip prefilter, with glow and dark-glass edge.
- `AppModel`: capture cancellation, stale-result guards, sensor timeout and power/session cleanup.

The mathematical implementation and app code are original. The HID report layout follows the documented findings of [Sam Henri Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor). No code from the unlicensed macTilt repository has been included. The wallpaper was generated specifically for this project.
