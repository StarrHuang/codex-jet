import SwiftUI
import ResetCore

/// Account history and public reset signals stay separate, with every time kept source-bound.
struct ResetScheduleView: View {
    let window: QuotaWindow?
    let radar: RadarData?
    let now: Date
    var history: [QuotaSnapshot] = []
    var accountKey: String? = nil
    var compact = false

    private let blue = Color(red: 0.39, green: 0.67, blue: 0.98)
    private let muted = ink.secondary

    private var analysis: QuotaHistoryAnalysis? {
        guard let window, let accountKey else { return nil }
        return QuotaHistoryAnalysis.analyze(history: history, accountKey: accountKey,
                                            windowID: window.id, bucketID: window.bucketID,
                                            now: now)
    }

    private var observedBoundaries: [(ObservedCycle, ObservedCycle)] {
        let cycles = analysis?.cycles ?? []
        return Array(zip(cycles, cycles.dropFirst())).filter { $0.0.finalUsedPercent > 0 || $0.1.initialUsedPercent > 0 }.suffix(3).reversed().map { ($0.0, $0.1) }
    }

    private var events: [RadarTimeline.Event] {
        (radar?.timeline.events ?? []).sorted { left, right in
            switch (eventDate(left.date), eventDate(right.date)) {
            case let (a?, b?): return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.id < right.id
            }
        }.prefix(4).map { $0 }
    }

