import Foundation
import IOKit.hid
import Darwin

struct SensorReading {
    let angle: Double?
    let message: String
}

/// Reads the MacBook lid-angle sensor through IOKit HID.
///
/// All HID state lives on one background queue. Readings are delivered on the
/// main actor. A failed report never reuses a stale angle.
///
/// Discovery mirrors the pattern that is known to work in practice
/// (Sam Henri Gold's LidAngleSensor): match Apple product 0x8104 on the standard
/// Sensor usage page, probe each candidate with open → read → close, release the
/// manager, then re-open only the device that answered for polling.
final class LidSensor {
    private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)
    private static let pollInterval: DispatchTimeInterval = .milliseconds(33)
    private static let failureLimit = 5
    private static let retryDelay: DispatchTimeInterval = .seconds(2)

    private let queue = DispatchQueue(label: "app.still.sensor", qos: .userInitiated)
    private let report: @MainActor (SensorReading) -> Void
    private var timer: DispatchSourceTimer?
    private var device: IOHIDDevice?
    private var failures = 0

    init(report: @escaping @MainActor (SensorReading) -> Void) { self.report = report }

    deinit {
        timer?.cancel()
        if let device { IOHIDDeviceClose(device, Self.noOptions) }
    }

    func start() {
        queue.async { [self] in startOnQueue() }
    }

    private func startOnQueue() {
        stopOnQueue()
        switch Self.probe() {
        case .readable(let candidate):
            guard IOHIDDeviceOpen(candidate, Self.noOptions) == kIOReturnSuccess else {
                publish(nil, "The lid sensor was found but could not be opened. Manual preview is available.")
                return
            }
            device = candidate
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(3))
            clock.setEventHandler { [weak self] in self?.poll() }
            timer = clock
            clock.resume()
        case .vendorSpecificOnly:
            publish(nil, "This Mac has lid-sensor hardware, but it is exposed through an interface Still cannot read yet. Manual preview works.")
        case .notFound:
            publish(nil, "No readable lid-angle sensor. Manual preview works on this Mac.")
        }
    }

    func stop() { queue.async { [self] in stopOnQueue() } }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        if let device { IOHIDDeviceClose(device, Self.noOptions) }
        device = nil
        failures = 0
    }

    // MARK: Discovery

    private enum ProbeResult {
        case readable(IOHIDDevice)
        case vendorSpecificOnly
        case notFound
    }

    private static func probe() -> ProbeResult {
        // Strategy 1: standard Sensor page (0x0020), Orientation usage (0x008A).
        // Three spellings of the same match (they are OR-ed): the exact dictionary the
        // reference app ships, the primary-usage keys, and the device usage-pair keys.
        let standard: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: 0x05AC, kIOHIDProductIDKey as String: 0x8104,
             "UsagePage": 0x0020, "Usage": 0x008A],
            [kIOHIDVendorIDKey as String: 0x05AC, kIOHIDProductIDKey as String: 0x8104,
             kIOHIDPrimaryUsagePageKey as String: 0x0020, kIOHIDPrimaryUsageKey as String: 0x008A],
            [kIOHIDVendorIDKey as String: 0x05AC,
             kIOHIDDeviceUsagePageKey as String: 0x0020, kIOHIDDeviceUsageKey as String: 0x008A]
        ]
        for candidate in devices(matching: standard) {
            guard IOHIDDeviceOpen(candidate, noOptions) == kIOReturnSuccess else { continue }
            let angle = read(candidate)
            IOHIDDeviceClose(candidate, noOptions)
            if angle != nil { return .readable(candidate) }
        }
        // Strategy 2: the hardware exists but only under a vendor-specific page.
        let vendor: [[String: Any]] = [[kIOHIDVendorIDKey as String: 0x05AC, kIOHIDProductIDKey as String: 0x8104]]
        if !devices(matching: vendor).isEmpty { return .vendorSpecificOnly }
        return .notFound
    }

    private static func devices(matching dictionaries: [[String: Any]]) -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
        IOHIDManagerSetDeviceMatchingMultiple(manager, dictionaries as CFArray)
        guard IOHIDManagerOpen(manager, noOptions) == kIOReturnSuccess else { return [] }
        defer { IOHIDManagerClose(manager, noOptions) }
        let found = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        return Array(found)
    }

    // MARK: Reading

    /// Feature report 1: byte 0 is the report ID, bytes 1–2 the angle in degrees, little-endian.
    private static func read(_ device: IOHIDDevice) -> Double? {
        var bytes = [UInt8](repeating: 0, count: 8)
        var count = CFIndex(bytes.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count)
        guard result == kIOReturnSuccess, count >= 3 else { return nil }
        let degrees = Double(UInt16(bytes[2]) << 8 | UInt16(bytes[1]))
        // The hinge cannot exceed a flat lid; anything larger is a garbage report.
        guard (0...200).contains(degrees) else { return nil }
        return degrees
    }

    private func poll() {
        guard let device else { return }
        guard let angle = Self.read(device) else {
            failures += 1
            if failures == Self.failureLimit {
                // Re-probe rather than give up. Reads fail for reasons that pass on their own —
                // another process holding the device, a sleep/wake transition — and a permanent
                // stop turned any of those into a sensor that stays dead until the user finds the
                // Rescan button, with every lid feature disabled meanwhile and no hint why.
                publish(nil, "Lid sensor interrupted. Reconnecting…")
                stopOnQueue()
                queue.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
                    self?.startOnQueue()
                }
            }
            return
        }
        failures = 0
        // Every successful read is published, so the app can treat it as a heartbeat.
        publish(angle, "Lid sensor available")
    }

    private func publish(_ angle: Double?, _ message: String) {
        let reading = SensorReading(angle: angle, message: message)
        let report = self.report
        DispatchQueue.main.async {
            MainActor.assumeIsolated { report(reading) }
        }
    }

    // MARK: Model

    static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown Mac" }
        var value = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(decoding: value.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}
