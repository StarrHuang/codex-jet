import SwiftUI
import ResetCore

extension DeadlinePace.RunwayLight {
    var symbol: String {
        switch self {
        case .red: "🔴"
        case .yellow: "🟡"
        case .green: "🟢"
        case .unknown: "⚪️"
        }
    }
    var color: Color {
        switch self {
        case .red: Color(red: 1.00, green: 0.29, blue: 0.30)
        case .yellow: Color(red: 1.00, green: 0.74, blue: 0.24)
        case .green: Color(red: 0.38, green: 0.92, blue: 0.64)
        case .unknown: Color.white.opacity(0.46)
        }
    }
    var explanation: String {
        switch self {
        case .red: L("红灯：按近期实测速率，预计明显提前耗尽（快于目标速度 10% 以上），或当前额度已耗尽。")
        case .yellow: L("黄灯：预计接近重置时用尽（实测速率在目标速度 ±10% 内），余量临界。")
        case .green: L("绿灯：按近期实测速率，额度可撑到最近目标并留有余量。")
        case .unknown: L("灰灯：缺少有效速度样本、读数过期或没有未来目标，暂不判断能否撑到重置。")
        }
    }
}
