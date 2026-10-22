import Foundation

public enum ResetTimeDisplay {
    public static func shanghai(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
    public static func remaining(until deadline: Date, now: Date) -> String {
        let interval = deadline.timeIntervalSince(now)
        if interval <= 0 { return "目标已到，等待确认" }
        let seconds = Int(interval)
        if seconds < 60 { return "不到1分钟" }
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        return (days > 0 ? "\(days)天" : "") + (hours > 0 ? "\(hours)小时" : "") + "\(minutes)分"
    }
}
