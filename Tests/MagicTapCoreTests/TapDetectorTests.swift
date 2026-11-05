import CoreGraphics
import XCTest
@testable import MagicTapCore

final class TapDetectorTests: XCTestCase {
    private let origin = CGPoint(x: 500, y: 400)
    private let finger = TouchPoint(x: 0.5, y: 0.5)

    private func detector(_ tweak: (inout TapConfig) -> Void = { _ in }) -> TapDetector {
        var config = TapConfig()
        tweak(&config)
        return TapDetector(config: config)
    }

    /// Simulates fingers down at `t0`, a mid frame, and all up at `t0 + duration`.
    private func tap(
        _ d: TapDetector,
        fingers: [TouchPoint],
        duration: TimeInterval = 0.08,
        cursorEnd: CGPoint? = nil,
        at t0: TimeInterval = 10
    ) -> TapAction? {
        XCTAssertNil(d.process(time: t0, touches: fingers, cursor: origin))
        XCTAssertNil(d.process(time: t0 + duration / 2, touches: fingers, cursor: origin))
        return d.process(time: t0 + duration, touches: [], cursor: cursorEnd ?? origin)
    }

    func testSingleFingerTapIsLeftClick() {
        XCTAssertEqual(tap(detector(), fingers: [finger]), .leftClick)
    }

    func testTwoFingerTapIsRightClick() {
        let two = [finger, TouchPoint(x: 0.6, y: 0.5)]
        XCTAssertEqual(tap(detector(), fingers: two), .rightClick)
    }

    func testThreeFingerTapIsIgnored() {
        let three = [finger, TouchPoint(x: 0.6, y: 0.5), TouchPoint(x: 0.7, y: 0.5)]
        XCTAssertNil(tap(detector(), fingers: three))
    }

    func testLongContactIsNotATap() {
        XCTAssertNil(tap(detector(), fingers: [finger], duration: 0.5))
    }

    func testTooShortContactIsNoise() {
        XCTAssertNil(tap(detector(), fingers: [finger], duration: 0.005))
    }

    func testMovingFingerIsAScrollNotATap() {
        let d = detector()
        XCTAssertNil(d.process(time: 1.00, touches: [TouchPoint(x: 0.5, y: 0.30)], cursor: origin))
        XCTAssertNil(d.process(time: 1.05, touches: [TouchPoint(x: 0.5, y: 0.45)], cursor: origin))
        XCTAssertNil(d.process(time: 1.10, touches: [], cursor: origin))
    }

    func testCursorMovementCancelsTap() {
        let moved = CGPoint(x: origin.x + 40, y: origin.y)
        XCTAssertNil(tap(detector(), fingers: [finger], cursorEnd: moved))
    }

    func testPhysicalClickCancelsTap() {
        let d = detector()
        XCTAssertNil(d.process(time: 1.00, touches: [finger], cursor: origin))
        d.noteButtonEvent()
        XCTAssertNil(d.process(time: 1.08, touches: [], cursor: origin))
    }

    func testButtonEventDoesNotAffectNextTap() {
        let d = detector()
        d.noteButtonEvent() // no session: no effect
        XCTAssertEqual(tap(d, fingers: [finger]), .leftClick)
    }

    func testSecondFingerLandingDoesNotCountAsMovement() {
        let d = detector()
        XCTAssertNil(d.process(time: 1.00, touches: [TouchPoint(x: 0.3, y: 0.5)], cursor: origin))
        // Second finger far away shifts the centroid a lot, but nothing "moved".
        XCTAssertNil(d.process(
            time: 1.03,
            touches: [TouchPoint(x: 0.3, y: 0.5), TouchPoint(x: 0.9, y: 0.5)],
            cursor: origin
        ))
        XCTAssertEqual(d.process(time: 1.08, touches: [], cursor: origin), .rightClick)
    }

    func testDisabledActionsAreIgnored() {
        XCTAssertNil(tap(detector { $0.singleFingerLeftClick = false }, fingers: [finger]))
        let two = [finger, TouchPoint(x: 0.6, y: 0.5)]
        XCTAssertNil(tap(detector { $0.twoFingerRightClick = false }, fingers: two))
    }

    func testDetectorIsReusableAcrossTaps() {
        let d = detector()
        XCTAssertEqual(tap(d, fingers: [finger], at: 1), .leftClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 2), .leftClick)
    }

    func testResetDropsSession() {
        let d = detector()
        XCTAssertNil(d.process(time: 1.00, touches: [finger], cursor: origin))
        d.reset()
        XCTAssertNil(d.process(time: 1.08, touches: [], cursor: origin))
    }
}
