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

public enum TapAction: Equatable {
    case leftClick
    case rightClick
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
    }

    private var session: Session?

    public init(config: TapConfig = TapConfig()) {
        self.config = config
    }

    /// - Parameters:
    ///   - time: monotonic timestamp in seconds.
    ///   - touches: fingers currently touching the surface.
    ///   - cursor: current pointer location in screen points.
    public func process(time: TimeInterval, touches: [TouchPoint], cursor: CGPoint) -> TapAction? {
        if touches.isEmpty {
            return finish(at: time, cursor: cursor)
        }

        let centroid = Self.centroid(of: touches)

        guard var s = session else {
            session = Session(
                start: time,
                startCursor: cursor,
                lastCentroid: centroid,
                lastCount: touches.count,
                maxFingers: touches.count,
                travel: 0,
                invalid: false
            )
            return nil
        }

        // Only measure motion between frames with the same finger count:
        // adding/removing a finger shifts the centroid without any movement.
        if touches.count == s.lastCount {
            s.travel += Self.distance(centroid, s.lastCentroid)
        }
        s.lastCentroid = centroid
        s.lastCount = touches.count
        s.maxFingers = max(s.maxFingers, touches.count)

        if time - s.start > config.maxTapDuration
            || s.travel > config.maxFingerTravel
            || Self.distance(cursor, s.startCursor) > config.maxCursorTravel {
            s.invalid = true
        }
        session = s
        return nil
    }

    /// Call when a physical button press is observed. A real click while
    /// fingers are down must not additionally produce a synthetic tap.
    public func noteButtonEvent() {
        session?.invalid = true
    }

    /// Forget any in-progress contact (e.g. when the device disconnects).
    public func reset() {
        session = nil
    }

    private func finish(at time: TimeInterval, cursor: CGPoint) -> TapAction? {
        defer { session = nil }
        guard let s = session, !s.invalid else { return nil }

        let duration = time - s.start
        guard duration >= config.minTapDuration, duration <= config.maxTapDuration else { return nil }
        guard s.travel <= config.maxFingerTravel else { return nil }
        guard Self.distance(cursor, s.startCursor) <= config.maxCursorTravel else { return nil }

        switch s.maxFingers {
        case 1 where config.singleFingerLeftClick: return .leftClick
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
