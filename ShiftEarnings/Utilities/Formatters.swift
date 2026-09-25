import Foundation

extension Decimal {
    func rounded(scale: Int = 2, mode: Decimal.RoundingMode = .bankers) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}

enum MoneyMath {
    static let millisecondsPerHour = Decimal(3_600_000)

    static func earnings(hourlyRate: Decimal, paidMilliseconds: Int64, multiplier: Decimal = 1) -> Decimal {
        guard paidMilliseconds > 0 else { return 0 }
        return hourlyRate * Decimal(paidMilliseconds) * multiplier / millisecondsPerHour
    }

    static func parseDecimal(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func canonicalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

enum AppFormatters {
    static func rubles(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .currency
        formatter.currencyCode = "RUB"
        formatter.currencySymbol = "₽"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfEven
        return formatter.string(from: NSDecimalNumber(decimal: amount.rounded())) ?? "0,00 ₽"
    }

    static func time(minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", (minuteOfDay / 60) % 24, minuteOfDay % 60)
    }

    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 { return "\(hours) ч \(mins) мин" }
        if hours > 0 { return "\(hours) ч" }
        return "\(mins) мин"
    }

    static func remaining(seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        return duration(minutes: totalMinutes)
    }

    static func date(_ day: DayKey) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: day.dateComponents) else { return day.description }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMMM yyyy, HH:mm:ss"
        return formatter.string(from: date)
    }

    static func signedDifference(_ seconds: TimeInterval) -> String {
        let sign = seconds >= 0 ? "+" : "−"
        var value = Int(abs(seconds).rounded())
        let days = value / 86_400
        value %= 86_400
        let hours = value / 3_600
        value %= 3_600
        let minutes = value / 60
        let secs = value % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) д") }
        if hours > 0 { parts.append("\(hours) ч") }
        if minutes > 0 { parts.append("\(minutes) мин") }
        parts.append("\(secs) сек")
        return sign + parts.joined(separator: " ")
    }
}

enum RussianPlural {
    static func minutes(_ value: Int) -> String {
        let mod10 = value % 10
        let mod100 = value % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "минуту"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "минуты"
        } else {
            word = "минут"
        }
        return "\(value) \(word)"
    }
}
