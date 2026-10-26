import SwiftUI

/// Compact native companion to the app icon: an open quota ring and clock hands.
struct QuotaLogo: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().trim(from: 0.12, to: 1)
                    .stroke(ink.accent, style: StrokeStyle(lineWidth: side * 0.11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(side * 0.09)
                Path { path in
                    path.move(to: CGPoint(x: side * 0.32, y: side * 0.36))
                    path.addLine(to: CGPoint(x: side * 0.5, y: side * 0.5))
                    path.addLine(to: CGPoint(x: side * 0.70, y: side * 0.30))
                }
                .stroke(ink.accent, style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round, lineJoin: .round))
                Circle().fill(ink.accent).frame(width: side * 0.105, height: side * 0.105)
            }.frame(width: side, height: side)
        }.accessibilityHidden(true)
    }
}
