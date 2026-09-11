import AppKit
import SwiftUI
import Combine
import OSLog
import FoldCore

/// Screen Recording is granted per code signature, so when it silently fails to stick nothing in
/// the UI distinguishes "never asked" from "asked and already refused". These lines make the real
/// TCC answer readable:
///   log show --predicate 'subsystem == "dev.akki.still"' --last 5m
let stillLog = Logger(subsystem: "dev.akki.still", category: "permission")

@MainActor
final class AppModel: ObservableObject {
    @Published var tuning = FoldTuning() { didSet { saveTuning() } }
    @Published var previewAngle = 105.0
    @Published var sensorAngle: Double?
    @Published var sensorMessage = "Checking this Mac…"
    @Published var message = "Checking this Mac…"
    @Published var captureAllowed = false
    @Published var isBusy = false
    @Published var playingPreview = false
    /// The desktop fold is being held indefinitely, until the user dismisses it.
    @Published var screenSaverActive = false
    @Published var automaticEnabled = false {
        didSet {
            if !automaticEnabled { cancelGesture(); return }
            gate.reset()
            // Adopt the lid's current angle as "open" unless it is already close to it.
            //
            // The effect is defined as starting just below the working angle, so a default of 105°
            // on a lid that rests at 133° means nothing happens until the screen is most of the
            // way shut — which reads as the feature being broken rather than as a setting being
            // wrong. Calibrating on enable makes "open = clear, start closing = fold" true for the
            // way this particular Mac is actually sitting.
            if let angle = sensorAngle, (75...135).contains(angle), abs(angle - tuning.workingAngle) > 6 {
                tuning.workingAngle = angle
                previewAngle = angle
                message = "Following your lid, with \(Int(angle))° set as open. Close it slowly to fold the desktop."
            } else {
                message = "Following your lid. Reopen to your working angle to clear the effect."
            }
        }
    }

    let modelIdentifier = LidSensor.modelIdentifier
    private let overlay = DesktopOverlay()
    private var gate = GestureGate()
    private var sensor: LidSensor?
    private var captureTask: Task<Void, Never>?
    private var gestureID = UUID()
    private var renderTimer: Timer?
    private var previewTimer: Timer?
    private var screenSaverTimer: Timer?
    private var previousTick = Date.timeIntervalSinceReferenceDate
    private var lastSensorTick = Date.timeIntervalSinceReferenceDate
    private var smoothedAngle = 105.0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sessionAvailable = true

    init() {
        if let data = UserDefaults.standard.data(forKey: "still.tuning"),
           let saved = try? JSONDecoder().decode(FoldTuning.self, from: data) {
            tuning = saved.validated
        }
        previewAngle = tuning.workingAngle
        captureAllowed = DesktopCapture.isAllowed
        // Ask once at launch when the core feature is unusable without it. Also the only way to
        // learn whether macOS still *offers* the prompt: a `false` return with no dialog means a
        // decision is already recorded against this signature and it will never ask again.
        if !captureAllowed {
            let granted = CGRequestScreenCaptureAccess()
            stillLog.notice("screen capture not yet granted; asking (CG returned \(granted, privacy: .public))")
            Task { [weak self] in
                let ok = await DesktopCapture.provokePermissionPrompt()
                stillLog.notice("screen capture after ScreenCaptureKit request: \(ok, privacy: .public)")
                self?.captureAllowed = DesktopCapture.isAllowed
                self?.refreshStatus()
            }
        }
        sensor = LidSensor { [weak self] reading in self?.receive(reading) }
        rescan()
        observePowerAndSession()
        refreshStatus()
    }

