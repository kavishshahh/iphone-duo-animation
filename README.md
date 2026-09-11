# Still

Free, open source iPhone Duo-style lid animation for Mac. Close your MacBook lid and the desktop tilts, frosts over and dims with it. A small menu bar app written in Swift, Metal and SwiftUI. MIT licensed.

Website and interactive demo: https://still.akki.dev

**Status:** early prototype. The code is written and the geometry is unit tested, but it has not been exercised on real Macs yet. It needs people with sensor-equipped MacBooks (14/16-inch Pro from 2021, Air from M2) to run it and report back. Open an issue with your model identifier and what the "Your Mac" tab says.

## Build

macOS 14+, Xcode Command Line Tools, Apple Silicon.

```sh
bash native/scripts/build.sh
open native/build/Still.app
```

See [`native/README.md`](native/README.md) for how it works, its limits, and what still needs testing. The GitHub Actions workflow builds `Still.app` on every push and attaches it as an artifact.

## Layout

- `native/` Swift package: `FoldCore` (projection math, gesture state, tests) and the `Still` app (IOKit lid sensor, ScreenCaptureKit snapshot, Metal overlay, SwiftUI settings).
- `site/` the landing page and browser demo. `node site/server.mjs` serves it on http://127.0.0.1:4173; add `--lan` to reach it from other devices on the same Wi-Fi. `node --test site/test/*.test.mjs` runs the shared geometry tests.
- `FEASIBILITY.md` the research that started this.

## Credits

The HID report layout for the lid angle sensor follows the findings of [Sam Henri Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) (Apache 2.0). The browser demo uses [three.js](https://threejs.org) (MIT). The wallpaper was made for this project.

Independent project, not affiliated with Apple. iPhone, iPhone Duo, Mac and MacBook are trademarks of Apple Inc.
