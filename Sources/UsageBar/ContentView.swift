import SwiftUI
import AppKit

enum Theme {
    static let claude = Color(red: 0.83, green: 0.46, blue: 0.31)
    static let codex  = Color(red: 0.15, green: 0.63, blue: 0.51)
    static let brand  = Color(red: 0.47, green: 0.40, blue: 0.92)

    static func limitColor(_ fraction: Double, base: Color) -> Color {
        if fraction >= 1.0 { return .red }
        if fraction >= 0.8 { return .orange }
        return base
    }
    static func quipColor(_ level: Int) -> Color {
        switch level {
        case 0:  return .green
        case 1:  return .yellow
        case 2:  return .orange
        default: return .red
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @State private var hoveredDay: DayBar?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            quipBanner
            if store.toolFilter.showsClaude { claudeCard }
            if store.toolFilter.showsCodex { codexCard }
            chartSection
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title3)
                .foregroundStyle(Theme.brand)
            Text("AI Usage").font(.headline)
            Spacer()
            Text(updatedText).font(.caption2).foregroundStyle(.secondary)
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture { store.manualRefresh() }
                    .help("새로고침")
            }
        }
        .frame(height: 22)
    }

    private var updatedText: String {
        if store.isRefreshing { return "업데이트 중…" }
        guard let d = store.snapshot.lastUpdated else { return "불러오는 중…" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "방금 업데이트" }
        if s < 3600 { return "\(s / 60)분 전" }
        return "\(s / 3600)시간 전"
    }

    // MARK: Quip

    private var quipBanner: some View {
        let quip = store.snapshot.quip
        let color = Theme.quipColor(quip.level)
        return HStack(spacing: 7) {
            Image(systemName: quip.symbol).foregroundStyle(color)
            Text(quip.text).font(.callout.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Cards

    private var claudeCard: some View {
        let snap = store.snapshot
        let hasData = !snap.claudeWindows.isEmpty
        let note: String?
        let login: (() -> Void)?
        if hasData {
            note = nil; login = nil
        } else if snap.claudeLoggedOut {
            note = "claude.ai에 로그인하면 실제 5시간·주간 한도가 표시됩니다."
            login = { store.showClaudeLogin() }
        } else {
            note = "claude.ai에서 한도를 불러오는 중…"
            login = nil
        }
        return ToolCard(tool: .claude, accent: Theme.claude,
                        badge: hasData ? "실시간" : "", badgeReal: true,
                        subtitle: snap.claudePlan ?? "",
                        windows: snap.claudeWindows,
                        note: note,
                        loginAction: login)
    }

    private var codexCard: some View {
        let snap = store.snapshot
        let note: String?
        if !snap.codexWindows.isEmpty {
            note = nil
        } else if snap.codexFetched == nil {
            note = "불러오는 중…"
        } else {
            note = "Codex 한도를 불러오지 못했습니다.\nCodex 앱이 설치·로그인되어 있는지 확인하세요."
        }
        return ToolCard(tool: .codex, accent: Theme.codex,
                        badge: snap.codexWindows.isEmpty ? "" : "실시간",
                        badgeReal: !snap.codexWindows.isEmpty,
                        subtitle: snap.codexPlan.map { $0.capitalized } ?? "",
                        windows: snap.codexWindows,
                        note: note)
    }

    // MARK: Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let day = hoveredDay {
                    Text(hoverText(day))
                        .font(.caption).foregroundStyle(.primary)
                    Spacer()
                } else {
                    Text("최근 14일 · 추정 비용")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    legendDot(Theme.claude, "Claude")
                    legendDot(Theme.codex, "Codex")
                }
            }
            .frame(height: 14)
            DailyBarChart(bars: store.snapshot.dayBars, hovered: $hoveredDay)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func hoverText(_ day: DayBar) -> String {
        func tok(_ n: Int) -> String { n == 0 ? "0" : "\(Fmt.compact(n))토큰" }
        return "\(Fmt.hoverDay(day.day)) · Claude \(tok(day.claudeTokens)) · Codex \(tok(day.codexTokens))"
    }

    // MARK: Footer

}

/// One tool card: name + badge + two limit windows (5시간 / 주간).
struct ToolCard: View {
    let tool: Tool
    let accent: Color
    let badge: String
    let badgeReal: Bool
    let subtitle: String
    let windows: [LimitWindow]
    let note: String?
    var loginAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text(tool.label).font(.subheadline.weight(.semibold))
                if !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background((badgeReal ? accent : Color.secondary).opacity(0.18), in: Capsule())
                        .foregroundStyle(badgeReal ? accent : Color.secondary)
                }
                Spacer()
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if windows.isEmpty {
                Text(note ?? "데이터 없음")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(windows) { WindowRow(window: $0, accent: accent) }
                if let note = note {
                    Text(note)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let loginAction = loginAction {
                Button(action: loginAction) {
                    Text("Claude.ai 로그인 → 실시간 사용량")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.22)))
    }
}

/// One window row: label · gauge bar · percent, with a reset hint below.
struct WindowRow: View {
    let window: LimitWindow
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(window.kind.label)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                GaugeBar(fraction: window.usedPercent / 100, accent: accent)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.limitColor(window.usedPercent / 100, base: .primary))
                    .frame(width: 46, alignment: .trailing)
            }
            if let reset = window.resetText {
                Text(reset)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.leading, 50)
            }
        }
    }
}

/// Horizontal gauge bar: fills, turning orange/red as it nears/exceeds 100%.
struct GaugeBar: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        let color = Theme.limitColor(fraction, base: accent)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(0.15))
                Capsule().fill(color).frame(width: max(3, geo.size.width * clamped))
            }
        }
        .frame(height: 7)
    }
}

/// 14-day grouped bar chart. Bars sit on a shared baseline; hovering a day's
/// column reports it via `hovered`.
struct DailyBarChart: View {
    let bars: [DayBar]
    @Binding var hovered: DayBar?
    private let height: CGFloat = 58

    var body: some View {
        let maxCost = max(bars.map { max($0.claudeCost, $0.codexCost) }.max() ?? 0, 0.01)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(bars) { day in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 2) {
                        bar(day.claudeCost / maxCost, Theme.claude)
                        bar(day.codexCost / maxCost, Theme.codex)
                    }
                }
                .frame(width: 18, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(hovered?.day == day.day ? Color.primary.opacity(0.10) : Color.clear)
                )
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = day }
                    else if hovered?.day == day.day { hovered = nil }
                }
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func bar(_ fraction: Double, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 6, height: max(2, CGFloat(min(max(fraction, 0), 1)) * height))
    }
}