    private var extraResetAdvice: ExtraResetAdvice { ExtraResetAdvice.evaluate(radar, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("重置安排").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("账户实测 · 全局站点信号")
                    .font(.system(size: compact ? 9 : 12)).foregroundStyle(muted)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "person.crop.circle.badge.clock")
                        .font(.system(size: 14)).foregroundStyle(blue).frame(width: 18)
                    Text("本账户正常重置").font(.system(size: compact ? 11 : 13, weight: .semibold))
                    Spacer()
                    statusChip(window?.resetsAt == nil ? "时间未知" : "服务器读数", tint: window?.resetsAt == nil ? muted : blue)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(window?.resetsAt.map { stamp($0) + " · 上海时间" } ?? "重置时间未知")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Spacer()
                    Text("Codex 账户额度接口")
                        .font(.system(size: compact ? 9 : 12)).foregroundStyle(muted)
                }.padding(.leading, 27)
            }
            .padding(11)
            .background(blue.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 13)).foregroundStyle(.orange.opacity(0.9)).frame(width: 18)
                    Text("本机观测到的周期变化").font(.system(size: compact ? 11 : 13, weight: .semibold))
                    Spacer()
                    statusChip("采样区间", tint: muted)
                }
                if observedBoundaries.isEmpty {
                    Text("尚无相邻周期变化记录；不回填首次采样之前的历史。")
                        .font(.system(size: compact ? 9 : 12)).foregroundStyle(muted).padding(.leading, 27)
                } else {
                    ForEach(Array(observedBoundaries.enumerated()), id: \.offset) { _, boundary in
                        observedBoundaryRow(previous: boundary.0, next: boundary.1)
                    }
                    Text("观测区间不代表准确发生时刻或原因。")
                        .font(.system(size: compact ? 9 : 11)).foregroundStyle(muted).padding(.leading, 27)
                }
            }
            .padding(11)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13)).foregroundStyle(blue).frame(width: 18)
                    Text("全局公告与历史").font(.system(size: compact ? 11 : 13, weight: .semibold))
                    Spacer()
                    Text(radarFreshness).font(.system(size: compact ? 9 : 12)).foregroundStyle(muted)
                }

                if [.upcoming, .observation].contains(extraResetAdvice.state), let deadline = extraResetAdvice.deadline {
                    HStack(alignment: .top, spacing: 8) {
                        statusChip("活跃公告", tint: blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(extraResetAdvice.targetName) \(stamp(deadline)) · 北京时间")
                                .font(.system(size: compact ? 10 : 12, weight: .medium, design: .monospaced))
                            Text("还有 " + ResetTimeDisplay.remaining(until: deadline, now: now))
                                .font(.system(size: compact ? 10 : 12, weight: .semibold)).foregroundStyle(blue)
                            Text(extraResetAdvice.conversionNote ?? "以本账户读数确认是否到账。")
                                .font(.system(size: compact ? 9 : 12)).foregroundStyle(muted)
                        }
                        Spacer(minLength: 0)
                        if let url = extraResetAdvice.sourceURL {
                            Link("原文", destination: url).font(.system(size: compact ? 9 : 12)).foregroundStyle(blue)
                        }
                    }.padding(.leading, 27)
                } else if extraResetAdvice.state == .recent {
                    Text("站点刚确认额外重置；等待本账户读数确认到账。")
                        .font(.system(size: compact ? 9 : 12)).foregroundStyle(muted).padding(.leading, 27)
                }

                if events.isEmpty {
                    Text(radar == nil ? "未知 · 尚无可用雷达时间线" : "暂无站点收录事件")
                        .font(.system(size: compact ? 9 : 12)).foregroundStyle(muted).padding(.leading, 27)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { Rectangle().fill(.white.opacity(0.045)).frame(height: 1).padding(.leading, 27) }
                            eventRow(event)
                        }
                    }
                }
                Text("来源：codex-reset.com · 全局事件不代表你的账户已到账。")
                    .font(.system(size: compact ? 9 : 12)).foregroundStyle(muted).padding(.leading, 27)
            }
            .padding(11)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(13)
        .popoverCard(blue)
    }

    private var radarFreshness: String {
        guard let radar else { return "来源未知" }
        guard let updated = parseDate(radar.forecast.updated_at), updated <= now,
              now.timeIntervalSince(updated) <= 30 * 60,
              now.timeIntervalSince(radar.fetchedAt) <= 30 * 60 else { return "站点数据过期" }
        return "站点更新 \(stamp(updated))"
    }

    private func observedBoundaryRow(previous: ObservedCycle, next: ObservedCycle) -> some View {
        let scheduleChanged = !sameQuotaResetTime(previous.resetsAt, next.resetsAt)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusChip(next.initialUsedPercent < previous.finalUsedPercent ? "观测到额度回补" : "重置时间更新 / 重锚", tint: .orange)
                if scheduleChanged { statusChip("重置时间字段变化", tint: muted) }
            }
            Text("采样间隔：\(stamp(previous.lastSeen)) → \(stamp(next.firstSeen))")
                .font(.system(size: compact ? 9 : 12, design: .monospaced)).foregroundStyle(muted)
            HStack(spacing: 6) {
                Text("已用 \(number(previous.finalUsedPercent))%")
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(muted)
                Text("已用 \(number(next.initialUsedPercent))%")
                Spacer(minLength: 0)
            }.font(.system(size: compact ? 9 : 12, design: .monospaced))
        }
        .padding(.leading, 27)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func eventRow(_ event: RadarTimeline.Event) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(eventDate(event.date).map { $0 <= now ? muted : blue } ?? muted)
                .frame(width: 5, height: 5).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.title).font(.system(size: compact ? 10 : 12, weight: .medium))
                    statusChip(eventDate(event.date).map { $0 <= now ? "历史" : "公告时间" } ?? "时间未识别", tint: muted)
                }
                if let summary = event.summary {
                    Text(summary).font(.system(size: compact ? 10 : 12)).foregroundStyle(muted).lineLimit(3)
                }
                Text(event.announced_at.flatMap(parseDate).map { stamp($0) + " · 北京时间" } ?? displayDate(event.date)).font(.system(size: compact ? 9 : 12, design: .monospaced)).foregroundStyle(muted)
            }
            Spacer(minLength: 2)
            if let address = event.url, let url = URL(string: address), url.scheme == "https", url.host == "x.com" {
                Link("原文", destination: url).font(.system(size: compact ? 9 : 12)).foregroundStyle(blue)
            }
        }.padding(.leading, 27)
    }

    private func statusChip(_ title: String, tint: Color) -> some View {
        Text(title).font(.system(size: compact ? 8 : 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(tint.opacity(0.11), in: Capsule())
    }

    private func eventDate(_ value: String) -> Date? {
        if let instant = parseDate(value) { return instant }
        // Timeline events can supply a calendar date without a clock time.
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        format.dateFormat = "yyyy-MM-dd"
        format.isLenient = false
        guard value.count == 10, let day = format.date(from: value), format.string(from: day) == value else { return nil }
        return day // Ordering by calendar day only; never display a fabricated time.
    }

    private func displayDate(_ value: String) -> String {
        if let instant = parseDate(value) { return stamp(instant) }
        if eventDate(value) != nil { return value + " · 来源未提供时刻" }
        return value + " · 时间未识别"
    }
}
