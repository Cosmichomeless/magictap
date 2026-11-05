import CoreGraphics
import XCTest
@testable import MagicTapCore

final class TapDetectorTests: XCTestCase {
    private let origin = CGPoint(x: 500, y: 400)
    private let finger = TouchPoint(x: 0.5, y: 0.5)

    private func detector(_ tweak: (inout TapConfig) -> Void = { _ in }) -> TapDetector {
        var config = TapConfig()
        config.holdToDrag = false // enabled explicitly by the hold tests
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
            touches: [TouchPoint(x: 0.3, y: 0.5), TouchPoint(x: 0.7, y: 0.5)],
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

    // MARK: Grip (resting fingers)

    private let grip = [TouchPoint(x: 0.70, y: 0.87), TouchPoint(x: 0.30, y: 0.84)]

    /// Holds the mouse for `seconds`, one frame every 50 ms. Returns the last frame time.
    @discardableResult
    private func hold(_ d: TapDetector, _ fingers: [TouchPoint], seconds: TimeInterval, from t0: TimeInterval = 0) -> TimeInterval {
        var t = t0
        while t - t0 < seconds {
            XCTAssertNil(d.process(time: t, touches: fingers, cursor: origin))
            t += 0.05
        }
        return t
    }

    func testTapWhileGrippingIsLeftClick() {
        let d = detector()
        var t = hold(d, grip, seconds: 1)
        let tapping = grip + [finger]
        XCTAssertNil(d.process(time: t, touches: tapping, cursor: origin))
        t += 0.04
        XCTAssertNil(d.process(time: t, touches: tapping, cursor: origin))
        t += 0.04
        // Index lifts, the grip stays.
        XCTAssertEqual(d.process(time: t, touches: grip, cursor: origin), .leftClick)
    }

    func testTwoFingerTapWhileGrippingIsRightClick() {
        let d = detector()
        var t = hold(d, grip, seconds: 1)
        let tapping = grip + [finger, TouchPoint(x: 0.6, y: 0.5)]
        XCTAssertNil(d.process(time: t, touches: tapping, cursor: origin))
        t += 0.08
        XCTAssertEqual(d.process(time: t, touches: grip, cursor: origin), .rightClick)
    }

    func testGripAloneNeverClicks() {
        let d = detector()
        let t = hold(d, grip, seconds: 2)
        XCTAssertNil(d.process(time: t, touches: [], cursor: origin))
    }

    func testLiftingTheGripIsNotATap() {
        let d = detector()
        let t = hold(d, grip, seconds: 1)
        XCTAssertNil(d.process(time: t, touches: [grip[0]], cursor: origin))
        XCTAssertNil(d.process(time: t + 0.05, touches: [], cursor: origin))
    }

    func testGripFingerCreepingStaysResting() {
        let d = detector()
        var t = hold(d, grip, seconds: 1)
        // The grip drifts a little each frame; it must not look like a new finger.
        for step in 1 ... 6 {
            let drifted = grip.map { TouchPoint(x: $0.x, y: $0.y - 0.03 * Float(step)) }
            XCTAssertNil(d.process(time: t, touches: drifted, cursor: origin))
            t += 0.015
        }
        XCTAssertNil(d.process(time: t, touches: [], cursor: origin))
    }

    // MARK: Edge contacts (thumb / ring finger holding the mouse)

    private let edges = [TouchPoint(x: 0.06, y: 0.78), TouchPoint(x: 0.94, y: 0.55)]

    func testEdgeContactsLandingWithTheTapAreIgnored() {
        // Whole hand lands and lifts together, as in real use.
        XCTAssertEqual(tap(detector(), fingers: edges + [finger]), .leftClick)
    }

    func testEdgeContactsAloneNeverClick() {
        XCTAssertNil(tap(detector(), fingers: edges))
        XCTAssertNil(tap(detector(), fingers: [edges[0]], at: 20))
    }

    func testTwoFingerTapWithEdgeContactsIsRightClick() {
        let two = [finger, TouchPoint(x: 0.6, y: 0.5)]
        XCTAssertEqual(tap(detector(), fingers: edges + two), .rightClick)
    }

    func testEdgeFilterCanBeDisabled() {
        XCTAssertNil(tap(detector { $0.edgeMargin = 0 }, fingers: edges + [finger]))
    }

    func testFingerHoveringAtTheMarginIsNotSplitIntoTwoTaps() {
        // Real log: a tap starting inside the margin and drifting onto it must stay one contact.
        let d = detector()
        let xs: [Float] = [0.12, 0.11, 0.1001, 0.0999, 0.0998, 0.1001]
        var t = 0.0
        for x in xs {
            XCTAssertNil(d.process(time: t, touches: [TouchPoint(x: x, y: 0.9)], cursor: origin))
            t += 0.015
        }
        XCTAssertEqual(d.process(time: t, touches: [], cursor: origin), .leftClick)
    }

    func testContactLandingInsideTheEdgeZoneIsStillIgnored() {
        let d = detector()
        XCTAssertNil(tap(d, fingers: [TouchPoint(x: 0.05, y: 0.9)]))
    }

    func testIndexAndMiddleFingerNearTheSidesStillCount() {
        // Real log: taps with the index at x 0.21-0.33 and the middle finger at 0.76-0.84.
        XCTAssertEqual(tap(detector(), fingers: [TouchPoint(x: 0.84, y: 0.92)]), .leftClick)
        XCTAssertEqual(tap(detector(), fingers: [TouchPoint(x: 0.21, y: 0.94)]), .leftClick)
        let two = [TouchPoint(x: 0.33, y: 0.78), TouchPoint(x: 0.81, y: 0.87)]
        XCTAssertEqual(tap(detector(), fingers: two), .rightClick)
    }

    // MARK: Tap and drag

    /// Feeds a finger from `t0` for `seconds` at 15 ms per frame; returns the actions seen.
    private func press(
        _ d: TapDetector, _ at: TouchPoint = TouchPoint(x: 0.5, y: 0.5),
        from t0: TimeInterval, seconds: TimeInterval, cursor: (Int) -> CGPoint = { _ in CGPoint(x: 500, y: 400) }
    ) -> [TapAction] {
        var actions: [TapAction] = []
        var t = t0
        var i = 0
        while t <= t0 + seconds {
            if let a = d.process(time: t, touches: [at], cursor: cursor(i)) { actions.append(a) }
            t += 0.015
            i += 1
        }
        return actions
    }

    func testTapThenHoldStartsADragAndLiftEndsIt() {
        let d = detector()
        XCTAssertEqual(tap(d, fingers: [finger], at: 10), .leftClick)      // lifts at 10.08
        XCTAssertEqual(press(d, from: 10.2, seconds: 0.5), [.dragStart])
        XCTAssertTrue(d.isDragging)
        XCTAssertEqual(d.process(time: 11, touches: [], cursor: origin), .dragEnd)
        XCTAssertFalse(d.isDragging)
    }

    func testDragStartsWhereTheTouchBegan() {
        let d = detector()
        _ = tap(d, fingers: [finger], at: 10)
        // The mouse moves while the finger rests: the drag must start at the origin.
        _ = press(d, from: 10.2, seconds: 0.5, cursor: { CGPoint(x: 500 + $0 * 10, y: 400) })
        XCTAssertEqual(d.dragOrigin, origin)
    }

    func testDragSurvivesAStillFingerLongerThanTheGripThreshold() {
        let d = detector()
        _ = tap(d, fingers: [finger], at: 10)
        let actions = press(d, from: 10.2, seconds: 2)
        XCTAssertEqual(actions, [.dragStart]) // not ended by the resting-finger filter
        XCTAssertTrue(d.isDragging)
    }

    func testSecondQuickTapIsADoubleClickNotADrag() {
        let d = detector()
        XCTAssertEqual(tap(d, fingers: [finger], at: 10), .leftClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 10.2), .doubleClick)
        XCTAssertFalse(d.isDragging)
    }

