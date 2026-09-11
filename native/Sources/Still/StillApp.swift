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
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown() }
        }
        .defaultSize(width: 820, height: 680)
        .windowResizability(.contentSize)

        MenuBarExtra("Still", systemImage: "rectangle.on.rectangle.angled") {
            StillMenu(model: model)
        }
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
        Toggle("Follow lid", isOn: $model.automaticEnabled)
            .disabled(model.sensorAngle == nil || !model.captureAllowed)
        Button("Open Still…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Preview on desktop") { model.playDesktopDemo() }
            .disabled(model.isBusy)
        Button("Pause and clear") { model.pause() }
        Divider()
        Button("Quit Still") { model.shutdown(); NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
