import Foundation

struct PlannedNotification: Equatable, Identifiable {
    var id: String
    var fireDate: Date
    var title: String
    var body: String
    var timeZone: TimeZone
}

struct NotificationPlanBuilder {
    private let engine = EarningsEngine()
    private let schedule = WorkScheduleService()

    func buildPlan(
        context: EarningsContext,
        now: Date,
        horizonDays: Int = 21,
        maxCount: Int = 56
    ) -> [PlannedNotification] {
        guard context.preferences.notificationsEnabled,
              let today = engine.currentDay(at: now, context: context) else { return [] }

        var planned: [PlannedNotification] = []
        let dayCount = max(1, horizonDays)
        var candidateDays: [DayKey] = []
        if let activeShiftDay = engine.activeShiftDay(at: now, context: context), activeShiftDay < today {
            candidateDays.append(activeShiftDay)
        }
        candidateDays.append(contentsOf: (0..<dayCount).map { today.addingDays($0) })

        for day in candidateDays {
            if let workStart = context.preferences.workStartDay, day < workStart { continue }
            if context.dayOverrides[day]?.isDayOff == true { continue }
            guard let configuration = engine.configuration(for: day, configurations: context.configurations),
                  schedule.shiftInterval(day: day, configuration: configuration) != nil else { continue }

            for breakItem in configuration.breaks {
                guard let interval = schedule.intersectingBreakInterval(day: day, break: breakItem, configuration: configuration) else { continue }
                let rule = context.notificationRules[breakItem.stableKey] ?? .empty(for: breakItem.stableKey)

                for minutes in rule.allStartOffsets {
                    let fireDate = interval.start.addingTimeInterval(TimeInterval(-minutes * 60))
                    guard fireDate > now else { continue }
                    planned.append(PlannedNotification(
                        id: identifier(day: day, breakKey: breakItem.stableKey, phase: .start, offset: minutes),
                        fireDate: fireDate,
                        title: breakItem.name,
                        body: startBody(name: breakItem.name, minutes: minutes),
                        timeZone: configuration.timeZone
                    ))
                }

                for minutes in rule.allEndOffsets {
                    let fireDate = interval.end.addingTimeInterval(TimeInterval(-minutes * 60))
                    guard fireDate > now else { continue }
                    planned.append(PlannedNotification(
                        id: identifier(day: day, breakKey: breakItem.stableKey, phase: .end, offset: minutes),
                        fireDate: fireDate,
                        title: breakItem.name,
                        body: endBody(name: breakItem.name, minutes: minutes),
                        timeZone: configuration.timeZone
                    ))
                }
            }
        }

        var seen = Set<String>()
        return planned
            .sorted(by: { $0.fireDate < $1.fireDate })
            .filter { seen.insert($0.id).inserted }
            .prefix(max(0, maxCount))
            .map { $0 }
    }

    private func identifier(day: DayKey, breakKey: String, phase: BreakPhase, offset: Int) -> String {
        "work-break.\(day.rawValue).\(breakKey).\(phase.rawValue).\(offset)"
    }

    private func startBody(name: String, minutes: Int) -> String {
        if minutes == 0 { return "\(name) начинается сейчас" }
        if name.caseInsensitiveCompare("Обед") == .orderedSame {
            return "До обеда \(RussianPlural.minutes(minutes))"
        }
        return "До начала: \(RussianPlural.minutes(minutes))"
    }

    private func endBody(name: String, minutes: Int) -> String {
        if minutes == 0 { return "\(name) заканчивается сейчас" }
        return "\(name) закончится через \(RussianPlural.minutes(minutes))"
    }
}
