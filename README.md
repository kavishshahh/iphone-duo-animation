# Still

Free, open source iPhone Duo-style lid animation for Mac. Close your MacBook lid and the desktop tilts, frosts over and dims with it. A small menu bar app written in Swift, Metal and SwiftUI. MIT licensed.

Website and interactive demo: https://www.iphoneduoanimation.com

Free Duo animation for Mac setup guide: https://www.iphoneduoanimation.com/blog/duo-animation-for-mac/

**Status:** early prototype. The code is written and the geometry is unit tested, but it has not been exercised on real Macs yet. It needs people with sensor-equipped MacBooks (14/16-inch Pro from 2021, Air from M2) to run it and report back. Open an issue with your model identifier and what the "Your Mac" tab says.

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
   With full Xcode installed the geometry tests run first; with only the Command Line Tools the script says it's skipping them (XCTest ships inside Xcode) and goes straight to the release build. Red text after that is a compile error: paste it into an issue.
4. **Open the app.**
   ```sh
   open native/build/Still.app
   ```
   The Still window appears with the slider preview, which needs no permissions. Still also sits in the menu bar (a tilted rectangle icon).
5. **Allow Screen Recording and read the sensor line.** In the **Your Mac** tab click **Allow**. macOS opens System Settings; switch Still on, then quit and reopen the app if it asks. The line above says either "Lid sensor available" with a live angle, or "No readable lid-angle sensor". Note the model identifier under it (for example `Mac15,3`).
6. **Try it.** Click **Preview on desktop** for a four-second run on your real desktop. If the sensor was found, click **Use current lid** while sitting normally, switch on **Follow lid**, and close the lid slowly. Open it back up and the effect clears.

If Terminal says "Operation not permitted" inside Downloads, macOS is blocking it from that folder: allow Terminal under Privacy & Security → Files and Folders, or move the folder to your home directory first. Built locally, so Gatekeeper won't complain; the app is signed ad hoc on your own machine. That also means macOS forgets the Screen Recording permission after each rebuild, which is normal for unsigned dev builds. The M1 Air and every 13-inch MacBook Pro have no lid sensor: on those, step 6 stops at the desktop preview.

See [`native/README.md`](native/README.md) for how it works, its limits, and what still needs testing. The GitHub Actions workflow builds `Still.app` on every push and attaches it as an artifact.

## Layout

- `native/` Swift package: `FoldCore` (projection math, gesture state, tests) and the `Still` app (IOKit lid sensor, ScreenCaptureKit snapshot, Metal overlay, SwiftUI settings).
- `site/` the landing page and browser demo. `node site/server.mjs` serves it on http://127.0.0.1:4173; add `--lan` to reach it from other devices on the same Wi-Fi. `node --test site/test/*.test.mjs` runs the shared geometry tests.
- `FEASIBILITY.md` the research that started this.

## Credits

Contributors: [Akshay Sharma](https://akki.dev) and [Kavish Shah](https://kavish.vercel.app).

The HID report layout for the lid angle sensor follows the findings of [Sam Henri Gold's LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) (Apache 2.0). The browser demo uses [three.js](https://threejs.org) (MIT). The wallpaper was made for this project.

Independent project, not affiliated with Apple. iPhone, iPhone Duo, Mac and MacBook are trademarks of Apple Inc.
