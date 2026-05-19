import Foundation

/// List price in USD per 1,000,000 tokens.
struct ModelPricing {
    var input: Double
    var cacheWrite: Double
    var cacheRead: Double
    var output: Double
}

enum Pricing {
    // Anthropic list pricing (per MTok).
    static let claudeOpus   = ModelPricing(input: 15, cacheWrite: 18.75, cacheRead: 1.5,   output: 75)
    static let claudeSonnet = ModelPricing(input: 3,  cacheWrite: 3.75,  cacheRead: 0.3,   output: 15)
    static let claudeHaiku  = ModelPricing(input: 1,  cacheWrite: 1.25,  cacheRead: 0.1,   output: 5)
    // OpenAI GPT-5 family list pricing (per MTok).
    static let gpt5         = ModelPricing(input: 1.25, cacheWrite: 0,   cacheRead: 0.125, output: 10)

    static func table(for model: String, tool: Tool) -> ModelPricing {
        let m = model.lowercased()
        switch tool {
        case .claude:
            if m.contains("opus")  { return claudeOpus }
            if m.contains("haiku") { return claudeHaiku }
            return claudeSonnet
        case .codex:
            return gpt5
        }
    }

    /// Estimated cost in USD, based on public list prices.
    static func cost(_ c: TokenCounts, model: String, tool: Tool) -> Double {
        let p = table(for: model, tool: tool)
        return Double(c.input)       / 1_000_000 * p.input
             + Double(c.cachedInput) / 1_000_000 * p.cacheRead
             + Double(c.cacheWrite)  / 1_000_000 * p.cacheWrite
             + Double(c.output)      / 1_000_000 * p.output
    }
}
