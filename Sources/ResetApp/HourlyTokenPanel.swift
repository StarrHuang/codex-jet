import SwiftUI
import Charts
import ResetCore

struct HourlyTokenPanel: View {
    private struct ModelTotal: Identifiable {
        let model: String
        let totalTokens: Int64
        var id: String { model }
    }

    let report: LocalTokenReport?
    let loading: Bool
    let error: String?
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }
    @State private var rangeHours = 24
    @State private var selectedHour: Date?

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        return calendar
    }
    private let palette: [Color] = [
        Color(red: 0.44, green: 0.72, blue: 0.98),
        Color(red: 0.98, green: 0.66, blue: 0.35),
        Color(red: 0.73, green: 0.94, blue: 0.59),
        Color(red: 0.79, green: 0.63, blue: 0.98),
        Color(red: 0.35, green: 0.83, blue: 0.76),
        Color(red: 0.98, green: 0.49, blue: 0.56),
        Color(red: 0.95, green: 0.83, blue: 0.37),
        Color(red: 0.53, green: 0.68, blue: 0.92)
    ]

    private var generatedAt: Date { report?.generatedAt ?? Date() }
    private var endHour: Date { shanghaiCalendar.dateInterval(of: .hour, for: generatedAt)?.start ?? generatedAt }
    private var startHour: Date { shanghaiCalendar.date(byAdding: .hour, value: -(rangeHours - 1), to: endHour) ?? endHour }
    private var selected: Date { selectedHour ?? endHour }
    private var rows: [HourlyModelTokens] {
        guard let report else { return [] }
        return aggregate(report.rows.filter { $0.hour >= startHour && $0.hour <= endHour })
            .sorted { $0.hour == $1.hour ? $0.model < $1.model : $0.hour < $1.hour }
    }
    private var selectedRows: [HourlyModelTokens] { rows.filter { $0.hour == selected }.sorted { $0.totalTokens > $1.totalTokens } }
    private var modelNames: [String] { Array(Set(rows.map(\.model))).sorted() }
    private var rangeTotals: [ModelTotal] {
        Dictionary(grouping: rows, by: \.model).map { model, modelRows in
            ModelTotal(model: model, totalTokens: modelRows.reduce(0) { $0 + $1.totalTokens })
        }.sorted { $0.totalTokens == $1.totalTokens ? $0.model < $1.model : $0.totalTokens > $1.totalTokens }
    }
    private var rangeGrandTotal: Int64 { rangeTotals.reduce(0) { $0 + $1.totalTokens } }
    private var isStale: Bool { generatedAt < Date().addingTimeInterval(-600) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 13 : 19) {
            header
            if let error {
                statusCard(title: L("读取失败"), detail: error, symbol: "exclamationmark.triangle.fill", color: .orange)
            } else if loading && report == nil {
                statusCard(title: L("正在读取本机会话"), detail: L("等待本地 Codex 使用记录"), symbol: "arrow.triangle.2.circlepath", color: ink.blue)
            } else if let report {
                if isStale {
                    statusCard(title: L("数据可能已过期"), detail: L("最近生成于 {{0}}", String(describing: dateTime(generatedAt))), symbol: "clock", color: .orange)
                }
                if !compact {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortTokens(rangeGrandTotal)).font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                        Text("tokens / \(rangeHours == 24 ? L("24 小时") : L("7 天"))").font(.system(size: 12)).foregroundStyle(ink.secondary)
                        Spacer()
                        Text(L("输入含缓存 · 输出含推理")).font(.system(size: 11)).foregroundStyle(ink.secondary)
                    }
                }
                chartSection
                selectedHourSection
                if !compact { rangeTotalsSection }
                if !report.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("读取提示")).font(.system(size: compact ? 11 : 13, weight: .semibold)).foregroundStyle(ink.secondary)
                        ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, warning in
                            Text("• \(L(warning))").font(.system(size: 11)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.top, 1)
                }
                footer(report)
            } else {
                statusCard(title: L("暂无本机使用记录"), detail: L("尚未读取到 Codex 会话数据。"), symbol: "chart.bar", color: ink.secondary)
            }
        }
        .padding(compact ? 15 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(ink.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.055), lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: rangeHours)
        .onChange(of: rangeHours) { _, _ in selectedHour = nil }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("每小时 · 模型消耗")).font(.system(size: compact ? 14 : 16, weight: .semibold))
                Text(L("本机 Codex 会话 · 上海时间")).font(.system(size: compact ? 10 : 12)).foregroundStyle(ink.secondary)
            }
            Spacer(minLength: 4)
            Picker(L("显示范围"), selection: $rangeHours) {
                Text(L("24 小时")).tag(24)
                Text(L("7 天")).tag(168)
            }.pickerStyle(.segmented).labelsHidden().tint(ink.accent).frame(width: compact ? 145 : 185)
        }
    }

    @ViewBuilder private var chartSection: some View {
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("这段时间没有已记录的小时")).font(.system(size: 12, weight: .medium))
                Text(L("缺少记录的小时显示为空；这不代表已确认消耗为零。当前小时仍在进行中。"))
                    .font(.system(size: compact ? 10 : 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: compact ? 100 : 150, alignment: .leading)
        } else {
            Text(L("每根柱为一小时；空白 = 未记录")).font(.system(size: compact ? 9 : 11)).foregroundStyle(ink.secondary)
            Chart {
                ForEach(rows) { row in
                    BarMark(
                        x: .value(L("小时"), row.hour, unit: .hour),
                        y: .value("Token", row.totalTokens),
                        width: .fixed(rangeHours > 24 ? 4 : 9)
                    )
                    .foregroundStyle(by: .value(L("模型"), row.model))
                }
                RuleMark(x: .value(L("选中小时"), selected))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            .chartXScale(domain: startHour...endHour.addingTimeInterval(3600))
            .chartForegroundStyleScale(domain: modelNames, range: modelNames.map(modelColor))
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: compact ? 4 : (rangeHours > 24 ? 7 : 8))) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.065))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date)).font(.system(size: compact ? 8 : 9, design: .monospaced)).foregroundStyle(ink.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 3 : 4)) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Int64.self) {
                            Text(shortTokens(number)).font(.system(size: 9, design: .monospaced)).foregroundStyle(ink.secondary)
                        }
                    }
                }
            }
            .chartXSelection(value: Binding<Date?>(
                get: { selectedHour ?? endHour },
                set: { selectedHour = $0.flatMap { shanghaiCalendar.dateInterval(of: .hour, for: $0)?.start } }
            ))
            .frame(height: compact ? 116 : 190)
            modelLegend
        }
    }

    private var modelLegend: some View {
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 115 : 145), alignment: .leading)], alignment: .leading, spacing: 7) {
            ForEach(modelNames, id: \.self) { model in
                HStack(spacing: 6) {
                    Circle().fill(modelColor(model)).frame(width: 8, height: 8)
                    Text(model).font(.system(size: compact ? 10 : 12, weight: .medium)).lineLimit(1).help(model)
                }.foregroundStyle(ink.secondary)
            }
        }
    }

    private var selectedHourSection: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateTime(selected)).font(.system(size: compact ? 11 : 12, weight: .semibold, design: .monospaced))
                Spacer()
                if selected == endHour { Text(L("当前小时 · 未完成")).font(.system(size: compact ? 9 : 11)).foregroundStyle(ink.secondary) }
                Button {
                    selectedHour = shanghaiCalendar.date(byAdding: .hour, value: -1, to: selected)
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).help(L("前一小时")).accessibilityLabel(L("前一小时"))
                    .disabled(selected <= startHour)
                Button {
                    selectedHour = shanghaiCalendar.date(byAdding: .hour, value: 1, to: selected)
                } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).help(L("后一小时")).accessibilityLabel(L("后一小时"))
                    .disabled(selected >= endHour)
            }
            if selectedRows.isEmpty {
                Text(L("未记录此小时的用量；不表示已确认消耗为零。"))
                    .font(.system(size: compact ? 10 : 12)).foregroundStyle(ink.secondary)
            } else {
                VStack(spacing: compact ? 7 : 9) {
                    ForEach(selectedRows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Circle().fill(modelColor(row.model)).frame(width: 7, height: 7)
                                Text(row.model).font(.system(size: compact ? 10 : 12, weight: .medium)).lineLimit(1).help(row.model)
                                Spacer(minLength: 5)
                                Text(shortTokens(row.totalTokens)).font(.system(size: compact ? 11 : 13, weight: .semibold, design: .monospaced)).help(exactTokens(row.totalTokens))
                            }
                            HStack(spacing: 10) {
                                metric(L("输入"), row.inputTokens)
                                metric(L("缓存⊂输入"), row.cachedInputTokens)
                                metric(L("输出"), row.outputTokens)
                                if !compact { metric(L("推理⊂输出"), row.reasoningOutputTokens) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var rangeTotalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(rangeHours == 24 ? L("24 小时模型合计") : L("7 天模型合计")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(L("总量")).font(.system(size: compact ? 9 : 11)).foregroundStyle(ink.secondary)
            }
            if rangeTotals.isEmpty {
                Text(L("此范围没有已记录的用量。空白时段不是经过确认的零消耗。"))
                    .font(.system(size: compact ? 10 : 12)).foregroundStyle(ink.secondary)
            } else {
                ForEach(rangeTotals) { row in
                    HStack(spacing: 7) {
                        Circle().fill(modelColor(row.model)).frame(width: 7, height: 7)
                        Text(row.model).font(.system(size: compact ? 10 : 12)).lineLimit(1).help(row.model)
                        Spacer()
                        GeometryReader { proxy in
                            Capsule().fill(modelColor(row.model).opacity(0.65))
                                .frame(width: proxy.size.width * Double(row.totalTokens) / Double(max(1, rangeTotals.first?.totalTokens ?? 1)))
                        }.frame(width: 120, height: 4).accessibilityHidden(true)
                        Text(shortTokens(row.totalTokens)).font(.system(size: compact ? 10 : 12, design: .monospaced)).help(exactTokens(row.totalTokens))
                    }
                }
                Divider().overlay(.white.opacity(0.08))
                HStack {
                    Text(L("范围合计")).font(.system(size: compact ? 10 : 12, weight: .semibold))
                    Spacer()
                    Text(shortTokens(rangeGrandTotal)).font(.system(size: compact ? 10 : 12, weight: .semibold, design: .monospaced)).help(exactTokens(rangeGrandTotal))
                }
            }
        }.padding(.top, 2)
    }

    private func footer(_ report: LocalTokenReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("含缓存 token；缓存是输入的子集，推理 token 是输出的子集，不重复累加。"))
            Text(L("这是本机活动记录，可能覆盖多个账户；非订阅额度，未绑定当前账户。缩写为近似值，悬停可查看精确数值。"))
            Text(L("模型名称来自轮次上下文。"))
            Text(L("已读取 {{0}} 个会话文件 · 更新于 {{1}}", String(describing: report.filesRead), String(describing: dateTime(report.generatedAt))))
        }.font(.system(size: compact ? 9 : 11)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func statusCard(title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(color).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: compact ? 11 : 13, weight: .semibold))
                Text(L(detail)).font(.system(size: compact ? 10 : 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ label: String, _ value: Int64) -> some View {
        Text("\(label) \(shortTokens(value))")
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(ink.secondary)
            .lineLimit(1).help("\(label)：\(exactTokens(value))")
    }

    private func aggregate(_ input: [HourlyModelTokens]) -> [HourlyModelTokens] {
        let groups = Dictionary(grouping: input) { "\($0.hour.timeIntervalSince1970)|\($0.model)" }
        return groups.values.compactMap { group in
            guard let first = group.first else { return nil }
            return HourlyModelTokens(
                hour: first.hour, model: first.model,
                inputTokens: group.reduce(0) { $0 + $1.inputTokens },
                cachedInputTokens: group.reduce(0) { $0 + $1.cachedInputTokens },
                outputTokens: group.reduce(0) { $0 + $1.outputTokens },
                reasoningOutputTokens: group.reduce(0) { $0 + $1.reasoningOutputTokens },
                totalTokens: group.reduce(0) { $0 + $1.totalTokens },
                eventCount: group.reduce(0) { $0 + $1.eventCount }
            )
        }
    }

    private func modelColor(_ model: String) -> Color {
        let allModels = Array(Set((report?.rows ?? []).map(\.model))).sorted()
        return palette[(allModels.firstIndex(of: model) ?? 0) % palette.count]
    }

    private func shortTokens(_ value: Int64) -> String {
        let absolute = abs(Double(value))
        if absolute >= 100_000_000 { return String(format: L("%.1f亿"), Double(value) / 100_000_000) }
        if absolute >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if absolute >= 10_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func exactTokens(_ value: Int64) -> String {
        "\(NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)) tokens"
    }

    private func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.timeZone = shanghai
        formatter.dateFormat = L("M月d日 HH:mm")
        return formatter.string(from: date)
    }

    private func axisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.timeZone = shanghai
        formatter.dateFormat = rangeHours > 24 ? "M/d HH" : "HH:mm"
        return formatter.string(from: date)
    }
}