    /// Timers are scheduled on the main run loop, so their callbacks arrive on the
    /// main thread. `assumeIsolated` makes that explicit to the compiler instead of
    /// calling main-actor methods from a nonisolated `@Sendable` block.
    private func mainTimer(every interval: TimeInterval, _ body: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func saveTuning() {
        if let data = try? JSONEncoder().encode(tuning.validated) {
            UserDefaults.standard.set(data, forKey: "still.tuning")
        }
        overlay.update(angle: smoothedAngle, tuning: tuning)
    }

    func rescan() {
        cancelGesture()
        sensorAngle = nil
        sensorMessage = "Checking this Mac…"
        sensor?.start()
        captureAllowed = DesktopCapture.isAllowed
    }

    func calibrate() {
        guard let sensorAngle, (75...135).contains(sensorAngle) else {
            message = "Open the lid between 75° and 135°, then set the working angle."
            return
        }
        automaticEnabled = false
        tuning.workingAngle = sensorAngle
        previewAngle = sensorAngle
        message = "Working angle saved. Enable Follow lid to start."
    }

    /// Rewrites the idle status line from live state.
    ///
    /// `message` used to be set once at launch and then only by actions, so after granting Screen
    /// Recording it kept telling the user to grant Screen Recording — the app contradicting the
    /// buttons next to it. Only touches the line when nothing is running, so it never overwrites
    /// feedback from something the user just did.
    func refreshStatus() {
        guard !effectOnScreen else { return }
        if !captureAllowed {
            message = "Allow Screen Recording to fold the desktop. The slider preview works without it."
        } else if sensorAngle == nil {
            message = "Ready. Press Apply to fold the desktop; lid follow needs a readable hinge sensor."
        } else {
            message = "Ready. Press Apply, or turn on lid follow to fold as you close the screen."
        }
    }

    func requestCaptureAccess() {
        // macOS labels this permission "record this computer's screen and audio" for every app
        // that asks, even one that takes a single screenshot with audio disabled, as Still does.
        message = "macOS will say Still wants to record your screen and audio. That is Apple's wording for the permission; Still takes one snapshot and never records audio or video."
        let granted = CGRequestScreenCaptureAccess()
        captureAllowed = DesktopCapture.isAllowed
        // A `false` here with no prompt shown means macOS already has a decision on file for this
        // signature and will never ask again.
        stillLog.notice("screen capture request returned \(granted, privacy: .public)")
        if captureAllowed { message = "Screen Recording is available." }
        else if message.hasPrefix("macOS will say") { message += " Allow Still in Screen Recording, then reopen the app if asked." }
    }

    func openCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func applyPreset(_ name: String) {
        switch name {
        case "Clear": tuning.perspective = 0.8; tuning.frost = 0; tuning.shade = 0.12
        case "Frost": tuning.perspective = 0.8; tuning.frost = 0.55; tuning.shade = 0.35
        case "Soft": tuning.perspective = 0.55; tuning.frost = 0.9; tuning.shade = 0.15
        default: break
        }
    }

    func reset() {
        automaticEnabled = false
        tuning = FoldTuning()
        stopPreview()
        previewAngle = tuning.workingAngle
        message = "Default appearance restored."
    }

    func playPreview() {
        stopPreview()
        playingPreview = true
        let began = Date.timeIntervalSinceReferenceDate
        previewTimer = mainTimer(every: 1.0 / 60) { [weak self] in
            guard let self else { return }
            let elapsed = Date.timeIntervalSinceReferenceDate - began
            if elapsed >= 4 {
                self.stopPreview()
                self.previewAngle = self.tuning.workingAngle
                return
            }
            let fold = 0.5 - 0.5 * cos(elapsed / 4 * 2 * .pi)
            self.previewAngle = self.tuning.workingAngle - (self.tuning.workingAngle - 30) * fold
        }
    }

    func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        playingPreview = false
    }

    private func receive(_ reading: SensorReading) {
        lastSensorTick = Date.timeIntervalSinceReferenceDate
        let hadAngle = sensorAngle != nil
        if sensorAngle != reading.angle { sensorAngle = reading.angle }
        if sensorMessage != reading.message { sensorMessage = reading.message }
        if hadAngle != (sensorAngle != nil) { refreshStatus() }
        guard let angle = reading.angle else {
            automaticEnabled = false
            return
        }
        guard automaticEnabled, sessionAvailable else { return }
        let oldState = gate.state
        let state = gate.update(angle: angle, workingAngle: tuning.workingAngle)
        if state == .idle {
            if oldState != .idle { cancelGesture() }
        } else if state == .captureRequested && captureTask == nil {
            beginAutomaticCapture()
        }
    }

