import XCTest
@testable import FoldCore

final class FoldCoreTests: XCTestCase {
    func testWorkingPlaneIsIdentityAcrossScreen() throws {
        for angle in [75.0, 90, 105, 135] {
            for u in [0.0, 0.2, 0.5, 0.9, 1] {
                for v in [0.0, 0.3, 0.7, 1] {
                    let uv = try XCTUnwrap(FoldMath.sourceUV(u: u, v: v, angle: angle, workingAngle: angle, aspect: 1.6))
                    XCTAssertEqual(uv.0, u, accuracy: 1e-10)
                    XCTAssertEqual(uv.1, v, accuracy: 1e-10)
                }
            }
        }
    }
    func testHingeIsStationary() throws {
        for angle in [18.0, 30, 60, 90, 105] {
            let uv = try XCTUnwrap(FoldMath.sourceUV(u: 0.5, v: 1, angle: angle, workingAngle: 105, aspect: 1.6))
            XCTAssertEqual(uv.0, 0.5, accuracy: 1e-10)
            XCTAssertEqual(uv.1, 1, accuracy: 1e-10)
        }
    }
    func testBadTuningCannotProduceNaN() {
        var t = FoldTuning()
        t.workingAngle = .nan
        t.fadeAngle = .infinity
        XCTAssertEqual(t.validated.workingAngle, 105)
        XCTAssertEqual(t.validated.fadeAngle, 18)
        XCTAssertEqual(FoldMath.progress(angle: .nan, tuning: t), 0)
    }
    func testSmoothingIsIndependentOfFrameRate() {
        var slow = 105.0
        var fast = 105.0
        for _ in 0..<30 { slow = FoldMath.smooth(current: slow, target: 30, dt: 1.0/30, response: 0.5) }
        for _ in 0..<120 { fast = FoldMath.smooth(current: fast, target: 30, dt: 1.0/120, response: 0.5) }
        XCTAssertEqual(slow, fast, accuracy: 1e-9)
    }
    func testFailureRequiresReopeningBeforeRecapture() {
        var gate = GestureGate()
        XCTAssertEqual(gate.update(angle: 103, workingAngle: 105), .idle)
        XCTAssertEqual(gate.update(angle: 100, workingAngle: 105), .captureRequested)
        gate.fail()
        XCTAssertEqual(gate.update(angle: 60, workingAngle: 105), .suppressed)
        XCTAssertEqual(gate.update(angle: 105, workingAngle: 105), .idle)
        XCTAssertEqual(gate.update(angle: 99, workingAngle: 105), .captureRequested)
        gate.captured()
        XCTAssertEqual(gate.state, .active)
    }
    func testReopeningWhileCapturePendingInvalidatesGesture() {
        var gate = GestureGate()
        gate.update(angle: 70, workingAngle: 105)
        gate.update(angle: 105, workingAngle: 105)
        gate.captured()
        XCTAssertEqual(gate.state, .idle)
    }
}
