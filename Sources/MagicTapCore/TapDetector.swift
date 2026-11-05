import CoreGraphics
import Foundation

/// A single finger contact in normalized sensor coordinates (0...1).
public struct TouchPoint: Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public enum GesturePhase: Equatable {
    case began, changed, ended
}

public enum TapAction: Equatable {
    case leftClick
    case rightClick
    /// Button goes down at `TapDetector.dragOrigin` (tap-and-drag started).
    case dragStart
    /// Button goes up (the finger that was dragging lifted).
    case dragEnd
    /// Two fingers swiped toward the tip of the mouse.
    case missionControl
    /// Two fingers swiped toward the wrist (closes Mission Control if it is open).
    case missionControlClose
    /// Continuous pinch: `amount` is the change in magnification for this frame
    /// (positive = fingers apart), like a trackpad magnify gesture.
    case magnify(Float, GesturePhase)
}

public struct TapConfig: Equatable {
    /// A contact longer than this is a rest/hold, not a tap.
    public var maxTapDuration: TimeInterval = 0.20
    /// Contacts shorter than this are treated as sensor noise.
    public var minTapDuration: TimeInterval = 0.02
    /// Max total finger path length (normalized units) during a tap.
    public var maxFingerTravel: Float = 0.04
    /// Max cursor movement (points) during a tap. Moving the mouse while a
    /// finger grazes the surface must not produce a click.
    public var maxCursorTravel: CGFloat = 4
    /// Contacts closer than this to the left/right edge (normalized x) are the
    /// thumb/ring finger holding the mouse and are never counted. 0 disables.
    public var edgeMargin: Float = 0.10
    /// A contact that was already counted keeps counting until it is this much
    /// deeper into the edge zone, so a finger hovering around the margin
    /// doesn't flicker in and out (which looked like a lift).
    public var edgeHysteresis: Float = 0.04
    /// A finger that has stayed on the surface longer than this is treated as
    /// part of the grip (thumb/ring finger holding the mouse) and ignored, so
    /// a tap with another finger still counts as a one-finger tap.
    public var restingAfter: TimeInterval = 0.30
    /// Max normalized distance a finger may move between frames and still be
    /// recognised as the same contact.
    public var trackRadius: Float = 0.12
    /// Tap, then touch again within this time and keep the finger still for
    /// longer than `maxTapDuration`: the button is held until the finger lifts.
    public var dragWindow: TimeInterval = 0.6
    public var tapAndDrag = true
    /// Rest one finger without moving it (nor the mouse) for this long and the
    /// button goes down, no prior tap needed. Must stay below `restingAfter`,
    /// which stops counting the finger.
    public var holdToDragAfter: TimeInterval = 0.25
    public var holdToDrag = true
    /// Two fingers moving this far (normalized) toward the tip open Mission Control.
    public var swipeDistance: Float = 0.12
    /// Two fingers changing their separation by this much (with the pair
    /// itself nearly still) starts a pinch.
    public var pinchStartDistance: Float = 0.05
    /// Magnification per unit of finger separation change. Higher = faster zoom.
    public var pinchGain: Float = 2.5
    public var missionControlSwipe = true
    public var pinchZoom = true
    public var singleFingerLeftClick = true
    public var twoFingerRightClick = true

    public init() {}
}

/// Turns a stream of multitouch frames into tap actions.
///
/// Feed every frame (including the empty one produced when all fingers lift)
/// to `process`. A tap is reported on the frame where the last finger lifts.
/// The type has no dependency on hardware or AppKit so it can be unit-tested.
public final class TapDetector {
    public var config: TapConfig

    private struct Session {
        var start: TimeInterval
        var startCursor: CGPoint
        var lastCentroid: TouchPoint
        var lastCount: Int
        var maxFingers: Int
        var travel: Float
        var invalid: Bool
        /// Started shortly after a left-click tap: may turn into a drag.
        var followsTap: Bool
        /// Where the two fingers were when the second one landed.
        var pairCentroid: TouchPoint?
        var pairDistance: Float = 0
        /// A swipe/pinch was already reported for this contact.
        var fired = false
        var lastSeparation: Float = 0
    }

