import AppKit
import ScreenCaptureKit

enum CaptureIssue: LocalizedError {
    case permission, noDisplay
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Screen Recording in System Settings, then reopen Still if macOS asks."
        case .noDisplay: return "The requested display is no longer available."
        }
    }
}

/// One captured display, paired with the screen it came from.
struct DesktopShot {
    let screen: NSScreen
    let image: CGImage
}

@MainActor
enum DesktopCapture {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
    }

    /// The screen the user is currently looking at, best-effort: the one under the pointer,
    /// falling back to the main screen.
    ///
    /// The desktop effect used to be hard-targeted at the built-in display, which put it on the
    /// closed or ignored laptop panel whenever an external monitor was in use — the effect ran
    /// correctly somewhere the user was not looking.
    static func activeScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let pixelWidth = Double(CGDisplayPixelsWide(display.displayID))
        let pixelHeight = Double(CGDisplayPixelsHigh(display.displayID))
        let scale = min(1, 1800 / max(pixelWidth, 1))
        config.width = max(1, Int(pixelWidth * scale))
        config.height = max(1, Int(pixelHeight * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    /// Provokes the Screen Recording prompt by actually asking ScreenCaptureKit for content.
    ///
    /// `CGRequestScreenCaptureAccess()` is the older CoreGraphics entry point and, on this macOS,
    /// returns false without ever showing a dialog. Touching `SCShareableContent` is what makes
    /// the system register the app and ask. Returns whether access ended up granted.
    @discardableResult
    static func provokePermissionPrompt() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return isAllowed
        } catch {
            stillLog.notice("ScreenCaptureKit request refused: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func snapshot(screen: NSScreen) async throws -> CGImage {
        guard isAllowed else { throw CaptureIssue.permission }
        guard let wanted = displayID(of: screen) else { throw CaptureIssue.noDisplay }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == wanted }) else {
            throw CaptureIssue.noDisplay
        }
        // Excluding Still prevents feedback and keeps the settings window out of the gesture.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let picture = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                configuration: configuration(for: display))
        try Task.checkCancellation()
        return picture
    }

    /// Captures every attached display in one pass.
    ///
    /// The fold covers whole screens, so with more than one display a single-screen capture leaves
    /// the others showing an untouched desktop. Shares one `SCShareableContent` query: it is the
    /// slow part, and asking per display also risks the set changing between calls.
    static func snapshotAll() async throws -> [DesktopShot] {
        guard isAllowed else { throw CaptureIssue.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }

        var shots: [DesktopShot] = []
        for screen in NSScreen.screens {
            guard let wanted = displayID(of: screen),
                  let display = content.displays.first(where: { $0.displayID == wanted }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let picture = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                    configuration: configuration(for: display))
            try Task.checkCancellation()
            shots.append(DesktopShot(screen: screen, image: picture))
        }
        guard !shots.isEmpty else { throw CaptureIssue.noDisplay }
        return shots
    }
}