    func testThirdTapStartsANewPair() {
        let d = detector()
        XCTAssertEqual(tap(d, fingers: [finger], at: 10), .leftClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 10.2), .doubleClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 10.4), .leftClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 10.6), .doubleClick)
    }

    func testSecondTapAfterTheWindowIsASingleClick() {
        let d = detector()
        XCTAssertEqual(tap(d, fingers: [finger], at: 10), .leftClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 10.7), .leftClick)
    }

    func testDoubleTapNeedsTheCursorToStayPut() {
        let d = detector()
        XCTAssertEqual(tap(d, fingers: [finger], at: 10), .leftClick)
        // The mouse moved a long way between the taps: a new target.
        XCTAssertNil(d.process(time: 10.2, touches: [finger], cursor: CGPoint(x: 400, y: 300)))
        XCTAssertNil(d.process(time: 10.24, touches: [finger], cursor: CGPoint(x: 400, y: 300)))
        XCTAssertEqual(d.process(time: 10.28, touches: [], cursor: CGPoint(x: 400, y: 300)), .leftClick)
    }

    func testDoubleTapWorksWithTapAndDragOff() {
        let d = detector { $0.tapAndDrag = false }
        XCTAssertEqual(tap(d, fingers: [finger], at: 10), .leftClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 10.2), .doubleClick)
    }

    func testDoubleTapCanBeDisabled() {
        let d = detector { $0.doubleTap = false }
        XCTAssertEqual(tap(d, fingers: [finger], at: 10), .leftClick)
        XCTAssertEqual(tap(d, fingers: [finger], at: 10.2), .leftClick)
    }

    func testTapThenHoldStillDragsWithDoubleTapOn() {
        let d = detector()
        _ = tap(d, fingers: [finger], at: 10)
        let actions = press(d, from: 10.2, seconds: 0.5)
        XCTAssertEqual(actions, [.dragStart])
    }

    func testScrollRightAfterATapIsNotADrag() {
        let d = detector()
        _ = tap(d, fingers: [finger], at: 10)
        var actions: [TapAction] = []
        var t = 10.2
        for step in 0 ..< 30 {
            if let a = d.process(time: t, touches: [TouchPoint(x: 0.5, y: 0.3 + 0.02 * Float(step))], cursor: origin) { actions.append(a) }
            t += 0.015
        }
        XCTAssertTrue(actions.isEmpty)
        XCTAssertFalse(d.isDragging)
    }

    func testNoDragWhenTheSecondTouchIsTooLate() {
        let d = detector()
        _ = tap(d, fingers: [finger], at: 10)
        XCTAssertTrue(press(d, from: 11.0, seconds: 0.5).isEmpty)
        XCTAssertFalse(d.isDragging)
    }

    func testTapAndDragCanBeDisabled() {
        let d = detector { $0.tapAndDrag = false }
        _ = tap(d, fingers: [finger], at: 10)
        XCTAssertTrue(press(d, from: 10.2, seconds: 0.5).isEmpty)
    }

    func testResetReleasesADrag() {
        let d = detector()
        _ = tap(d, fingers: [finger], at: 10)
        _ = press(d, from: 10.2, seconds: 0.5)
        XCTAssertTrue(d.reset())
        XCTAssertFalse(d.isDragging)
        XCTAssertFalse(d.reset())
    }

    func testRightClickTapDoesNotArmADrag() {
        let d = detector()
        let two = [finger, TouchPoint(x: 0.6, y: 0.5)]
        XCTAssertEqual(tap(d, fingers: two, at: 10), .rightClick)
        XCTAssertTrue(press(d, from: 10.2, seconds: 0.5).isEmpty)
    }

    // MARK: Hold to drag

    func testHoldingAStillFingerStartsADragWithoutATap() {
        let d = detector { $0.holdToDrag = true }
        XCTAssertEqual(press(d, from: 10, seconds: 0.5), [.dragStart])
        XCTAssertTrue(d.isDragging)
        XCTAssertEqual(d.dragOrigin, origin)
        XCTAssertEqual(d.process(time: 11, touches: [], cursor: origin), .dragEnd)
    }

    func testHoldDragSurvivesPastTheGripThreshold() {
        let d = detector { $0.holdToDrag = true }
        XCTAssertEqual(press(d, from: 10, seconds: 3), [.dragStart])
        XCTAssertTrue(d.isDragging)
    }

    func testMovingTheMouseWhileRestingIsNotAHoldDrag() {
        let d = detector { $0.holdToDrag = true }
        XCTAssertTrue(press(d, from: 10, seconds: 0.5, cursor: { CGPoint(x: 500 + $0 * 10, y: 400) }).isEmpty)
        XCTAssertFalse(d.isDragging)
    }

    func testSlidingTheFingerIsNotAHoldDrag() {
        let d = detector { $0.holdToDrag = true }
        var t = 10.0
        for step in 0 ..< 30 {
            XCTAssertNil(d.process(time: t, touches: [TouchPoint(x: 0.5, y: 0.3 + 0.02 * Float(step))], cursor: origin))
            t += 0.015
        }
        XCTAssertFalse(d.isDragging)
    }

    func testQuickTapStillClicksWithHoldToDragOn() {
        XCTAssertEqual(tap(detector { $0.holdToDrag = true }, fingers: [finger]), .leftClick)
    }

    func testHoldToDragCanBeDisabled() {
        let d = detector { $0.holdToDrag = false }
        XCTAssertTrue(press(d, from: 10, seconds: 0.5).isEmpty)
    }

    func testTwoFingersNeverHoldDrag() {
        let d = detector { $0.holdToDrag = true }
        var t = 10.0
        while t < 10.5 {
            XCTAssertNil(d.process(time: t, touches: [finger, TouchPoint(x: 0.6, y: 0.5)], cursor: origin))
            t += 0.015
        }
        XCTAssertFalse(d.isDragging)
    }

    // MARK: Two-finger swipe and pinch

    /// Two fingers over `frames` frames (15 ms each), interpolated between the two poses.
    private func twoFingers(
        _ d: TapDetector, from a: (TouchPoint, TouchPoint), to b: (TouchPoint, TouchPoint),
        frames: Int = 12, at t0: TimeInterval = 10
    ) -> [TapAction] {
        var actions: [TapAction] = []
        for i in 0 ..< frames {
            let f = Float(i) / Float(frames - 1)
            func lerp(_ p: TouchPoint, _ q: TouchPoint) -> TouchPoint {
                TouchPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f)
            }
            let touches = [lerp(a.0, b.0), lerp(a.1, b.1)]
            if let x = d.process(time: t0 + Double(i) * 0.015, touches: touches, cursor: origin) { actions.append(x) }
        }
        if let x = d.process(time: t0 + 1, touches: [], cursor: origin) { actions.append(x) }
        return actions
    }

    private func pair(_ y: Float, gap: Float = 0.2, x: Float = 0.5) -> (TouchPoint, TouchPoint) {
        (TouchPoint(x: x - gap / 2, y: y), TouchPoint(x: x + gap / 2, y: y))
    }

    func testTwoFingerSwipeTowardTheTipOpensMissionControl() {
        XCTAssertEqual(twoFingers(detector(), from: pair(0.4), to: pair(0.7)), [.missionControl])
    }

    func testTwoFingerSwipeTowardTheWristClosesMissionControl() {
        XCTAssertEqual(twoFingers(detector(), from: pair(0.7), to: pair(0.4)), [.missionControlClose])
    }

    func testSidewaysDownSwipeDoesNotClose() {
        let a = (TouchPoint(x: 0.3, y: 0.7), TouchPoint(x: 0.5, y: 0.7))
        let b = (TouchPoint(x: 0.6, y: 0.6), TouchPoint(x: 0.8, y: 0.6))
        XCTAssertTrue(twoFingers(detector(), from: a, to: b).isEmpty)
    }

    func testSidewaysTwoFingerSwipeDoesNothing() {
        XCTAssertTrue(twoFingers(detector(), from: pair(0.5, x: 0.35), to: pair(0.5, x: 0.65)).isEmpty)
    }

    func testOneFingerSwipeDoesNothing() {
        let d = detector()
        var t = 10.0
        for i in 0 ..< 12 {
            XCTAssertNil(d.process(time: t, touches: [TouchPoint(x: 0.5, y: 0.4 + 0.03 * Float(i))], cursor: origin))
            t += 0.015
        }
    }

    func testSwipeFiresOnlyOncePerContact() {
        let d = detector()
        XCTAssertEqual(twoFingers(d, from: pair(0.2), to: pair(0.8), frames: 20), [.missionControl])
    }

    private func total(_ actions: [TapAction]) -> Float {
        actions.reduce(0) { sum, action in
            if case let .magnify(amount, _) = action { return sum + amount }
            return sum
        }
    }

    func testPinchApartIsAContinuousPositiveMagnification() {
        let actions = twoFingers(detector(), from: pair(0.5, gap: 0.1), to: pair(0.5, gap: 0.4), frames: 20)
        guard case .magnify(_, .began)? = actions.first else { return XCTFail("no began: \(actions)") }
        XCTAssertEqual(actions.last, .magnify(0, .ended))
        XCTAssertGreaterThan(actions.count, 5) // fluid: many updates, not one step
        XCTAssertEqual(total(actions), 0.3 * 2.5, accuracy: 0.05)
    }

    func testPinchTogetherIsNegative() {
        let actions = twoFingers(detector(), from: pair(0.5, gap: 0.5), to: pair(0.5, gap: 0.15), frames: 20)
        XCTAssertLessThan(total(actions), -0.5)
        XCTAssertEqual(actions.last, .magnify(0, .ended))
    }

    func testLongPinchIsNotCutByTheGripFilter() {
        let actions = twoFingers(detector(), from: pair(0.5, gap: 0.1), to: pair(0.5, gap: 0.5), frames: 60) // 0.9 s
        XCTAssertEqual(total(actions), 0.4 * 2.5, accuracy: 0.05)
    }

    func testPinchEndsWhenOneFingerLifts() {
        let d = detector()
        var t = 10.0
        var actions: [TapAction] = []
        for i in 0 ..< 10 {
            let gap = 0.1 + 0.04 * Float(i)
            if let a = d.process(time: t, touches: [TouchPoint(x: 0.5 - gap / 2, y: 0.5), TouchPoint(x: 0.5 + gap / 2, y: 0.5)], cursor: origin) { actions.append(a) }
            t += 0.015
        }
        XCTAssertEqual(d.process(time: t, touches: [finger], cursor: origin), .magnify(0, .ended))
        XCTAssertNil(d.process(time: t + 0.1, touches: [], cursor: origin))
    }

    func testResetEndsAPinch() {
        let d = detector()
        _ = twoFingers(d, from: pair(0.5, gap: 0.1), to: pair(0.5, gap: 0.4), frames: 8)
        XCTAssertNil(d.process(time: 20, touches: [], cursor: origin)) // already ended
    }

    func testSwipeAndPinchCanBeDisabled() {
        let off = { (c: inout TapConfig) in c.missionControlSwipe = false; c.pinchZoom = false }
        XCTAssertTrue(twoFingers(detector(off), from: pair(0.4), to: pair(0.7)).isEmpty)
        XCTAssertTrue(twoFingers(detector(off), from: pair(0.5, gap: 0.1), to: pair(0.5, gap: 0.4)).isEmpty)
    }

    func testGestureDoesNotAlsoClick() {
        let d = detector()
        _ = twoFingers(d, from: pair(0.4), to: pair(0.7), frames: 8)
        XCTAssertFalse(d.isDragging)
    }

    func testTwoFingerTapStillRightClicksWithGesturesOn() {
        XCTAssertEqual(tap(detector(), fingers: [finger, TouchPoint(x: 0.6, y: 0.5)]), .rightClick)
    }
}
