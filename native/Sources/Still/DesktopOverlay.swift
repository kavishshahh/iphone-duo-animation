import AppKit
import FoldCore

/// A full-screen overlay window.
///
/// In screen-saver mode it takes input so that any key, click or real mouse movement dismisses it,
/// the way a screen saver does. In gesture and preview modes it stays transparent to input.
final class OverlayPanel: NSPanel {
    var onDismiss: (@MainActor () -> Void)?
    /// Input only dismisses once armed. A screen saver that starts while the pointer is still
    /// drifting from the click that launched it would otherwise close in the same instant.
    var dismissOnInput = false
    /// The pointer position when input was armed; movement is measured against it so that a
    /// resting mouse reporting sub-pixel jitter does not count as "the user came back".
    var pointerAtArming: NSPoint = .zero

    override var canBecomeKey: Bool { dismissOnInput }
    override var canBecomeMain: Bool { false }

    private func dismiss() {
        guard dismissOnInput else { return }
        MainActor.assumeIsolated { onDismiss?() }
    }

    override func keyDown(with event: NSEvent) { dismiss() }
    override func mouseDown(with event: NSEvent) { dismiss() }
    override func rightMouseDown(with event: NSEvent) { dismiss() }
    override func otherMouseDown(with event: NSEvent) { dismiss() }
    override func scrollWheel(with event: NSEvent) { dismiss() }
    override func mouseMoved(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let moved = hypot(now.x - pointerAtArming.x, now.y - pointerAtArming.y)
        if moved > 12 { dismiss() }
    }
}

@MainActor
final class DesktopOverlay {
    private struct Layer {
        let panel: OverlayPanel
        let surface: FoldSurface
        let image: CGImage
    }

    private var layers: [Layer] = []
    var isVisible: Bool { layers.contains { $0.panel.isVisible } }

    /// Shows the fold across every captured display.
    ///
    /// `onDismiss` is non-nil only for screen-saver mode, which is also the only mode whose panels
    /// accept input.
    func show(shots: [DesktopShot], angle: Double, tuning: FoldTuning,
              onDismiss: (@MainActor () -> Void)? = nil) throws {
        hide()
        guard !shots.isEmpty else {
            throw NSError(domain: "Still", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "No display could be captured."])
        }

        var built: [Layer] = []
        for shot in shots {
            let surface = FoldSurface()
            guard surface.setupError == nil else {
                throw NSError(domain: "Still", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: surface.setupError ?? "Metal could not start."])
            }
            let panel = OverlayPanel(contentRect: shot.screen.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false, screen: shot.screen)
            panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            // Never flagged opaque: the window server may skip compositing a window it believes
            // is fully covering, and `opacity` below 1 has to blend with the desktop underneath.
            panel.isOpaque = false
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            // Excluded from screen capture so the fold never feeds back into its own snapshot.
            panel.sharingType = .none
            panel.ignoresMouseEvents = (onDismiss == nil)
            panel.acceptsMouseMovedEvents = (onDismiss != nil)
            panel.onDismiss = onDismiss
            panel.contentView = surface
            panel.setFrame(shot.screen.frame, display: false)

            surface.update(image: shot.image, angle: angle, tuning: tuning)
            guard surface.setupError == nil else {
                let message = surface.setupError ?? "The captured frame could not be rendered."
                hide()
                throw NSError(domain: "Still", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
            }
            built.append(Layer(panel: panel, surface: surface, image: shot.image))
        }
        layers = built

        // The snapshot is pixel-identical to the live desktop, so a very short fade hides
        // the moment the projected copy replaces it instead of letting it pop in.
        for layer in layers {
            layer.panel.alphaValue = 0
            layer.panel.orderFrontRegardless()
            // Drive the view from its own clock while it is on screen. It previously relied on a
            // single `needsDisplay` set *before* the panel was ordered front: that draw can land
            // while the view still has no drawable, and nothing asks for another — leaving the
            // panel showing its opaque black background instead of the desktop.
            layer.surface.beginContinuousDisplay()
        }
        let target = tuning.validated.opacity
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            for layer in layers { layer.panel.animator().alphaValue = target }
        }
    }

    /// Arms screen-saver dismissal once the opening animation has settled.
    func armDismissal() {
        let pointer = NSEvent.mouseLocation
        for layer in layers {
            layer.panel.pointerAtArming = pointer
            layer.panel.dismissOnInput = true
        }
        layers.first?.panel.makeKeyAndOrderFront(nil)
    }

    func update(angle: Double, tuning: FoldTuning) {
        let opacity = tuning.validated.opacity
        for layer in layers {
            layer.surface.update(image: layer.image, angle: angle, tuning: tuning)
            // Applied on every update, not just at creation, so dragging the slider while the
            // effect is on screen shows the change immediately.
            if abs(layer.panel.alphaValue - opacity) > 0.001 { layer.panel.alphaValue = opacity }
        }
    }

    func hide() {
        for layer in layers {
            layer.panel.dismissOnInput = false
            layer.panel.onDismiss = nil
            layer.surface.endContinuousDisplay()
            layer.panel.orderOut(nil)
            layer.surface.clearSnapshot()
            layer.panel.close()
        }
        layers = []
    }
}
