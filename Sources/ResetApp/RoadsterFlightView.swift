import AppKit
import SwiftUI
import ResetCore

/// A synthetic launch-pad scene whose vehicle height follows only the latest usable quota balance.
struct RoadsterFlightView: View {
    let remainingPercent: Double?
    let ratePerHour: Double?
    var stale = false
    var announced = false
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var renderer = Roadster3DRenderer()
    @State private var transition: FlightTransition?
    @State private var transitionTask: Task<Void, Never>?
    @State private var travelOrigin = Date()
    @State private var traveled = 0.0

    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }
    private var flight: RoadsterFlightState {
        RoadsterFlightState(remainingPercent: remainingPercent, stale: stale, ratePerHour: ratePerHour)
    }
    private var motionAllowed: Bool { animated && !reduceMotion && scenePhase == .active }
    private var hasPositiveBalance: Bool { (flight.remainingPercent ?? 0) > 0 }
    private var looping: Bool { motionAllowed && hasPositiveBalance && flight.travelSpeed > 0 }
    private var running: Bool { motionAllowed && hasPositiveBalance && (flight.travelSpeed > 0 || transition != nil) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !running)) { timeline in
            let distance = motionAllowed ? traveled + timeline.date.timeIntervalSince(travelOrigin) * flight.travelSpeed : 0
            let phase = distance * 2 * .pi
            let sample = flightSample(at: timeline.date)
            Canvas(opaque: false, colorMode: .linear) { context, size in
                drawScene(in: &context, size: size, phase: phase, animating: looping,
                          liftFraction: sample.fraction, launch: sample.pose)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .help("高度 = 当前剩余额度；飞行与地面掠过速度 = 近期实测消耗（平滑压缩显示）。实际回补后短暂起飞翻转，随后回到额度对应高度。")
        .onChange(of: flight.travelSpeed) { oldSpeed, _ in
            let now = Date()
            traveled += now.timeIntervalSince(travelOrigin) * oldSpeed
            travelOrigin = now
        }
        .onChange(of: flight.liftFraction) { oldValue, newValue in
            guard let newValue else {
                clearTransition()
                return
            }
            guard newValue > 0 else {
                clearTransition()
                return
            }
            guard motionAllowed, let oldValue else {
                clearTransition()
                return
            }
            let current = transition?.fraction(at: Date()) ?? oldValue
            guard current != newValue else { return }
            beginTransition(from: current, to: newValue, rising: newValue > current)
        }
        .onChange(of: animated) { _, enabled in
            if !enabled { clearTransition() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { clearTransition() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { clearTransition() }
        }
        .onDisappear {
            clearTransition()
        }
    }

    private var accessibilityLabel: String {
        if stale { return "额度读数已过期；飞行高度与容量暂不判断" }
        guard let remaining = flight.remainingPercent else { return "等待有效额度读数；飞行高度与容量暂不判断" }
        let rate = ratePerHour.map { String(format: "，近期消耗 %.2f 百分点每小时", $0) } ?? "，速度待采样"
        return String(format: "Roadster 飞行演示，剩余额度 %.0f%%", remaining) + rate
    }

    private func beginTransition(from: Double, to: Double, rising: Bool) {
        transitionTask?.cancel()
        transition = FlightTransition(from: from, to: to, start: Date(), duration: rising ? 2.8 : 0.82, rising: rising)
        transitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(rising ? 2820 : 840)) } catch { return }
            transition = nil
            transitionTask = nil
        }
    }

    private func clearTransition() {
        transitionTask?.cancel()
        transitionTask = nil
        transition = nil
    }

    private func flightSample(at date: Date) -> (fraction: Double?, pose: RoadsterLaunchPose?) {
        guard hasPositiveBalance, let transition else { return (flight.liftFraction, nil) }
        let progress = min(1, max(0, date.timeIntervalSince(transition.start) / transition.duration))
        let pose = transition.rising ? RoadsterLaunchPose(progress: progress,
            roll: transition.to >= 0.55 && transition.to - transition.from >= 0.20) : nil
        let eased = pose?.liftProgress ?? progress * progress * (3 - 2 * progress)
        return (transition.from + (transition.to - transition.from) * eased, pose)
    }

    private func drawScene(in context: inout GraphicsContext, size: CGSize, phase: Double,
                           animating: Bool, liftFraction: Double?, launch: RoadsterLaunchPose?) {
        guard size.width > 0, size.height > 0 else { return }
        let width = size.width
        let height = size.height
        let compact = width < 140
        let groundY = height * 0.81
        let maxLift = height * 0.39
        let quota = flight.liftFraction
        let displayFraction = liftFraction ?? 0.52
        // Cruise has no vertical bob: height stays readable independently of speed.
        let lift = CGFloat(displayFraction) * maxLift
        let speed = animating ? flight.travelSpeed : 0
        drawHangar(in: &context, width: width, height: height, groundY: groundY, announced: announced)
        if speed > 0 { drawVelocityField(in: &context, size: size, phase: phase, speed: speed, groundY: groundY) }
        drawGroundShadow(in: &context, width: width, groundY: height * 0.89, lift: lift, maxLift: maxLift)

        // The stationary capacity bottle deliberately retains its original design.
        drawTank(in: &context, width: width, groundY: groundY, compact: compact,
                 remaining: flight.remainingPercent)
        let rendered = renderer.frame(size: CGSize(width: width * 0.755, height: height),
            lift: displayFraction, speed: speed, phase: phase, launch: launch)
        var scene = context
        scene.clip(to: Path(CGRect(x: 0, y: 0, width: width * 0.755, height: height)))
        scene.draw(Image(decorative: rendered.image, scale: 2),
                   in: CGRect(x: 0, y: 0, width: width * 0.755, height: height))
        let car = rendered.carBounds
        if quota == nil { drawServiceCradle(in: &context, car: car, groundY: groundY) }
        if flight.remainingPercent == 0 {
            drawLabel("PAD", at: CGPoint(x: car.midX, y: height * 0.97),
                      size: compact ? 5 : 7, color: .white.opacity(0.72), in: &context)
        }
        if !compact {
            let state: String = quota == nil ? (stale ? "读数过期" : "等待读数")
                : quota == 0 ? "已着陆" : launch != nil ? "回补 · 起飞"
                : ratePerHour == nil ? "速度待采样" : flight.travelSpeed > 0 ? "巡航" : "悬停待命"
            drawLabel(state, at: CGPoint(x: width * 0.18, y: height * 0.09), size: 8,
                      color: .white.opacity(0.68), in: &context)
            if let ratePerHour, quota != nil {
                drawLabel(String(format: "%.1f 点/h", ratePerHour),
                          at: CGPoint(x: width * 0.50, y: height * 0.09), size: 9,
                          color: Color(red: 0.65, green: 0.92, blue: 1), in: &context)
            }
        }
        if announced {
            if !compact {
                drawLabel("公告待确认", at: CGPoint(x: width * 0.30, y: height * 0.95),
                          size: 8, color: Color(red: 1, green: 0.75, blue: 0.42), in: &context)
            }
            drawPreparationLights(in: &context, width: width, groundY: groundY, compact: compact)
        }
    }

    private func drawVelocityField(in context: inout GraphicsContext, size: CGSize,
                                   phase: Double, speed: Double, groundY: CGFloat) {
        var field = context
        field.clip(to: Path(CGRect(x: 0, y: size.height * 0.23, width: size.width * 0.75,
                                  height: size.height * 0.76)))
        let distance = phase / (2 * .pi)
        // Tracking camera: near ground marks pass faster than distant air streaks.
        for index in 0..<14 {
            let near = index >= 8
            let depth = near ? 1.0 : 0.35 + Double(index % 3) * 0.12
            let position = (distance * depth + Double(index) * 0.173).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(position) * size.width * 0.95 - size.width * 0.10
            let y = near ? groundY + size.height * (0.035 + Double(index % 3) * 0.046)
                : size.height * (0.26 + Double(index) * 0.060)
            let length = size.width * (near ? 0.07 : 0.05) * (0.55 + speed)
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x + length, y: y))
            field.stroke(streak, with: .linearGradient(Gradient(colors: [.clear,
                Color(red: 0.54, green: 0.85, blue: 1).opacity(near ? 0.64 : 0.18)]),
                startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + length, y: y)),
                style: StrokeStyle(lineWidth: near ? 1.4 : 0.7, lineCap: .round))
        }
    }

    private func drawHangar(in context: inout GraphicsContext, width: CGFloat, height: CGFloat,
                            groundY: CGFloat, announced: Bool) {
        let sky = Path(CGRect(x: 0, y: 0, width: width, height: groundY))
        context.fill(sky, with: .linearGradient(
            Gradient(colors: [Color(red: 0.025, green: 0.055, blue: 0.09),
                              Color(red: 0.055, green: 0.105, blue: 0.14),
                              Color(red: 0.10, green: 0.16, blue: 0.19)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: groundY)))
        let floor = Path(CGRect(x: 0, y: groundY, width: width, height: height - groundY))
        context.fill(floor, with: .linearGradient(
            Gradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.20),
                              Color(red: 0.035, green: 0.06, blue: 0.08)]),
            startPoint: CGPoint(x: 0, y: groundY), endPoint: CGPoint(x: width * 0.35, y: height)))

        var architecture = Path()
        architecture.move(to: CGPoint(x: width * 0.07, y: height * 0.12))
        architecture.addLine(to: CGPoint(x: width * 0.07, y: groundY))
        architecture.move(to: CGPoint(x: width * 0.93, y: height * 0.12))
        architecture.addLine(to: CGPoint(x: width * 0.93, y: groundY))
        architecture.move(to: CGPoint(x: width * 0.07, y: height * 0.12))
        architecture.addQuadCurve(to: CGPoint(x: width * 0.93, y: height * 0.12),
                                  control: CGPoint(x: width * 0.5, y: -height * 0.08))
        context.stroke(architecture, with: .color(.white.opacity(0.10)), lineWidth: 1)

        let horizon = CGPoint(x: width * 0.50, y: height * 0.59)
        var grid = Path()
        grid.move(to: CGPoint(x: 0, y: groundY))
        grid.addLine(to: horizon)
        grid.move(to: CGPoint(x: width, y: groundY))
        grid.addLine(to: horizon)
        for fraction in [0.23, 0.47, 0.72] {
            grid.move(to: CGPoint(x: width * fraction, y: groundY))
            grid.addLine(to: horizon)
        }
        for fraction in [0.25, 0.50, 0.75] {
            let y = groundY + (height - groundY) * fraction
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(announced ? 0.12 : 0.075)), lineWidth: 0.7)

        var pad = Path()
        pad.move(to: CGPoint(x: width * 0.06, y: groundY))
        pad.addLine(to: CGPoint(x: width * 0.94, y: groundY))
        context.stroke(pad, with: .color(.white.opacity(0.38)), lineWidth: 1)
        let centerline = Path(roundedRect: CGRect(x: width * 0.48, y: groundY + 2,
                                                  width: width * 0.04, height: max(1, height * 0.18)),
                              cornerRadius: 1)
        context.fill(centerline, with: .color(.white.opacity(0.19)))
    }

    private func drawGroundShadow(in context: inout GraphicsContext, width: CGFloat,
                                  groundY: CGFloat, lift: CGFloat, maxLift: CGFloat) {
        let proximity = 1 - min(1, max(0, lift / maxLift))
        let shadowWidth = width * (0.29 + 0.16 * proximity)
        let shadow = Path(ellipseIn: CGRect(x: width * 0.40 - shadowWidth / 2,
                                             y: groundY - 2, width: shadowWidth, height: 5 + proximity * 4))
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 5 + (1 - proximity) * 4))
            glow.fill(shadow, with: .color(Color(red: 0.01, green: 0.025, blue: 0.035)
                .opacity(0.76 * proximity + 0.10)))
        }
    }

    private func drawTank(in context: inout GraphicsContext, width: CGFloat, groundY: CGFloat,
                          compact: Bool, remaining: Double?) {
        let tankWidth = width * (compact ? 0.13 : 0.115)
        let tankHeight = min(groundY * (compact ? 0.40 : 0.46), width * (compact ? 0.42 : 0.40))
        let tank = CGRect(x: width * (compact ? 0.78 : 0.79), y: groundY - tankHeight,
                          width: tankWidth, height: tankHeight)
        let body = Path(roundedRect: tank.insetBy(dx: 1, dy: 1), cornerRadius: tankWidth * 0.42)
        context.fill(body, with: .linearGradient(
            Gradient(colors: [Color(red: 0.11, green: 0.16, blue: 0.20),
                              Color(red: 0.49, green: 0.58, blue: 0.61),
                              Color(red: 0.18, green: 0.25, blue: 0.29),
                              Color(red: 0.07, green: 0.10, blue: 0.13)]),
            startPoint: CGPoint(x: tank.minX, y: tank.midY), endPoint: CGPoint(x: tank.maxX, y: tank.midY)))
        context.stroke(body, with: .color(.white.opacity(0.45)), lineWidth: 0.8)

        let cap = Path(ellipseIn: CGRect(x: tank.minX + tankWidth * 0.16, y: tank.minY - tankHeight * 0.035,
                                         width: tankWidth * 0.68, height: tankHeight * 0.075))
        context.fill(cap, with: .linearGradient(
            Gradient(colors: [Color(red: 0.62, green: 0.70, blue: 0.73),
                              Color(red: 0.12, green: 0.18, blue: 0.22)]),
            startPoint: CGPoint(x: tank.minX, y: tank.minY), endPoint: CGPoint(x: tank.maxX, y: tank.minY)))
        context.stroke(cap, with: .color(.white.opacity(0.52)), lineWidth: 0.7)

        var bands = Path()
        for y in [tank.minY + tankHeight * 0.16, tank.maxY - tankHeight * 0.12] {
            bands.move(to: CGPoint(x: tank.minX + 2, y: y))
            bands.addLine(to: CGPoint(x: tank.maxX - 2, y: y))
        }
        context.stroke(bands, with: .color(.white.opacity(0.30)), lineWidth: compact ? 0.6 : 1)
        var weave = Path()
        for index in 0..<6 {
            let y = tank.minY + tankHeight * (0.42 + CGFloat(index) * 0.035)
            weave.move(to: CGPoint(x: tank.midX - tankWidth * 0.27, y: y))
            weave.addLine(to: CGPoint(x: tank.midX + tankWidth * 0.27, y: y + tankHeight * 0.035))
        }
        context.stroke(weave, with: .color(.white.opacity(0.11)), lineWidth: compact ? 0.45 : 0.65)

        if let remaining {
            let gaugeRadius = min(tankWidth * (compact ? 0.32 : 0.35), compact ? 3.2 : 7.5)
            let center = CGPoint(x: tank.midX, y: tank.minY + tankHeight * 0.30)
            let gauge = Path(ellipseIn: CGRect(x: center.x - gaugeRadius, y: center.y - gaugeRadius,
                                               width: gaugeRadius * 2, height: gaugeRadius * 2))
            context.fill(gauge, with: .color(Color(red: 0.025, green: 0.045, blue: 0.055)))
            context.stroke(gauge, with: .color(.white.opacity(0.72)), lineWidth: compact ? 0.7 : 1)
            let angle = Double.pi * 0.75 + Double(min(100, max(0, remaining))) / 100 * Double.pi * 1.5
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: CGPoint(x: center.x + cos(angle) * gaugeRadius * 0.78,
                                       y: center.y + sin(angle) * gaugeRadius * 0.78))
            context.stroke(needle, with: .color(remaining == 0 ? .white.opacity(0.58) : .white),
                           style: StrokeStyle(lineWidth: compact ? 0.6 : 1, lineCap: .round))
            if !compact {
                drawLabel(String(format: "%.0f%%", remaining),
                          at: CGPoint(x: tank.midX, y: tank.maxY + 5), size: 10,
                          color: .white.opacity(0.92), in: &context)
                drawLabel("额度", at: CGPoint(x: tank.midX, y: tank.maxY + 16),
                          size: 7, color: .white.opacity(0.66), in: &context)
            }
            let segmentCount = 8
            let activeSegments = Int(ceil(min(100, max(0, remaining)) / 100 * Double(segmentCount)))
            let segmentWidth = tankWidth * 0.25
            let segmentHeight = max(compact ? 1 : 1.5, tankHeight * (compact ? 0.042 : 0.026))
            for index in 0..<segmentCount {
                let x = tank.midX - segmentWidth / 2
                let y = tank.minY + tankHeight * 0.46 + CGFloat(index) * (segmentHeight * 1.28)
                let segment = Path(roundedRect: CGRect(x: x, y: y, width: segmentWidth, height: segmentHeight),
                                   cornerRadius: segmentHeight * 0.35)
                let isLit = index >= segmentCount - activeSegments
                let segmentColor = isLit
                    ? Color(red: 0.38, green: 0.92, blue: 0.79).opacity(0.94)
                    : Color.white.opacity(0.14)
                context.fill(segment, with: .color(segmentColor))
            }
        } else {
            if compact {
                let gaugeRadius = min(tankWidth * 0.32, 3.2)
                let center = CGPoint(x: tank.midX, y: tank.minY + tankHeight * 0.30)
                let dash = Path(roundedRect: CGRect(x: center.x - gaugeRadius * 0.6,
                    y: center.y - 0.4, width: gaugeRadius * 1.2, height: 0.8), cornerRadius: 0.4)
                context.fill(dash, with: .color(.white.opacity(0.60)))
            } else {
                drawLabel("—", at: CGPoint(x: tank.midX, y: tank.minY + tankHeight * 0.30),
                          size: 12, color: .white.opacity(0.60), in: &context)
            }
        }
    }

    private func drawServiceCradle(in context: inout GraphicsContext, car: CGRect, groundY: CGFloat) {
        let railY = car.maxY + 2
        var cradle = Path()
        cradle.move(to: CGPoint(x: car.minX + car.width * 0.20, y: railY))
        cradle.addLine(to: CGPoint(x: car.minX + car.width * 0.20, y: groundY))
        cradle.move(to: CGPoint(x: car.minX + car.width * 0.77, y: railY))
        cradle.addLine(to: CGPoint(x: car.minX + car.width * 0.77, y: groundY))
        cradle.move(to: CGPoint(x: car.minX + car.width * 0.13, y: railY))
        cradle.addLine(to: CGPoint(x: car.minX + car.width * 0.84, y: railY))
        context.stroke(cradle, with: .color(.white.opacity(0.26)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3]))
    }

    private func drawPreparationLights(in context: inout GraphicsContext, width: CGFloat,
                                       groundY: CGFloat, compact: Bool) {
        let amber = Color(red: 1, green: 0.65, blue: 0.26)
        for index in 0..<4 {
            let x = width * (0.12 + CGFloat(index) * (compact ? 0.065 : 0.055))
            let radius: CGFloat = compact ? 1.1 : 1.8
            let light = Path(ellipseIn: CGRect(x: x - radius, y: groundY - radius,
                                               width: radius * 2, height: radius * 2))
            context.fill(light, with: .color(amber.opacity(0.9)))
        }
    }

    private func drawLabel(_ value: String, at point: CGPoint, size: CGFloat,
                           color: Color, in context: inout GraphicsContext) {
        let label = Text(value).font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit().foregroundColor(color)
        context.draw(context.resolve(label), at: point, anchor: .center)
    }
}

private struct FlightTransition {
    let from: Double
    let to: Double
    let start: Date
    let duration: TimeInterval
    let rising: Bool

    func fraction(at date: Date) -> Double {
        let progress = min(1, max(0, date.timeIntervalSince(start) / duration))
        let eased = rising ? RoadsterLaunchPose(progress: progress, roll: false).liftProgress
            : progress * progress * (3 - 2 * progress)
        return from + (to - from) * eased
    }
}
