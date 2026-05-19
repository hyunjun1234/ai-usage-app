import Foundation

/// Parses Claude Code transcripts in ~/.claude/projects/**/*.jsonl
/// Each `assistant` line becomes one timestamped UsageEvent.
final class ClaudeParser {
    private let root = NSString(string: "~/.claude/projects").expandingTildeInPath
    private var offsets: [String: Int] = [:]
    private var seenIDs: Set<String> = []
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
        for case let rel as String in walker where rel.hasSuffix(".jsonl") {
            let path = root + "/" + rel
            let (lines, newOffset) = readNewLines(path: path, from: offsets[path] ?? 0)
            offsets[path] = newOffset
            for line in lines { ingest(line) }
        }
    }

    private func ingest(_ line: Substring) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return }

        let model = (message["model"] as? String) ?? "claude"
        if model.contains("synthetic") { return }

        // De-dup: the same response can appear in several transcript files.
        let id = (message["id"] as? String) ?? (obj["uuid"] as? String) ?? UUID().uuidString
        guard !seenIDs.contains(id) else { return }
        seenIDs.insert(id)

        guard let ts = obj["timestamp"] as? String, let date = parseDate(ts) else { return }

        var c = TokenCounts()
        c.input       = intValue(usage["input_tokens"])
        c.output      = intValue(usage["output_tokens"])
        c.cacheWrite  = intValue(usage["cache_creation_input_tokens"])
        c.cachedInput = intValue(usage["cache_read_input_tokens"])

        events.append(UsageEvent(date: date, tool: .claude, model: model, counts: c))
    }

    private func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }
}
