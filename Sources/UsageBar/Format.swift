import Foundation

enum Fmt {
    private static let resetTodayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm 초기화"
        return f
    }()

    private static let resetOtherDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d a h:mm 초기화"
        return f
    }()

    private static let claudeUsageISOFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let claudeUsageISOPlain = ISO8601DateFormatter()

    static func resetText(_ date: Date) -> String {
        let formatter = Calendar.current.isDateInToday(date)
            ? resetTodayFormatter
            : resetOtherDayFormatter
        return formatter.string(from: date)
    }

    static func claudeUsageResetDate(_ string: String) -> Date? {
        claudeUsageISOFractional.date(from: string) ?? claudeUsageISOPlain.date(from: string)
    }
}
