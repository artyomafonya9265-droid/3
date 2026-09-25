import Foundation

struct DayKey: RawRepresentable, Hashable, Codable, Comparable, CustomStringConvertible, Identifiable {
    let rawValue: Int
    var id: Int { rawValue }

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(year: Int, month: Int, day: Int) {
        self.rawValue = year * 10_000 + month * 100 + day
    }

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    var year: Int { rawValue / 10_000 }
    var month: Int { (rawValue / 100) % 100 }
    var day: Int { rawValue % 100 }
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func date(atMinute minute: Int = 0, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = minute / 60
        components.minute = minute % 60
        components.second = 0
        return calendar.date(from: components)
    }

    func addingDays(_ value: Int) -> DayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
        let shifted = calendar.date(byAdding: .day, value: value, to: base) ?? base
        return DayKey(date: shifted, timeZone: calendar.timeZone)
    }

    var startOfMonth: DayKey {
        DayKey(year: year, month: month, day: 1)
    }

    func daysInMonth() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }
}
