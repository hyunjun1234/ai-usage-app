import Foundation

enum Fmt {
    /// 1_234_567 -> "1.2M", 12_345 -> "12.3K"
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        switch abs(v) {
        case 1_000_000_000...: return trim(v / 1_000_000_000) + "B"
        case 1_000_000...:     return trim(v / 1_000_000) + "M"
        case 1_000...:         return trim(v / 1_000) + "K"
        default:               return "\(n)"
        }
    }

    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    /// 8.3 -> "$8.30", 1234.5 -> "$1,235"
    static func currency(_ v: Double) -> String {
        if v >= 1000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return "$" + (f.string(from: NSNumber(value: v)) ?? "\(Int(v))")
        }
        return String(format: "$%.2f", v)
    }
}

/// Best-effort Int from a JSON value.
func intValue(_ any: Any?) -> Int {
    switch any {
    case let i as Int:      return i
    case let d as Double:   return Int(d)
    case let n as NSNumber: return n.intValue
    default:                return 0
    }
}
