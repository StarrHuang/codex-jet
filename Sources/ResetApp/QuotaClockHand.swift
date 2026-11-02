import AppKit
import SwiftUI
import QuartzCore

/// 用合成层旋转指针，避免为每一帧重新计算 SwiftUI 视图。
struct QuotaClockHand: NSViewRepresentable {
    let turnsPerSecond: Double
    let lineWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> QuotaClockHandView { QuotaClockHandView() }

    func updateNSView(_ view: QuotaClockHandView, context: Context) {
        view.configure(turnsPerSecond: turnsPerSecond, lineWidth: lineWidth,
                       color: colorScheme == .dark ? .white : .black)
    }
}

@MainActor
final class QuotaClockHandView: NSView {
    private let hand = CAShapeLayer()
    private var requestedSpeed = 0.0
    private var runningSpeed = 0.0
    private var turns = 0.0
    private var origin = CACurrentMediaTime()
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        hand.fillColor = nil
        hand.lineCap = .round
        layer!.addSublayer(hand)
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
            name: NSApplication.didHideNotification, object: NSApp)
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
            name: NSApplication.didUnhideNotification, object: NSApp)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(turnsPerSecond: Double, lineWidth: CGFloat, color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hand.strokeColor = color.cgColor
        hand.lineWidth = lineWidth
        CATransaction.commit()
        if requestedSpeed != turnsPerSecond {
            requestedSpeed = turnsPerSecond
            updateAnimation()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        updateAnimation()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hand.bounds = bounds
        hand.position = CGPoint(x: bounds.midX, y: bounds.midY)
        hand.contentsScale = window?.backingScaleFactor ?? 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.midX, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY + min(bounds.width, bounds.height) * 0.18))
        hand.path = path
        CATransaction.commit()
    }

    @objc private func visibilityChanged(_ notification: Notification) { updateAnimation() }

    private func updateAnimation() {
        let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
            && !NSApp.isHidden && !isHiddenOrHasHiddenAncestor
        let speed = visible ? requestedSpeed : 0
        guard speed != runningSpeed else { return }
        let now = CACurrentMediaTime()
        turns = (turns + (now - origin) * runningSpeed).truncatingRemainder(dividingBy: 1)
        origin = now
        runningSpeed = speed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hand.removeAnimation(forKey: "quota-hand")
        hand.transform = CATransform3DMakeRotation(turns * .pi * 2, 0, 0, 1)
        if speed > 0 {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = turns * .pi * 2
            rotation.toValue = (turns + 1) * .pi * 2
            rotation.duration = 1 / speed
            rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            hand.add(rotation, forKey: "quota-hand")
        }
        CATransaction.commit()
    }
}