    private struct Track {
        var position: TouchPoint
        var born: TimeInterval
    }

    private var session: Session?
    private var tracks: [Track] = []
    private var lastTapEnd: TimeInterval?
    private var dragging = false
    private var pinching = false

    /// True between `.dragStart` and `.dragEnd`.
    public var isDragging: Bool { dragging }
    /// Where the cursor was when the drag-starting touch began.
    public private(set) var dragOrigin: CGPoint = .zero

    public init(config: TapConfig = TapConfig()) {
        self.config = config
    }

    /// - Parameters:
    ///   - time: monotonic timestamp in seconds.
    ///   - touches: fingers currently touching the surface.
    ///   - cursor: current pointer location in screen points.
    public func process(time: TimeInterval, touches all: [TouchPoint], cursor: CGPoint) -> TapAction? {
        let touches = activeTouches(all, at: time)
        if touches.isEmpty {
            return finish(at: time, cursor: cursor)
        }
        if dragging { return nil } // the button stays down until all fingers lift

        let centroid = Self.centroid(of: touches)

        guard var s = session else {
            session = Session(
                start: time,
                startCursor: cursor,
                lastCentroid: centroid,
                lastCount: touches.count,
                maxFingers: touches.count,
                travel: 0,
                invalid: false,
                followsTap: config.tapAndDrag && touches.count == 1
                    && lastTapEnd.map { time - $0 <= config.dragWindow } == true
            )
            lastTapEnd = nil
            return nil
        }

        if pinching {
            guard touches.count == 2 else {
                pinching = false
                s.invalid = true
                session = s
                return .magnify(0, .ended)
            }
            let separation = Self.distance(touches[0], touches[1])
            let delta = separation - s.lastSeparation
            s.lastSeparation = separation
            session = s
            return delta == 0 ? nil : .magnify(delta * config.pinchGain, .changed)
        }

        // Only measure motion between frames with the same finger count:
        // adding/removing a finger shifts the centroid without any movement.
        if touches.count == s.lastCount {
            s.travel += Self.distance(centroid, s.lastCentroid)
        }
        s.lastCentroid = centroid
        s.lastCount = touches.count
        s.maxFingers = max(s.maxFingers, touches.count)

        if touches.count == 2, s.maxFingers == 2, !s.fired {
            let separation = Self.distance(touches[0], touches[1])
            if let start = s.pairCentroid {
                if let gesture = swipeGesture(from: start, centroid: centroid) {
                    s.fired = true
                    s.invalid = true
                    session = s
                    return gesture
                }
                let spread = separation - s.pairDistance
                let moved = Self.distance(centroid, start)
                if config.pinchZoom, abs(spread) >= config.pinchStartDistance, moved <= abs(spread) / 2 {
                    pinching = true
                    s.fired = true
                    s.invalid = true
                    s.lastSeparation = separation
                    session = s
                    return .magnify(spread * config.pinchGain, .began)
                }
            } else {
                s.pairCentroid = centroid
                s.pairDistance = separation
            }
        }

        let held = time - s.start
        let still = !s.invalid && s.maxFingers == 1 && s.travel <= config.maxFingerTravel
        let cursorStill = Self.distance(cursor, s.startCursor) <= config.maxCursorTravel
        if still, s.followsTap {
            // Finger resting after a tap: moving the cursor is allowed (that is
            // the drag). Sliding the finger is a scroll, handled below.
            if held > config.maxTapDuration { return beginDrag(s) }
        } else if still, config.holdToDrag, cursorStill {
            // A still finger on a still mouse may become a drag; don't discard
            // the session for lasting longer than a tap while we wait.
            if held >= config.holdToDragAfter { return beginDrag(s) }
        } else if held > config.maxTapDuration
            || s.travel > config.maxFingerTravel
            || !cursorStill {
            s.invalid = true
        }
        session = s
        return nil
    }

