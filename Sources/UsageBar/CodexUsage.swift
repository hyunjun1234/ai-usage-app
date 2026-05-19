import Foundation

/// Parses Codex CLI rollout transcripts in ~/.codex/sessions/**/rollout-*.jsonl
/// for per-turn token counts (used by the trend chart). Live rate limits come
/// from the app-server instead — see CodexAppServer.
final class CodexParser {
    private let root = NSString(string: "~/.codex/sessions").expandingTildeInPath
    private var offsets: [String: Int] = [:]
    private var modelByFile: [String: String] = [:]
    private(set) var events: [UsageEvent] = []

    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func scan() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root), let walker = fm.enumerator(atPath: root) else { return }
        for case let rel as String in walker
            where rel.hasSuffix(".jsonl") && rel.contains("rollout-") {
            let path = root + "/" + rel
            let (lines, newOffset) = readNewLines(path: path, from: offsets[path] ?? 0)
            offsets[path] = newOffset
            for line in lines { ingest(line, file: path) }
        }
    }

    private func ingest(_ line: Substring, file: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let type = obj["type"] as? String,
              let payload = obj["payload"] as? [String: Any] else { return }

        if type == "turn_context" {
            if let m = payload["model"] as? String, !m.isEmpty { modelByFile[file] = m }
            return
        }
        guard type == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String, let date = parseDate(ts) else { return }

        let totalInput = intValue(last["input_tokens"])
        let cached = intValue(last["cached_input_tokens"])
        var c = TokenCounts()
        c.cachedInput = cached
        c.input = max(0, totalInput - cached)
        c.output = intValue(last["output_tokens"])
        if c.total == 0 { return }

        let model = modelByFile[file] ?? "gpt-5"
        events.append(UsageEvent(date: date, tool: .codex, model: model, counts: c))
    }

    private func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }
}
