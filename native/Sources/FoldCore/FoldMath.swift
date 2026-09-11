import Foundation

public struct FoldTuning: Codable, Equatable {
    public var workingAngle: Double = 105
    public var fadeAngle: Double = 18
    public var perspective: Double = 0.8
    public var frost: Double = 0.55
    public var shade: Double = 0.35
    public var response: Double = 0.72
    /// How strongly the folded copy covers the real desktop. 1 replaces it outright; lower values
    /// let the untouched desktop show through, so the fold reads as a veil over the screen rather
    /// than a replacement of it.
    public var opacity: Double = 1.0
    public init() {}

    public var validated: Self {
        var value = self
        value.workingAngle = finiteClamp(workingAngle, 75, 135, fallback: 105)
        value.fadeAngle = finiteClamp(fadeAngle, 8, 28, fallback: 18)
        value.perspective = finiteClamp(perspective, 0, 1, fallback: 0.8)
        value.frost = finiteClamp(frost, 0, 1, fallback: 0.55)
        value.shade = finiteClamp(shade, 0, 1, fallback: 0.35)
        value.response = finiteClamp(response, 0, 1, fallback: 0.72)
        // Floored well above zero: an overlay at 0 is invisible but still swallows the screen in
        // screen-saver mode, which would read as the app being broken.
        value.opacity = finiteClamp(opacity, 0.15, 1, fallback: 1.0)
        return value
    }
}

public func finiteClamp(_ value: Double, _ lower: Double, _ upper: Double, fallback: Double) -> Double {
    value.isFinite ? min(upper, max(lower, value)) : fallback
}

public enum FoldMath {
    public static func progress(angle: Double, tuning: FoldTuning) -> Double {
        let t = tuning.validated
        return finiteClamp((t.workingAngle - angle) / (t.workingAngle - t.fadeAngle), 0, 1, fallback: 0)
    }

    public static func smooth(current: Double, target: Double, dt: Double, response: Double) -> Double {
        guard current.isFinite, target.isFinite else { return target.isFinite ? target : 105 }
        let elapsed = finiteClamp(dt, 0, 0.1, fallback: 0)
        let rate = 12 + finiteClamp(response, 0, 1, fallback: 0.72) * 34
        return current + (target - current) * (1 - exp(-rate * elapsed))
    }

    // Inverse projection: trace a ray from the viewer through the moving panel
    // and intersect the plane at the user's original working angle.
    // Coordinates: hinge at origin; +y up; +z toward the viewer; panel height = 1.
    public static func sourceUV(u: Double, v: Double, angle: Double, workingAngle: Double,
                                aspect: Double, eyeHeight: Double = 2.3, eyeDistance: Double = 2.6) -> (Double, Double)? {
        guard [u, v, angle, workingAngle, aspect, eyeHeight, eyeDistance].allSatisfy({ $0.isFinite }),
              aspect > 0 else { return nil }
        let a = angle * .pi / 180
        let w = workingAngle * .pi / 180
        let px = (u - 0.5) * aspect
        let py = (1 - v) * sin(a)
        let pz = (1 - v) * cos(a)
        let denominator = cos(w) * (py - eyeHeight) - sin(w) * (pz - eyeDistance)
        guard abs(denominator) > 0.00001 else { return nil }
        let ray = -(cos(w) * eyeHeight - sin(w) * eyeDistance) / denominator
        guard ray > 0 else { return nil }
        let x = ray * px
        let y = eyeHeight + ray * (py - eyeHeight)
        let z = eyeDistance + ray * (pz - eyeDistance)
        return (x / aspect + 0.5, 1 - (y * sin(w) + z * cos(w)))
    }
}

/// Hysteresis prevents a resting lid from repeatedly triggering capture.
/// Any failure suppresses a gesture until the lid returns to its working angle.
public struct GestureGate {
    public enum State: Equatable { case idle, captureRequested, active, suppressed }
    public private(set) var state: State = .idle
    public init() {}

    @discardableResult
    public mutating func update(angle: Double, workingAngle: Double) -> State {
        guard angle.isFinite else { fail(); return state }
        if angle >= workingAngle - 0.5 { state = .idle }
        else if state == .idle && angle <= workingAngle - 4 { state = .captureRequested }
        return state
    }
    public mutating func captured() {
        if state == .captureRequested { state = .active }
    }
    public mutating func fail() { state = .suppressed }
    public mutating func reset() { state = .idle }
}
