import Foundation
import Combine
import ServiceManagement

/// Claude subscription plan — drives the (estimated) budget.
enum ClaudePlan: String, CaseIterable {
    case pro, max5x, max20x
    var label: String {
        switch self {
        case .pro:    return "Pro"
        case .max5x:  return "Max 5x"
        case .max20x: return "Max 20x"
        }
    }
    /// Estimated 5-hour spend budget in USD — calibrated against Claude's panel.
    var fiveHourBudget: Double {
        switch self {
        case .pro:    return 72
        case .max5x:  return 360
        case .max20x: return 1440
        }
    }
    /// Estimated weekly spend budget in USD — calibrated against Claude's panel.
    var weeklyBudget: Double {
        switch self {
        case .pro:    return 181
        case .max5x:  return 906
        case .max20x: return 3624
        }
    }
}

/// Everything the UI needs, recomputed whenever inputs change.
struct Snapshot {
    var claudeWindows: [LimitWindow] = []
    var codexWindows: [LimitWindow] = []
    var dayBars: [DayBar] = []
    var quip = Quip(text: "불러오는 중…", symbol: "hourglass", level: 0)
    var lastUpdated: Date?
    var codexOK = true
    var codexFetched: Date?
    var codexPlan: String?

    func windows(for tool: Tool) -> [LimitWindow] {
        tool == .claude ? claudeWindows : codexWindows
    }
    /// Used percent for one tool's chosen window.
    func percent(_ tool: Tool, _ kind: WindowKind) -> Double? {
        windows(for: tool).first { $0.kind == kind }?.usedPercent
    }
}

