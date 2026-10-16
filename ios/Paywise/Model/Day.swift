import Foundation

/// Calendar days as the contracts write them (yyyy-MM-dd) and as the app shows them ("Oct 17, 2026", "Oct 17").
/// English month names on purpose: the copy in SPEC §5.5, §6.3 and §15.7 is written that way.
enum Day {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// yyyy-MM-dd in `timeZone`.
    static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        CheckFlow.clientDate(date, timeZone: timeZone)
    }

    /// Today for the app: the "Pretend today is…" day when it is on, else the phone's date.
    static func today(settings: PaywiseSettings, now: Date = .now, timeZone: TimeZone = .current) -> String {
        settings.dateOverrideDay ?? string(now, timeZone: timeZone)
    }

    /// Noon on that day in `timeZone` (noon, so a time-zone change never moves it to another day).
    static func date(_ day: String, timeZone: TimeZone = .current) -> Date? {
        guard PaywiseSettings.isDay(day) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// "2027-02-14" → "Feb 14, 2027" (the "MMM d, yyyy" of §15.7 step 12a).
    static func medium(_ day: String) -> String? {
        ResultText.shortDate(day)
    }

    /// "2026-10-17" → "Oct 17" (§5.5 "Did you pay with Freedom ••1234 on Oct 17?").
    static func monthDay(_ day: String) -> String? {
        guard PaywiseSettings.isDay(day) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return "\(months[parts[1] - 1]) \(parts[2])"
    }
}
