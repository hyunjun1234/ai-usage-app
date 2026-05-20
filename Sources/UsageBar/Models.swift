import Foundation

enum Tool: String, CaseIterable, Hashable {
    case claude, codex
    var label: String { self == .claude ? "Claude" : "Codex" }
}

/// Token counts normalized into one shape shared by both tools.
struct TokenCounts {
    var input = 0        // non-cached input tokens
    var cachedInput = 0  // cache-read (Claude) / cached input (Codex)
    var cacheWrite = 0   // cache-creation (Claude only)
    var output = 0       // output tokens, including reasoning

    var total: Int { input + cachedInput + cacheWrite + output }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input,
                    cachedInput: a.cachedInput + b.cachedInput,
                    cacheWrite: a.cacheWrite + b.cacheWrite,
                    output: a.output + b.output)
    }
    static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }
}

/// One usage event — a single Claude assistant message or one Codex turn.
struct UsageEvent {
    let date: Date
    let tool: Tool
    let model: String
    let counts: TokenCounts
    var cost: Double { Pricing.cost(counts, model: model, tool: tool) }
}

/// The two limit windows both tools share.
enum WindowKind: String {
    case fiveHour, weekly
    var label: String { self == .fiveHour ? "5시간" : "주간" }
}

/// A usage window for display — real (Codex) or estimated (Claude).
struct LimitWindow: Identifiable {
    let kind: WindowKind
    var usedPercent: Double      // 0...100+
    var resetsAt: Date?
    var isReal: Bool

    var id: String { kind.label }

    /// Human reset hint, e.g. "오후 3:41 초기화" or "5/25 초기화".
    var resetText: String? {
        guard let r = resetsAt else { return nil }
        if r.timeIntervalSinceNow <= 0 { return "곧 초기화" }
        return Fmt.resetText(r)
    }
}

/// One day's totals for the trend chart.
struct DayBar: Identifiable {
    let day: Date
    var claudeCost = 0.0
    var claudeTokens = 0
    var codexCost = 0.0
    var codexTokens = 0
    var id: Date { day }
}

/// A light-hearted status line shown in the popover.
struct Quip {
    var text: String
    var symbol: String
    var level: Int   // 0 calm · 1 watch · 2 warn · 3 over
}