/// Owns the parsers, drives refreshes, and publishes a derived Snapshot.
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published var claudePlan: ClaudePlan {
        didSet {
            UserDefaults.standard.set(claudePlan.rawValue, forKey: "claudePlan")
            recompute()
        }
    }
    /// Which window the menu bar shows (5-hour or weekly).
    @Published var menuWindow: WindowKind {
        didSet { UserDefaults.standard.set(menuWindow.rawValue, forKey: "menuWindow") }
    }

    private var events: [UsageEvent] = []
    private var codexLimits: CodexLimitsResult?
    private var codexFetchOK = true
    private var lastUpdated: Date?
    private var codexFetchedAt: Date?
    private var codexInFlight = false

    private let claude = ClaudeParser()
    private let codex = CodexParser()
    private let scanQueue = DispatchQueue(label: "aiusage.scan")
    private let codexQueue = DispatchQueue(label: "aiusage.codex")

    init() {
        claudePlan = ClaudePlan(rawValue: UserDefaults.standard.string(forKey: "claudePlan") ?? "")
            ?? .max5x
        menuWindow = WindowKind(rawValue: UserDefaults.standard.string(forKey: "menuWindow") ?? "")
            ?? .fiveHour
    }

    // MARK: - Refresh

    func refresh(force: Bool = false) {
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            self.claude.scan()
            self.codex.scan()
            let merged = self.claude.events + self.codex.events
            DispatchQueue.main.async {
                self.events = merged
                self.lastUpdated = Date()
                self.recompute()
            }
        }
        let stale = codexFetchedAt.map { Date().timeIntervalSince($0) > 300 } ?? true
        if force || stale { refreshCodexLimits() }
    }

    func refreshCodexLimits() {
        if codexInFlight { return }
        codexInFlight = true
        codexQueue.async { [weak self] in
            let result = CodexAppServer.fetchRateLimits()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.codexInFlight = false
                self.codexFetchedAt = Date()
                if let result = result {
                    self.codexLimits = result
                    self.codexFetchOK = true
                } else {
                    self.codexFetchOK = false
                }
                self.recompute()
            }
        }
    }

    // MARK: - Derived snapshot

    private func recompute() {
        let cWindows = claudeWindows()
        let xWindows = [codexLimits?.fiveHour, codexLimits?.weekly].compactMap { $0 }
        let bars = dailySeries(days: 14)
        let maxPct = (cWindows + xWindows).map { $0.usedPercent }.max()
        snapshot = Snapshot(
            claudeWindows: cWindows,
            codexWindows: xWindows,
            dayBars: bars,
            quip: makeQuip(maxPct),
            lastUpdated: lastUpdated,
            codexOK: codexFetchOK,
            codexFetched: codexFetchedAt,
            codexPlan: codexLimits?.planType)
    }

    // MARK: - Claude windows (estimated)

    private func claudeWindows() -> [LimitWindow] {
        let claudeEvents = events.filter { $0.tool == .claude }.sorted { $0.date < $1.date }
        return [claudeFiveHour(claudeEvents), claudeWeekly(claudeEvents)]
    }

    private func claudeFiveHour(_ sorted: [UsageEvent]) -> LimitWindow {
        let blockLength: TimeInterval = 5 * 3600
        // Claude's session window starts at the block's first message, floored
        // to the nearest 10 minutes, and runs 5 hours. Once it elapses the
        // window stays at 0% until the next message starts a fresh block.
        var blockStart: Date?
        for t in claude.activityDates.sorted() {
            if let bs = blockStart, t < bs.addingTimeInterval(blockLength) { continue }
            blockStart = UsageStore.floor10Minutes(t)
        }
        guard let bs = blockStart else {
            return LimitWindow(kind: .fiveHour, usedPercent: 0, resetsAt: nil, isReal: false)
        }
        let blockEnd = bs.addingTimeInterval(blockLength)
        if Date() >= blockEnd {   // window elapsed — 0% until next use
            return LimitWindow(kind: .fiveHour, usedPercent: 0, resetsAt: nil, isReal: false)
        }
        let cost = sorted.filter { $0.date >= bs }.reduce(0) { $0 + $1.cost }
        let budget = claudePlan.fiveHourBudget
        return LimitWindow(kind: .fiveHour,
                           usedPercent: budget > 0 ? cost / budget * 100 : 0,
                           resetsAt: blockEnd, isReal: false)
    }

    /// Floors a date down to the nearest 10-minute boundary.
    static func floor10Minutes(_ date: Date) -> Date {
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 600).rounded(.down) * 600)
    }

    private func claudeWeekly(_ sorted: [UsageEvent]) -> LimitWindow {
        let weekStart = UsageStore.weeklyAnchor(before: Date())
        let cost = sorted.filter { $0.date >= weekStart }.reduce(0) { $0 + $1.cost }
        let budget = claudePlan.weeklyBudget
        return LimitWindow(kind: .weekly,
                           usedPercent: budget > 0 ? cost / budget * 100 : 0,
                           resetsAt: weekStart.addingTimeInterval(7 * 86400), isReal: false)
    }

    /// Most recent Friday 02:00 local — matches Claude's weekly reset.
    static func weeklyAnchor(before date: Date) -> Date {
        var comps = DateComponents()
        comps.weekday = 6        // Friday (1 = Sunday)
        comps.hour = 2
        comps.minute = 0
        return Calendar.current.nextDate(after: date, matching: comps,
                                         matchingPolicy: .nextTime,
                                         direction: .backward)
            ?? Calendar.current.startOfDay(for: date)
    }

    // MARK: - Trend chart

    private func dailySeries(days: Int) -> [DayBar] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var byDay: [Date: DayBar] = [:]
        for e in events {
            let day = cal.startOfDay(for: e.date)
            var bar = byDay[day] ?? DayBar(day: day)
            if e.tool == .claude {
                bar.claudeCost += e.cost
                bar.claudeTokens += e.counts.total
            } else {
                bar.codexCost += e.cost
                bar.codexTokens += e.counts.total
            }
            byDay[day] = bar
        }
        var out: [DayBar] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -i, to: today) ?? today
            out.append(byDay[day] ?? DayBar(day: day))
        }
        return out
    }

    // MARK: - Quip

    private func makeQuip(_ maxPercent: Double?) -> Quip {
        guard let p = maxPercent else {
            return Quip(text: "사용량을 불러오는 중…", symbol: "hourglass", level: 0)
        }
        switch p {
        case ..<30:  return Quip(text: "아직 한참 여유로워요", symbol: "leaf.fill", level: 0)
        case ..<60:  return Quip(text: "순항 중 — 페이스 좋아요", symbol: "paperplane.fill", level: 0)
        case ..<80:  return Quip(text: "슬슬 속도를 조절할 때", symbol: "gauge.with.needle", level: 1)
        case ..<100: return Quip(text: "한도가 코앞입니다", symbol: "exclamationmark.triangle.fill", level: 2)
        default:     return Quip(text: "한도 초과 — 잠시 숨 고르기", symbol: "flame.fill", level: 3)
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("AI Usage: launch-at-login toggle failed: \(error)")
            }
            objectWillChange.send()
        }
    }
}
