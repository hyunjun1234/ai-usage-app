import Foundation
import Combine
import ServiceManagement

/// Which tools the menu bar and popover show.
enum ToolFilter: String, CaseIterable {
    case both, claudeOnly, codexOnly
    var label: String {
        switch self {
        case .both:       return "Claude · Codex 모두"
        case .claudeOnly: return "Claude만"
        case .codexOnly:  return "Codex만"
        }
    }
    var showsClaude: Bool { self != .codexOnly }
    var showsCodex: Bool { self != .claudeOnly }
}

/// Auto-refresh cadence, selectable from the right-click menu.
enum RefreshInterval: Int, CaseIterable {
    case s10 = 10, s30 = 30, m1 = 60, m5 = 300, m10 = 600
    var label: String {
        switch self {
        case .s10: return "10초"
        case .s30: return "30초"
        case .m1:  return "1분"
        case .m5:  return "5분"
        case .m10: return "10분"
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
    var claudeLoggedOut = false

    func windows(for tool: Tool) -> [LimitWindow] {
        tool == .claude ? claudeWindows : codexWindows
    }
    /// Used percent for one tool's chosen window.
    func percent(_ tool: Tool, _ kind: WindowKind) -> Double? {
        windows(for: tool).first { $0.kind == kind }?.usedPercent
    }
}

/// Owns the data sources, drives refreshes, and publishes a derived Snapshot.
/// Both tools now report *real* limits — Codex via `codex app-server`,
/// Claude via a signed-in claude.ai web session.
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isRefreshing = false
    @Published var menuWindow: WindowKind {
        didSet { UserDefaults.standard.set(menuWindow.rawValue, forKey: "menuWindow") }
    }
    @Published var toolFilter: ToolFilter {
        didSet { UserDefaults.standard.set(toolFilter.rawValue, forKey: "toolFilter") }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet { UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval") }
    }

    private var events: [UsageEvent] = []          // for the 14-day trend chart
    private var codexLimits: CodexLimitsResult?
    private var codexFetchOK = true
    private var lastUpdated: Date?
    private var codexFetchedAt: Date?
    private var codexInFlight = false

    private let claude = ClaudeParser()
    private let codex = CodexParser()
    private let scanQueue = DispatchQueue(label: "aiusage.scan")
    private let codexQueue = DispatchQueue(label: "aiusage.codex")

    private let claudeWeb = ClaudeWebSession()
    private var claudeReal: (fiveHour: LimitWindow, weekly: LimitWindow)?
    private var claudeLoggedOut = false
    private var didAutoPromptLogin = false

    init() {
        menuWindow = WindowKind(rawValue: UserDefaults.standard.string(forKey: "menuWindow") ?? "")
            ?? .fiveHour
        toolFilter = ToolFilter(rawValue: UserDefaults.standard.string(forKey: "toolFilter") ?? "")
            ?? .both
        refreshInterval = RefreshInterval(
            rawValue: UserDefaults.standard.integer(forKey: "refreshInterval")) ?? .s10

        claudeWeb.onResult = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .ok(let five, let week):
                self.claudeReal = (five, week)
                self.claudeLoggedOut = false
            case .loggedOut:
                self.claudeReal = nil
                self.claudeLoggedOut = true
                if !self.didAutoPromptLogin {
                    self.didAutoPromptLogin = true
                    self.claudeWeb.showLoginWindow()
                }
            case .error:
                break       // transient — keep the previous state
            }
            self.recompute()
        }
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
        // Cadence is driven by the menu-bar timer; in-flight guards prevent overlap.
        if toolFilter.showsCodex { refreshCodexLimits() }
        if toolFilter.showsClaude { claudeWeb.refreshUsage() }
    }

    /// Manual refresh from the popover button — shows a brief spinner.
    func manualRefresh() {
        isRefreshing = true
        refresh(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isRefreshing = false
        }
    }

    /// Opens the claude.ai sign-in window.
    func showClaudeLogin() {
        claudeWeb.showLoginWindow()
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
        let cWindows = claudeReal.map { [$0.fiveHour, $0.weekly] } ?? []
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
            codexPlan: codexLimits?.planType,
            claudeLoggedOut: claudeLoggedOut)
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
