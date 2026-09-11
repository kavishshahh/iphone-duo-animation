import SwiftUI
import AppKit

@main
struct StillApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Still", id: "main") {
            SettingsView(model: model)
                // LSUIElement apps do not activate on launch; without this the first window
                // appears behind other apps and cannot take keyboard focus.
                .onAppear { presentMainWindow() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown() }
        }
        .defaultSize(width: 820, height: 680)
        .windowResizability(.contentSize)

        MenuBarExtra("Still", systemImage: "rectangle.on.rectangle.angled") {
            StillMenu(model: model)
        }
    }
}

/// Brings the settings window to whatever Space the user is actually looking at.
///
/// Still has no Dock icon (LSUIElement), so a window stranded on another Space cannot be reached
/// by clicking an icon — and `activate` alone switches the *user* to the window's Space rather
/// than bringing the window over. With a full-screen app on a display (its own Space), the window
/// is simply invisible and "Open Still…" appears to do nothing. `.moveToActiveSpace` makes the
/// window follow instead.
@MainActor
private func presentMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    // The window may not exist yet on the first `onAppear`; a hop to the next runloop pass is
    // enough for SwiftUI to have installed it.
    DispatchQueue.main.async {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true })
            ?? NSApp.windows.first(where: { $0.title == "Still" })
        else { return }
        window.collectionBehavior.insert(.moveToActiveSpace)

        // A restored frame can land the window off every display — a monitor that was
        // disconnected, a rearranged desktop, or SwiftUI simply placing it past the left edge.
        // With no Dock icon there is then nothing to click to bring it back, and the app looks
        // like it failed to launch. Judge by the window's CENTRE, not by intersection: a 40pt
        // sliver technically overlaps a screen while being useless.
        let centre = NSPoint(x: window.frame.midX, y: window.frame.midY)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(centre) }),
           let screen = NSScreen.main ?? NSScreen.screens.first {
            let area = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                          y: area.midY - size.height / 2))
        }

        window.makeKeyAndOrderFront(nil)
    }
}

private struct StillMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let angle = model.sensorAngle {
            Text("Lid: \(Int(angle))°")
        } else {
            Text("Manual preview available")
        }
        Button("Open Still…") {
            openWindow(id: "main")
            presentMainWindow()
        }
        Button("Apply") { model.applyToDesktop() }
            .disabled(model.isBusy || model.screenSaverActive)
        Button("Cancel") { model.cancelEffect() }
            .disabled(!model.effectOnScreen)
        Divider()
        Button("Quit Still") { model.shutdown(); NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