    /// Sensor y grows toward the tip of the mouse, so "up" is +y (open) and
    /// "down" is -y (close), like the trackpad.
    private func swipeGesture(from start: TouchPoint, centroid: TouchPoint) -> TapAction? {
        let dx = centroid.x - start.x
        let dy = centroid.y - start.y
        if config.missionControlSwipe, dy >= config.swipeDistance, abs(dx) <= dy {
            return .missionControl
        }
        if config.missionControlSwipe, dy <= -config.swipeDistance, abs(dx) <= -dy {
            return .missionControlClose
        }
        return nil
    }

    private func beginDrag(_ s: Session) -> TapAction {
        dragging = true
        dragOrigin = s.startCursor
        session = s
        return .dragStart
    }

    /// Call when a physical button press is observed. A real click while
    /// fingers are down must not additionally produce a synthetic tap.
    public func noteButtonEvent() {
        guard !dragging else { return }
        session?.invalid = true
    }

    /// Forget any in-progress contact (e.g. when the device disconnects).
    /// - Returns: true if a drag was in progress, so the caller must release
    ///   the button.
    @discardableResult
    public func reset() -> Bool {
        let wasDragging = dragging
        dragging = false
        pinching = false
        session = nil
        tracks = []
        lastTapEnd = nil
        return wasDragging
    }

    /// Drops edge (grip) contacts, then follows each remaining contact from
    /// frame to frame (nearest match) and drops the ones that have been
    /// resting longer than `restingAfter`.
    private func activeTouches(_ all: [TouchPoint], at time: TimeInterval) -> [TouchPoint] {
        var available = tracks
        var updated: [Track] = []
        var active: [TouchPoint] = []
        for touch in all {
            let nearest = available.indices.min {
                Self.distance(available[$0].position, touch) < Self.distance(available[$1].position, touch)
            }
            var match: Int?
            if let index = nearest, Self.distance(available[index].position, touch) <= config.trackRadius {
                match = index
            }
            // Known contacts get extra room at the edges (hysteresis).
            let margin = config.edgeMargin - (match == nil ? 0 : config.edgeHysteresis)
            guard touch.x >= margin, touch.x <= 1 - margin else { continue }

            var born = time
            if let index = match {
                born = available[index].born
                available.remove(at: index)
            }
            updated.append(Track(position: touch, born: born))
            if dragging || pinching || time - born < config.restingAfter { active.append(touch) }
        }
        tracks = updated
        return active
    }

    private func finish(at time: TimeInterval, cursor: CGPoint) -> TapAction? {
        defer { session = nil }
        if dragging {
            dragging = false
            return .dragEnd
        }
        if pinching {
            pinching = false
            return .magnify(0, .ended)
        }
        guard let s = session, !s.invalid else { return nil }

        let duration = time - s.start
        guard duration >= config.minTapDuration, duration <= config.maxTapDuration else { return nil }
        guard s.travel <= config.maxFingerTravel else { return nil }
        guard Self.distance(cursor, s.startCursor) <= config.maxCursorTravel else { return nil }

        switch s.maxFingers {
        case 1 where config.singleFingerLeftClick:
            lastTapEnd = time
            return .leftClick
        case 2 where config.twoFingerRightClick: return .rightClick
        default: return nil
        }
    }

    static func centroid(of points: [TouchPoint]) -> TouchPoint {
        let n = Float(points.count)
        return TouchPoint(
            x: points.reduce(0) { $0 + $1.x } / n,
            y: points.reduce(0) { $0 + $1.y } / n
        )
    }

    static func distance(_ a: TouchPoint, _ b: TouchPoint) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
