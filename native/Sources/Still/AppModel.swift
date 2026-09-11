import AppKit
import SwiftUI
import Combine
import FoldCore

@MainActor
final class AppModel: ObservableObject {
    @Published var tuning = FoldTuning() { didSet { saveTuning() } }
    @Published var previewAngle = 105.0
    @Published var sensorAngle: Double?
    @Published var sensorMessage = "Checking this Mac…"
    @Published var message = "Try the preview. Desktop mode asks for Screen Recording access."
    @Published var captureAllowed = false
    @Published var isBusy = false
    @Published var playingPreview = false
    @Published var automaticEnabled = false {
        didSet {
            if !automaticEnabled { cancelGesture() }
            else { gate.reset(); message = "Following your lid. Reopen to your working angle to clear the effect." }
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
        sensor = LidSensor { [weak self] reading in self?.receive(reading) }
        rescan()
        observePowerAndSession()
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

    func requestCaptureAccess() {
        // macOS labels this permission "record this computer's screen and audio" for every app
        // that asks, even one that takes a single screenshot with audio disabled, as Still does.
        message = "macOS will say Still wants to record your screen and audio. That is Apple's wording for the permission; Still takes one snapshot and never records audio or video."
        _ = CGRequestScreenCaptureAccess()
        captureAllowed = DesktopCapture.isAllowed
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
        if sensorAngle != reading.angle { sensorAngle = reading.angle }
        if sensorMessage != reading.message { sensorMessage = reading.message }
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
        guard let screen = DesktopCapture.builtInScreen() else {
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
                let image = try await DesktopCapture.snapshot(screen: screen)
                guard !Task.isCancelled, self.gestureID == id,
                      self.sessionAvailable, self.automaticEnabled,
                      self.gate.state == .captureRequested else { return }
                self.smoothedAngle = self.sensorAngle ?? self.tuning.workingAngle
                try self.overlay.show(image: image, screen: screen, angle: self.smoothedAngle, tuning: self.tuning)
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

    func playDesktopDemo() {
        guard sessionAvailable else { return }
        automaticEnabled = false
        cancelGesture()
        captureAllowed = DesktopCapture.isAllowed
        guard captureAllowed else { requestCaptureAccess(); return }
        guard let screen = DesktopCapture.builtInScreen() ?? NSScreen.main else { return }
        let id = UUID()
        gestureID = id
        isBusy = true
        message = "Playing a four-second desktop preview. It clears automatically."
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await DesktopCapture.snapshot(screen: screen)
                guard !Task.isCancelled, self.gestureID == id, self.sessionAvailable else { return }
                try self.overlay.show(image: image, screen: screen, angle: self.tuning.workingAngle, tuning: self.tuning)
                self.captureTask = nil
                let began = Date.timeIntervalSinceReferenceDate
                self.renderTimer = self.mainTimer(every: 1.0 / 60) { [weak self] in
                    guard let self else { return }
                    let elapsed = Date.timeIntervalSinceReferenceDate - began
                    guard elapsed < 4 else {
                        self.cancelGesture()
                        self.message = "Desktop preview finished."
                        return
                    }
                    let fold = 0.5 - 0.5 * cos(elapsed / 4 * 2 * .pi)
                    let angle = self.tuning.workingAngle - (self.tuning.workingAngle - 36) * fold
                    self.overlay.update(angle: angle, tuning: self.tuning)
                }
            } catch {
                guard self.gestureID == id else { return }
                self.cancelGesture()
                self.message = error.localizedDescription
            }
        }
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
            self?.captureAllowed = DesktopCapture.isAllowed
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
