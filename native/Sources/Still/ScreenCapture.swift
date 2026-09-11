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

@MainActor
enum DesktopCapture {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
    }

    static func snapshot(screen: NSScreen) async throws -> CGImage {
        guard isAllowed else { throw CaptureIssue.permission }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw CaptureIssue.noDisplay
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
            throw CaptureIssue.noDisplay
        }
        // Excluding Still prevents feedback and keeps the settings window out of the gesture.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let pixelWidth = Double(CGDisplayPixelsWide(display.displayID))
        let pixelHeight = Double(CGDisplayPixelsHigh(display.displayID))
        let scale = min(1, 1800 / max(pixelWidth, 1))
        config.width = max(1, Int(pixelWidth * scale))
        config.height = max(1, Int(pixelHeight * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let picture = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        return picture
    }
}
