import AppKit
import FoldCore

@MainActor
final class DesktopOverlay {
    private var panel: NSPanel?
    private var surface: FoldSurface?
    private var image: CGImage?
    var isVisible: Bool { panel?.isVisible ?? false }

    func show(image: CGImage, screen: NSScreen, angle: Double, tuning: FoldTuning) throws {
        hide()
        let surface = FoldSurface()
        guard surface.setupError == nil else {
            throw NSError(domain: "Still", code: 3, userInfo: [NSLocalizedDescriptionKey: surface.setupError ?? "Metal could not start."])
        }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false, screen: screen)
        panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.isReleasedWhenClosed = false
        panel.contentView = surface
        panel.setFrame(screen.frame, display: false)
        self.panel = panel
        self.surface = surface
        self.image = image
        surface.update(image: image, angle: angle, tuning: tuning)
        guard surface.setupError == nil else {
            let message = surface.setupError ?? "The captured frame could not be rendered."
            hide()
            throw NSError(domain: "Still", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
        }
        // The snapshot is pixel-identical to the live desktop, so a very short fade hides
        // the moment the projected copy replaces it instead of letting it pop in.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func update(angle: Double, tuning: FoldTuning) {
        surface?.update(image: image, angle: angle, tuning: tuning)
    }
    func hide() {
        panel?.orderOut(nil)
        surface?.clearSnapshot()
        panel?.close()
        panel = nil
        surface = nil
        image = nil
    }
}
