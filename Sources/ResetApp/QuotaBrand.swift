import SwiftUI

/// 品牌时钟的单一几何源；应用图标、通知、侧栏和菜单栏共用。
struct QuotaBrandMark: View {
    var tint: Color = Color(red: 0.09, green: 0.19, blue: 0.17)

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().trim(from: 0.16, to: 1)
                    .stroke(tint, style: StrokeStyle(lineWidth: side * 0.105, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(side * 0.105)
                Path { path in
                    path.move(to: CGPoint(x: side * 0.50, y: side * 0.28))
                    path.addLine(to: CGPoint(x: side * 0.50, y: side * 0.50))
                    path.addLine(to: CGPoint(x: side * 0.69, y: side * 0.50))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: side * 0.085, lineCap: .round, lineJoin: .round))
            }.frame(width: side, height: side)
        }.accessibilityHidden(true)
    }
}

/// 无文字的薄荷色品牌底板，小尺寸通知也能辨认；颜色不代表账户状态。
struct QuotaBrandBadge: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            QuotaBrandMark().padding(side * 0.12)
                .frame(width: side, height: side)
                .background(LinearGradient(colors: [Color(red: 0.78, green: 0.98, blue: 0.87),
                                                     Color(red: 0.42, green: 0.85, blue: 0.66)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
        }.accessibilityHidden(true)
    }
}

/// 传统 ICNS 的安全边距；与现代 App Store 的系统遮罩画布分开。
struct QuotaAppIcon: View {
    var body: some View {
        GeometryReader { geometry in
            QuotaBrandBadge().padding(geometry.size.width * 0.10)
        }
    }
}
