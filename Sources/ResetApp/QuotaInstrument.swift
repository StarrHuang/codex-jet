import SwiftUI

/// Anatomy-inspired bench gauge. Its needle is the account reading, never an idle animation.
struct QuotaInstrument: View, Animatable {
    nonisolated var remaining: Double
    var tint: Color
    nonisolated var animatableData: Double {
        get { remaining }
        set { remaining = newValue }
    }

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 220, y: size.height / 150)
            let edge = Color(red: 0.39, green: 0.47, blue: 0.47)
            let top = Color(red: 0.20, green: 0.26, blue: 0.26)
            func fill(_ points: [CGPoint], _ color: Color) {
                var p = Path()
                p.addLines(points)
                p.closeSubpath()
                context.fill(p, with: .color(color))
                context.stroke(p, with: .color(edge.opacity(0.6)), lineWidth: 0.65)
            }
            func at(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                CGPoint(x: 110 + (x - y) * 0.82, y: 108 + (x + y) * 0.32 - z)
            }
            func box(_ x: Double, _ y: Double, _ w: Double, _ d: Double, _ z: Double, _ h: Double) {
                fill([at(x,y,z), at(x+w,y,z), at(x+w,y,z+h), at(x,y,z+h)], top.opacity(0.65))
                fill([at(x+w,y,z), at(x+w,y+d,z), at(x+w,y+d,z+h), at(x+w,y,z+h)], top.opacity(0.45))
                fill([at(x,y,z+h), at(x+w,y,z+h), at(x+w,y+d,z+h), at(x,y+d,z+h)], top)
            }
            let shadow = Path(ellipseIn: CGRect(x: 22, y: 105, width: 177, height: 37))
            context.fill(shadow, with: .color(.black.opacity(0.22)))
            for (x,y) in [(-57.0,-28.0),(42,-28),(-57,23),(42,23)] { box(x,y,13,12,-6,7) }
            box(-67,-36,134,80,1,8)
            box(-64,-33,128,74,9,2)
            box(-26,-16,52,36,11,14)
            // A tilted dial housing; the inset rim and lower lip give it real thickness.
            let rim = CGRect(x: 57, y: 18, width: 107, height: 88)
            context.fill(Path(ellipseIn: rim.offsetBy(dx: 0, dy: 9)), with: .color(Color.black.opacity(0.55)))
            context.fill(Path(ellipseIn: rim), with: .linearGradient(
                Gradient(colors: [Color(red: 0.48, green: 0.57, blue: 0.55), top]),
                startPoint: CGPoint(x: 60,y: 20), endPoint: CGPoint(x: 145,y: 100)))
            context.stroke(Path(ellipseIn: rim.insetBy(dx: 3, dy: 3)), with: .color(edge), lineWidth: 0.7)
            context.fill(Path(ellipseIn: rim.insetBy(dx: 8, dy: 7)), with: .color(Color(red: 0.065, green: 0.10, blue: 0.10)))
            let center = CGPoint(x: 110.5, y: 63)
            func point(_ angle: Double, _ r: Double) -> CGPoint {
                CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r * 0.81)
            }
            for tick in 0...30 {
                let angle = (135.0 + Double(tick) * 9) * .pi / 180
                var mark = Path()
                mark.move(to: point(angle, tick % 5 == 0 ? 31 : 35))
                mark.addLine(to: point(angle, 39))
                context.stroke(mark, with: .color(tick % 5 == 0 ? Color.white.opacity(0.8) : edge), lineWidth: tick % 5 == 0 ? 1.4 : 0.7)
            }
            let angle = (135 + remaining / 100 * 270) * .pi / 180
            var needle = Path()
            needle.move(to: point(angle + .pi, 8))
            needle.addLine(to: point(angle, 31))
            context.stroke(needle, with: .color(tint), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: 106.5,y: 59.5,width: 8,height: 7)), with: .color(tint))
            context.fill(Path(ellipseIn: CGRect(x: 109,y: 61.5,width: 3,height: 3)), with: .color(top))
            for (x,y) in [(-57.0,-26.0),(53,-26),(-57,33),(53,33)] {
                let p = at(x,y,11)
                context.fill(Path(ellipseIn: CGRect(x:p.x-2,y:p.y-1,width:4,height:2)), with: .color(edge))
                var slot = Path(); slot.move(to: CGPoint(x:p.x-1,y:p.y)); slot.addLine(to: CGPoint(x:p.x+1,y:p.y))
                context.stroke(slot, with: .color(.black), lineWidth: 0.6)
            }
            // Engraved plate, attached to the front edge of the base.
            box(-25,28,49,9,11,0.7)
            context.draw(Text("CODEX / 100").font(.system(size: 5, weight: .medium, design: .monospaced)).foregroundColor(edge), at: CGPoint(x: 89,y: 121))
        }
        .frame(width: 220, height: 150)
        .accessibilityHidden(true)
    }
}

struct InstrumentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