    private func beginAutomaticCapture() {
        // The lid sensor lives in the built-in display, so its absence means this Mac cannot drive
        // the gesture at all — but the fold itself covers every screen, since closing the lid on a
        // Mac with an external monitor should still fold what the user is looking at.
        guard DesktopCapture.builtInScreen() != nil else {
            gate.fail()
            message = "Automatic mode needs the built-in MacBook display."
            return
        }
        captureAllowed = DesktopCapture.isAllowed
        guard captureAllowed else {
            gate.fail()
            message = "Allow Screen Recording before using Follow lid."
            return
        }
        let id = UUID()
        gestureID = id
        isBusy = true
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let shots = try await DesktopCapture.snapshotAll()
                guard !Task.isCancelled, self.gestureID == id,
                      self.sessionAvailable, self.automaticEnabled,
                      self.gate.state == .captureRequested else { return }
                self.smoothedAngle = self.sensorAngle ?? self.tuning.workingAngle
                try self.overlay.show(shots: shots, angle: self.smoothedAngle, tuning: self.tuning)
                self.gate.captured()
                self.isBusy = false
                self.captureTask = nil
                self.startTrackingFrames()
            } catch {
                guard self.gestureID == id else { return }
                self.cancelGesture()
                self.gate.fail()
                self.message = error.localizedDescription
            }
        }
    }

    private func startTrackingFrames() {
        previousTick = Date.timeIntervalSinceReferenceDate
        renderTimer = mainTimer(every: 1.0 / 60) { [weak self] in
            guard let self else { return }
            let now = Date.timeIntervalSinceReferenceDate
            guard now - self.lastSensorTick < 0.5, let target = self.sensorAngle else {
                self.cancelGesture()
                self.gate.fail()
                self.message = "Sensor updates stopped. The desktop effect has been cleared."
                return
            }
            let next = FoldMath.smooth(current: self.smoothedAngle, target: target,
                dt: now - self.previousTick, response: self.tuning.response)
            self.previousTick = now
            if abs(next - self.smoothedAngle) > 0.01 {
                self.smoothedAngle = next
                self.overlay.update(angle: next, tuning: self.tuning)
            }
        }
    }

    // MARK: Apply and cancel

    /// True whenever something is on screen, or about to be, that Cancel would clear.
    ///
    /// Covers the armed lid gesture too: with lid-follow on there is nothing on screen yet, but
    /// closing the lid would put it there, and "Cancel" has to mean "and stay off".
    var effectOnScreen: Bool { screenSaverActive || isBusy || automaticEnabled }

    /// Switches the effect on.
    ///
    /// With a readable hinge sensor this arms the lid gesture: the screen stays exactly as it is
    /// while the lid is open, folds as the lid closes, and unfolds again as it reopens. It does
    /// NOT fold the desktop immediately — an effect that blurs a fully open screen is the thing
    /// people report as broken. Without a sensor there is no gesture to arm, so it falls back to
    /// folding and holding, which is the only thing such a Mac can show.
    func applyToDesktop() {
        guard sensorAngle != nil else {
            startScreenSaver()
            return
        }
        automaticEnabled = true
    }

    /// Clears the effect and stops it coming back — including the lid gesture, so cancelling
    /// cannot be undone a second later by the lid drifting a few degrees.
    func cancelEffect() {
        let had = effectOnScreen
        pause()
        message = had ? "Cancelled. Your desktop is back." : "Nothing to cancel."
    }

    // MARK: Screen saver

    /// Folds the desktop and HOLDS it there until the user dismisses it.
    ///
    /// The four-second preview answers "what does this look like?"; this answers "leave it up".
    /// It eases down to the resting angle and then stays, so any key, click or real mouse
    /// movement brings the desktop back — the interaction people already expect from a screen
    /// saver.
    func startScreenSaver() {
        guard sessionAvailable else { return }
        automaticEnabled = false
        cancelGesture()
        captureAllowed = DesktopCapture.isAllowed
        guard captureAllowed else { requestCaptureAccess(); return }
        let id = UUID()
        gestureID = id
        isBusy = true
        message = "Folding the desktop. Move the mouse or press a key to bring it back."
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let shots = try await DesktopCapture.snapshotAll()
                guard !Task.isCancelled, self.gestureID == id, self.sessionAvailable else { return }
                try self.overlay.show(shots: shots, angle: self.tuning.workingAngle, tuning: self.tuning,
                                      onDismiss: { [weak self] in self?.stopScreenSaver() })
                self.captureTask = nil
                self.screenSaverActive = true

                let began = Date.timeIntervalSinceReferenceDate
                let settle = 2.5
                let resting = max(self.tuning.fadeAngle + 6, 30.0)
                self.screenSaverTimer = self.mainTimer(every: 1.0 / 60) { [weak self] in
                    guard let self, self.screenSaverActive else { return }
                    let elapsed = Date.timeIntervalSinceReferenceDate - began
                    if elapsed >= settle {
                        // Held, not finished: the overlay stays until dismissed.
                        self.overlay.update(angle: resting, tuning: self.tuning)
                        return
                    }
                    // Ease out, so it comes to rest rather than stopping dead.
                    let t = elapsed / settle
                    let eased = 1 - pow(1 - t, 3)
                    self.overlay.update(angle: self.tuning.workingAngle
                        - (self.tuning.workingAngle - resting) * eased, tuning: self.tuning)
                }

                // Arm dismissal only after the opening move, so the pointer still travelling from
                // the click that started it does not close it immediately.
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard self.gestureID == id, self.screenSaverActive else { return }
                self.overlay.armDismissal()
            } catch {
                guard self.gestureID == id else { return }
                self.stopScreenSaver()
                self.message = error.localizedDescription
            }
        }
    }

    func stopScreenSaver() {
        let wasActive = screenSaverActive
        screenSaverActive = false
        screenSaverTimer?.invalidate()
        screenSaverTimer = nil
        cancelGesture()
        if wasActive { message = "Desktop restored." }
    }

    func cancelGesture() {
        gestureID = UUID()
        captureTask?.cancel()
        captureTask = nil
        renderTimer?.invalidate()
        renderTimer = nil
        overlay.hide()
        gate.reset()
        isBusy = false
    }

    func pause() {
        automaticEnabled = false
        screenSaverActive = false
        screenSaverTimer?.invalidate()
        screenSaverTimer = nil
        stopPreview()
        cancelGesture()
        message = "Paused. Your desktop is clear."
    }

    private func suspend() {
        sessionAvailable = false
        pause()
        sensor?.stop()
        sensorAngle = nil
        message = "Paused after sleep or a session change. Enable Follow lid again when ready."
    }

    private func resume() {
        sessionAvailable = true
        captureAllowed = DesktopCapture.isAllowed
        sensor?.start()
        // Deliberately require re-enabling automatic mode after sleep/lock in this prototype.
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        // Delivered on the main queue, so the main-actor hop is a formality for the compiler.
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }

    private func observePowerAndSession() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { [weak self] in self?.suspend() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { [weak self] in self?.resume() }
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.pause() }
        observe(.default, NSApplication.didBecomeActiveNotification) { [weak self] in
            // Coming back from System Settings is exactly when a grant changes under the app.
            self?.captureAllowed = DesktopCapture.isAllowed
            self?.refreshStatus()
        }
        // Additional best-effort lock signals; window level remains below the secure login UI.
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.suspend() }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.resume() }
    }

    func shutdown() {
        pause()
        sensor?.stop()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
