import MagicTapCore
import SwiftUI

/// A Magic Mouse seen from above (tip at the top) with the live fingers on it.
/// Sensor coordinates: x 0...1 left to right, y 0...1 from the wrist to the tip.
struct MouseView: View {
    let touches: [TouchPoint]
    /// Normalized edge margin; fingers inside it are grip and are ignored.
    var edgeMargin: Double = 0.10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.5, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.97), Color(white: 0.86)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: w * 0.5, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                    )
                // Edge bands: contacts there are treated as grip.
                HStack {
                    Rectangle().fill(Color.orange.opacity(0.12)).frame(width: w * edgeMargin)
                    Spacer()
                    Rectangle().fill(Color.orange.opacity(0.12)).frame(width: w * edgeMargin)
                }
                .clipShape(RoundedRectangle(cornerRadius: w * 0.5, style: .continuous))

                ForEach(Array(touches.enumerated()), id: \.offset) { _, t in
                    let grip = Double(t.x) < edgeMargin || Double(t.x) > 1 - edgeMargin
                    Circle()
                        .fill((grip ? Color.orange : Color.accentColor).opacity(0.75))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                        .frame(width: w * 0.2, height: w * 0.2)
                        .position(x: CGFloat(t.x) * w, y: (1 - CGFloat(t.y)) * h)
                }
            }
        }
        .aspectRatio(0.58, contentMode: .fit)
        .animation(.linear(duration: 0.03), value: touches)
    }
}
