import Foundation

enum BreakType: String, Codable, CaseIterable, Identifiable {
    case smoke
    case lunch
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smoke: return "Перекур"
        case .lunch: return "Обед"
        case .custom: return "Перерыв"
        }
    }
}

enum CounterMode: String, Codable, CaseIterable, Identifiable {
    case regular
    case smooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return "Обычный"
        case .smooth: return "Плавный"
        }
    }

    var refreshInterval: TimeInterval {
        switch self {
        case .regular: return 1.0
        case .smooth: return 0.10
        }
    }
}

enum BreakPhase: String, Codable {
    case start
    case end
}

struct BreakSnapshot: Identifiable, Hashable, Codable {
    var id: UUID
    var stableKey: String
    var name: String
    var startMinute: Int
    var endMinute: Int
    var isPaid: Bool
    var type: BreakType
    var sortOrder: Int

    static let defaults: [BreakSnapshot] = [
        BreakSnapshot(id: UUID(), stableKey: "smoke-1", name: "Перекур", startMinute: 10 * 60, endMinute: 10 * 60 + 20, isPaid: true, type: .smoke, sortOrder: 0),
        BreakSnapshot(id: UUID(), stableKey: "lunch", name: "Обед", startMinute: 12 * 60, endMinute: 13 * 60, isPaid: false, type: .lunch, sortOrder: 1),
        BreakSnapshot(id: UUID(), stableKey: "smoke-2", name: "Перекур", startMinute: 16 * 60, endMinute: 16 * 60 + 20, isPaid: true, type: .smoke, sortOrder: 2)
    ]
}

struct WorkConfigurationSnapshot: Identifiable, Hashable, Codable {
    var id: UUID
    var effectiveFrom: DayKey
    var hourlyRate: Decimal
    var shiftStartMinute: Int
    var shiftDurationMinutes: Int
    var timeZoneOffsetSeconds: Int
    var breaks: [BreakSnapshot]

    var timeZone: TimeZone {
        TimeZone(secondsFromGMT: timeZoneOffsetSeconds) ?? TimeZone(secondsFromGMT: 0)!
    }
}

struct DayOverrideSnapshot: Hashable, Codable {
    var day: DayKey
    var isDayOff: Bool
    var overtimeMinutes: Int
    var overtimeMultiplier: Decimal
}

struct NotificationRuleSnapshot: Hashable, Codable {
    var breakKey: String
    var beforeStartOffsets: Set<Int>
    var beforeEndOffsets: Set<Int>
    var customStartOffsets: Set<Int>
    var customEndOffsets: Set<Int>

    var allStartOffsets: [Int] {
        Array(beforeStartOffsets.union(customStartOffsets)).sorted(by: >)
    }

    var allEndOffsets: [Int] {
        Array(beforeEndOffsets.union(customEndOffsets)).sorted(by: >)
    }

    static func empty(for breakKey: String) -> NotificationRuleSnapshot {
        NotificationRuleSnapshot(
            breakKey: breakKey,
            beforeStartOffsets: [],
            beforeEndOffsets: [],
            customStartOffsets: [],
            customEndOffsets: []
        )
    }
}

struct AppPreferencesSnapshot: Hashable, Codable {
    var onboardingCompleted: Bool
    var workStartDay: DayKey?
    var notificationsEnabled: Bool
    var counterMode: CounterMode
}

struct EarningsContext: Hashable, Codable {
    var configurations: [WorkConfigurationSnapshot]
    var dayOverrides: [DayKey: DayOverrideSnapshot]
    var notificationRules: [String: NotificationRuleSnapshot]
    var preferences: AppPreferencesSnapshot
}

enum ShiftState: Equatable {
    case notConfigured
    case beforeWorkStart
    case beforeShift
    case working
    case paidBreak(String)
    case unpaidBreak(String)
    case completed
    case dayOff

    var title: String {
        switch self {
        case .notConfigured: return "Нужна настройка"
        case .beforeWorkStart: return "Работа ещё не началась"
        case .beforeShift: return "Смена ещё не началась"
        case .working: return "Смена идёт"
        case .paidBreak(let name): return name
        case .unpaidBreak(let name): return name
        case .completed: return "Смена завершена"
        case .dayOff: return "Выходной"
        }
    }
}

struct ActiveBreak: Equatable {
    var name: String
    var isPaid: Bool
    var start: Date
    var end: Date
}

struct DayEarnings: Equatable {
    var day: DayKey
    var baseEarnings: Decimal
    var overtimeEarnings: Decimal
    var paidMilliseconds: Int64
    var state: ShiftState
    var shiftStart: Date?
    var shiftEnd: Date?
    var activeBreak: ActiveBreak?
    var progress: Double
    var secondsRemaining: TimeInterval

    var totalEarnings: Decimal { baseEarnings + overtimeEarnings }

    static func zero(day: DayKey, state: ShiftState) -> DayEarnings {
        DayEarnings(
            day: day,
            baseEarnings: 0,
            overtimeEarnings: 0,
            paidMilliseconds: 0,
            state: state,
            shiftStart: nil,
            shiftEnd: nil,
            activeBreak: nil,
            progress: 0,
            secondsRemaining: 0
        )
    }
}

struct DashboardSnapshot {
    var day: DayEarnings
    var monthEarnings: Decimal
    var allTimeEarnings: Decimal
}
