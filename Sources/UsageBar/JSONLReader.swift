import Foundation

/// Reads newly appended whole lines from a file, tracking a byte offset so
/// repeated scans only touch new data. A trailing partial line (no newline
/// yet) is left unconsumed for the next call.
func readNewLines(path: String, from offset: Int) -> (lines: [Substring], newOffset: Int) {
    guard let handle = FileHandle(forReadingAtPath: path) else { return ([], offset) }
    defer { try? handle.close() }

    let size = Int((try? handle.seekToEnd()) ?? 0)
    let start = (offset > size) ? 0 : offset      // file shrank/rotated -> re-read
    guard size > start else { return ([], size) }

    try? handle.seek(toOffset: UInt64(start))
    guard let data = try? handle.readToEnd(), !data.isEmpty else { return ([], start) }
    guard let lastNL = data.lastIndex(of: 0x0A) else { return ([], start) }

    let consumed = start + lastNL + 1
    let text = String(decoding: data[...lastNL], as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    return (lines, consumed)
}
