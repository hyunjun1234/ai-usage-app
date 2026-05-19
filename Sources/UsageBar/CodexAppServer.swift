import Foundation

struct CodexLimitsResult {
    var fiveHour: LimitWindow?
    var weekly: LimitWindow?
    var planType: String?
}

/// Talks to `codex app-server` over JSON-RPC to read the account's real
/// rate limits. This works whether Codex is used via the CLI or the desktop
/// app, because it queries the account directly. Codex itself handles auth.
enum CodexAppServer {

    static func locateBinary() -> String? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            NSString(string: "~/.codex/bin/codex").expandingTildeInPath,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Blocking — call on a background queue. Returns nil on any failure.
    static func fetchRateLimits() -> CodexLimitsResult? {
        guard let binary = locateBinary() else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["app-server"]
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }

        // Watchdog — terminate if the handshake or network call hangs.
        let watchdog = DispatchWorkItem {
            if proc.isRunning { proc.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)

        let writer = stdinPipe.fileHandleForWriting
        func send(_ json: String) {
            if let d = (json + "\n").data(using: .utf8) { try? writer.write(contentsOf: d) }
        }
        send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"aiusage","title":"AI Usage","version":"1.0"}}}"#)
        send(#"{"jsonrpc":"2.0","method":"initialized","params":{}}"#)
        send(#"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#)

        let reader = stdoutPipe.fileHandleForReading
        var buffer = Data()
        var result: CodexLimitsResult?
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }            // EOF — process gone
            buffer.append(chunk)
            let text = String(decoding: buffer, as: UTF8.self)
            for line in text.split(separator: "\n") {
                if let parsed = parse(Data(line.utf8)) { result = parsed }
            }
            if result != nil { break }
        }

        watchdog.cancel()
        try? writer.close()
        if proc.isRunning { proc.terminate() }
        return result
    }

    private static func parse(_ data: Data) -> CodexLimitsResult? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["id"] as? NSNumber)?.intValue == 2,
              let res = obj["result"] as? [String: Any],
              let limits = res["rateLimits"] as? [String: Any] else { return nil }

        func window(_ key: String, _ kind: WindowKind) -> LimitWindow? {
            guard let w = limits[key] as? [String: Any],
                  let pct = (w["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
            var reset: Date?
            if let r = (w["resetsAt"] as? NSNumber)?.doubleValue {
                reset = Date(timeIntervalSince1970: r)
            }
            return LimitWindow(kind: kind, usedPercent: pct, resetsAt: reset, isReal: true)
        }
        return CodexLimitsResult(
            fiveHour: window("primary", .fiveHour),
            weekly: window("secondary", .weekly),
            planType: limits["planType"] as? String)
    }
}
