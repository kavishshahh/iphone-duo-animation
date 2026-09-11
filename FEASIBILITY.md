Feasibility assessment — desktop fold animation

Researched 11 September 2026. This is a research and architecture assessment; no native application or hardware prototype has been built or tested. The reference website's public page, styling, changelog, developer documentation, and public sensor implementations were inspected.

**Recommendation: start with a native macOS prototype, with automatic operation gated by a real sensor check.** The graphics are feasible. Universal automatic support across Apple Silicon models is not a defensible promise. Windows is a later, hardware-specific project.

The requested commercial direction is a $2 one-time purchase through Dodo Payments and a 50% discount for people who contact the creator by DM or email. Dodo is the user-selected provider. The user currently has an M1 Mac with 8 GB RAM; exact model and macOS version remain unconfirmed.

**What the reference establishes.** Bendy currently advertises a $4.99 purchase, screen capture rendered with Metal, native lid sensing, configurable appearance, and a menu-bar app. Its website combines a light neutral background, large product statement, interactive laptop demonstration, real footage, settings imagery, and requirements. These are reported product capabilities, not independently benchmarked behavior. [Bendy](https://trybendy.app/)

Its 0.4.0 changelog describes inverse perspective: a picture at the calibrated working angle is projected onto the moving panel from an assumed seated viewer position. This explains why the picture seems stationary in space. A fixed viewing assumption means the illusion depends on where the viewer sits. [Bendy changelog](https://trybendy.app/changelog)

**Hardware support comes before visual polish.** The maintained LidAngleSensor project identifies M1 Air and 13-inch M1/M2 MacBook Pro as lacking the required sensor. It lists the 14/16-inch Apple Silicon Pro families and newer Air hardware as candidates, while separately distinguishing physical sensor presence from a readable interface. Its hardware list is community evidence, not an Apple compatibility guarantee. [Hardware detection implementation](https://github.com/samhenrigold/LidAngleSensor/blob/main/LidAngleSensor/HardwareCompat.swift)

| Device category | Proposed behavior |
| --- | --- |
| User's M1 / 8 GB Mac | Develop and test graphics and manual controls; identify the exact machine before concluding sensor support. |
| M1 Air; 13-inch M1/M2 Pro | Manual slider or explicit preview action; no promise of angle tracking. |
| 14/16-inch Apple Silicon Pro; M2-and-later Air candidates | Probe the actual sensor and validate movement before enabling automatic mode. Test each advertised family and OS combination. |
| New or unrecognized MacBook | Probe capabilities; do not reject solely because its identifier is absent from a list. |
| Desktop Mac or external monitor | Optional manual preview; no built-in laptop hinge to follow. |

An open/closed switch cannot provide the intermediate angle needed for this effect. Camera estimation would add permission, lighting and viewpoint dependencies; it is not the initial solution for unsupported Macs. There is no established software-only substitute in this research that would make the same automatic effect reliable on every Apple Silicon machine.

**Proposed native architecture.** Use Swift and SwiftUI for settings and onboarding, AppKit for window and display management, IOKit HID for sensor access, ScreenCaptureKit for capture, and Metal/MetalKit for GPU rendering. Target macOS 14 initially, subject to an API availability audit and testing. Newer visual styling must have fallbacks on that minimum OS.

The runtime would perform these steps:

1. Detect the internal display and readable sensor. Calibrate the user's normal lid position and validate that readings change plausibly when moved.
2. Convert angle into normalized progress, smooth sensor noise, and use separate activation/clearing thresholds to avoid flickering around the working angle.
3. Capture the internal desktop into GPU-accessible image buffers. Exclude the overlay itself to prevent repeated capture of its own output.
4. Show a borderless, non-activating overlay on that display. Use an inverse projection anchored at the hinge, then add progressive blur, edge shading and a near-closed fade.
5. Reverse progress when the user reverses the lid while awake. Remove the overlay completely at the working angle and stop unnecessary capture/render work.
6. On permission loss, capture failure, sensor failure, display disconnection, sleep or session deactivation, hide the overlay and release cached frames.

This is a visual representation of the desktop; it does not transform the actual windows or their hit targets. During an active fold, normal clicking should not be presented as accurately aligned with the warped image. Avoid taking keyboard focus and keep a reliable menu-bar pause control. A global Escape shortcut is optional and should be tested for permission implications before adding it.

Apple supplies capture filters and streaming samples suitable for this pipeline. Screen Recording permission is required even when images remain in memory and nothing is saved. Disable audio capture. Preserve the operating system's capture indicators. [Apple capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

The sensor access uses public IOKit functions to read an undocumented hardware interface. That is different from having a stable, supported lid-angle API. The reference implementation reads a HID feature report using a timer. Bendy advertises event-driven sensing, but this research has not established a portable event-driven implementation across models. Start with measured, adaptive polling and investigate callbacks on supported devices. [Sensor implementation](https://github.com/samhenrigold/LidAngleSensor/blob/main/LidAngleSensor/LidAngleSensor.swift)

**Snapshot versus live capture.** Start the graphics proof with a bundled image and a manual angle control, which requires neither sensor hardware nor desktop capture. Next test a single desktop snapshot per gesture: simpler and less capture work, but videos and changing windows freeze. A live stream gives closer parity with Bendy, at the cost of capture latency, GPU/memory use and additional edge cases. Profile both on the user's M1. Do not promise zero idle CPU while a sensor timer is still running.

There is already a public Swift/Metal fold prototype using lid sensing and screen capture, which supports technical feasibility. Its README explicitly leaves opening behavior unfinished. No license file was visible at its repository root during inspection, so it should be treated as research evidence until reuse rights are established, not automatically adopted as the commercial codebase. [macTilt prototype](https://github.com/lqSky7/iphone-duo-macos-animation)

**Opening after full closure needs separate validation.** Reversing a partially closed lid while the machine is awake is straightforward in principle. After actual sleep, capture must resume and the active session must become available. A normal app cannot render while the computer is asleep. Treat login/lock screens as outside the initial effect and never display a cached private desktop over them. Test sleep/wake and session transitions explicitly, using the relevant system notifications. [Sleep notification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification), [session deactivation](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification)

Other release checks should cover Retina scaling, display changes, Spaces/full-screen apps, protected media, rapid direction changes, permission revocation, an idle lid, and a closed lid with an external display connected. These are test requirements, not currently verified support claims.

**Windows is technically possible on suitable hardware.** Microsoft exposes HingeAngleSensor for hinged dual-screen devices and provides screen capture APIs. A Windows version could use WinRT sensor access with Windows.Graphics.Capture and Direct3D rendering, in a separate native shell. However, Windows installation alone does not establish hinge-sensor availability. Ordinary lid-switch notifications provide only open/closed state, which cannot drive continuous animation. [HingeAngleSensor](https://learn.microsoft.com/en-us/uwp/api/windows.devices.sensors.hingeanglesensor), [lid switch notifications](https://learn.microsoft.com/en-us/windows/win32/power/power-setting-guids), [screen capture](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture)

Before estimating a Windows release, run a sensor probe on named target laptops. A manual animation is broadly achievable; automatic lid tracking requires a supported sensor/driver combination. Keep angle processing and projection math conceptually reusable, but expect platform-specific capture, rendering, permissions and packaging work.

**What is needed to build and ship.** The current M1 is a reasonable development starting point; build speed and graphics performance must be measured. Native compilation, signing and Mac testing need macOS and Xcode. This current workspace is on Windows, so a Mac build/test environment must be made available. A remote Mac can compile; real lid testing needs a physical compatible MacBook and someone moving its screen.

Before sales, obtain access to at least one compatible MacBook for the first proof, then several representative Air/Pro models through testers. Other prerequisites are a product name, original icon and visual assets, a support email/DM destination, domain/hosting, and a payment account approved for the seller's circumstances.

Distribute a Developer ID-signed, hardened, notarized app through a DMG initially. Apple currently charges $99 per year for the Developer Program, with regional pricing variations. The Mac App Store requires App Sandbox; direct notarized distribution makes sandboxing optional. Given the undocumented sensor dependency, validate direct distribution first and leave App Store eligibility uncommitted. [Apple membership](https://developer.apple.com/help/account/membership/program-enrollment), [distribution configuration](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

**Website and purchase proposal.** Build an original landing page around an interactive laptop hero, our own demonstration footage, $2 purchase button, clear compatibility information, and the line “DM or email me for 50% off.” Provide a free compatibility check before asking someone to buy. The website demonstration would use simulated angle input; the native app handles actual hardware and desktop capture.

For the Mac settings UI, use a live preview, automatic/manual mode, working-angle calibration, a small set of appearance controls, permissions status, launch-at-login, and pause. Begin with one well-tuned appearance. Additional presets can follow once the underlying geometry feels right.

Use Dodo Payments hosted checkout for the $2 one-time product. Issue a limited-use, product-specific 50% coupon when someone contacts the creator, reducing the price to $1 before applicable tax. Dodo supports percentage discounts and redemption limits. Use a coupon before purchase rather than a partial-refund promotion. [Dodo discounts](https://docs.dodopayments.com/features/discount-codes)

Attach a License Key entitlement and a Digital Files entitlement for automated license and installer delivery. The Mac app can use Dodo's public activation and validation endpoints without embedding a merchant API secret. Keep any product-management secrets on the server. Plan an update channel separately: Dodo's documentation says replacing delivered files affects future purchases, while earlier grants retain their issued versions. [Dodo license keys](https://docs.dodopayments.com/features/license-keys), [Dodo download delivery](https://docs.dodopayments.com/features/digital-product-delivery)

Dodo's published standard US card/wallet rate is 4% + $0.40. Simplified proceeds using only that base fee are:

| Price paid | Base transaction fee | Remaining before other costs |
| --- | --- | --- |
| $2.00 | $0.48 | $1.52 |
| $1.00 after 50% coupon | $0.44 | $0.56 |

These figures exclude tax effects, international-payment extras, payout/currency fees, refunds, support, hosting and development. Dodo lists an additional 1.5% for international payments, a distinct India-INR rate, and a $1 refund processing fee. Its public pricing page also lists a $5 payout fee below $1,000. The $1 offer is workable as a launch promotion but leaves a small contribution per sale. Verify the account's applicable rates and a $1 discounted test checkout before launch; no Dodo account or checkout has been configured in this research. [Current Dodo pricing](https://dodopayments.com/pricing)

**Suggested work order and estimates.** These are planning estimates for one experienced developer with working Mac access, not a delivery commitment:

| Stage | Result | Estimated engineering effort |
| --- | --- | --- |
| Hardware proof | Sensor detection and stable readings on a compatible laptop | 0.5–1 day |
| Graphics proof | Manual projection/blur preview, then captured desktop overlay | 1–3 days |
| Native alpha | Angle-driven closing/reversal, settings, error recovery and power handling | 3–5 days |
| Commercial beta | Compatibility testing, permission UX, installer, signing, payment flow and website | 4–8 days |

Allow roughly 2–4 working weeks for a credible small paid beta, assuming test hardware is available; account approval, tester availability and OS-specific failures can add elapsed time. The first useful milestone is a manually controlled graphics proof on the user's M1 plus a successful sensor probe on a borrowed compatible MacBook. Finish that before committing to an all-model marketing claim or building the full sales flow.
