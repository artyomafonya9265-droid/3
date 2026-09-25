import Foundation
import SwiftData

@Model
final class BreakEntity {
    var id: UUID
    var stableKey: String
    var name: String
    var startMinute: Int
    var endMinute: Int
    var isPaid: Bool
    var typeRaw: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        stableKey: String,
        name: String,
        startMinute: Int,
        endMinute: Int,
        isPaid: Bool,
        typeRaw: String,
        sortOrder: Int
    ) {
        self.id = id
        self.stableKey = stableKey
        self.name = name
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.isPaid = isPaid
        self.typeRaw = typeRaw
        self.sortOrder = sortOrder
    }
}

@Model
final class WorkConfigurationEntity {
    var id: UUID
    @Attribute(.unique) var effectiveFromRaw: Int
    var hourlyRateString: String
    var shiftStartMinute: Int
    var shiftDurationMinutes: Int
    var timeZoneOffsetSeconds: Int
    @Relationship(deleteRule: .cascade) var breaks: [BreakEntity]

    init(
        id: UUID = UUID(),
        effectiveFromRaw: Int,
        hourlyRateString: String,
        shiftStartMinute: Int,
        shiftDurationMinutes: Int,
        timeZoneOffsetSeconds: Int,
        breaks: [BreakEntity]
    ) {
        self.id = id
        self.effectiveFromRaw = effectiveFromRaw
        self.hourlyRateString = hourlyRateString
        self.shiftStartMinute = shiftStartMinute
        self.shiftDurationMinutes = shiftDurationMinutes
        self.timeZoneOffsetSeconds = timeZoneOffsetSeconds
        self.breaks = breaks
    }
}

@Model
final class DayOverrideEntity {
    var id: UUID
    @Attribute(.unique) var dayRaw: Int
    var isDayOff: Bool
    var overtimeMinutes: Int
    var overtimeMultiplierString: String

    init(
        id: UUID = UUID(),
        dayRaw: Int,
        isDayOff: Bool = false,
        overtimeMinutes: Int = 0,
        overtimeMultiplierString: String = "1"
    ) {
        self.id = id
        self.dayRaw = dayRaw
        self.isDayOff = isDayOff
        self.overtimeMinutes = overtimeMinutes
        self.overtimeMultiplierString = overtimeMultiplierString
    }
}

@Model
final class NotificationRuleEntity {
    var id: UUID
    @Attribute(.unique) var breakKey: String
    var beforeStartCSV: String
    var beforeEndCSV: String
    var customStartCSV: String
    var customEndCSV: String

    init(
        id: UUID = UUID(),
        breakKey: String,
        beforeStartCSV: String = "",
        beforeEndCSV: String = "",
        customStartCSV: String = "",
        customEndCSV: String = ""
    ) {
        self.id = id
        self.breakKey = breakKey
        self.beforeStartCSV = beforeStartCSV
        self.beforeEndCSV = beforeEndCSV
        self.customStartCSV = customStartCSV
        self.customEndCSV = customEndCSV
    }
}

@Model
final class AppPreferenceEntity {
    var id: UUID
    @Attribute(.unique) var singletonKey: String
    var onboardingCompleted: Bool
    var workStartDayRaw: Int?
    var notificationsEnabled: Bool
    var counterModeRaw: String

    init(
        id: UUID = UUID(),
        singletonKey: String = "main",
        onboardingCompleted: Bool = false,
        workStartDayRaw: Int? = nil,
        notificationsEnabled: Bool = false,
        counterModeRaw: String = CounterMode.regular.rawValue
    ) {
        self.id = id
        self.singletonKey = singletonKey
        self.onboardingCompleted = onboardingCompleted
        self.workStartDayRaw = workStartDayRaw
        self.notificationsEnabled = notificationsEnabled
        self.counterModeRaw = counterModeRaw
    }
}
