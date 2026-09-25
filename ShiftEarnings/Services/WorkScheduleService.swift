import Foundation

struct WorkScheduleService {
    func shiftInterval(day: DayKey, configuration: WorkConfigurationSnapshot) -> DateInterval? {
        guard configuration.shiftDurationMinutes > 0,
              let start = day.date(atMinute: configuration.shiftStartMinute, timeZone: configuration.timeZone) else { return nil }
        let end = start.addingTimeInterval(TimeInterval(configuration.shiftDurationMinutes * 60))
        return DateInterval(start: start, end: end)
    }

    func breakIntervals(day: DayKey, break item: BreakSnapshot, configuration: WorkConfigurationSnapshot) -> [DateInterval] {
        [day, day.addingDays(1)].compactMap { anchor in
            guard let start = anchor.date(atMinute: item.startMinute, timeZone: configuration.timeZone) else { return nil }
            let endDay = item.endMinute <= item.startMinute ? anchor.addingDays(1) : anchor
            guard let end = endDay.date(atMinute: item.endMinute, timeZone: configuration.timeZone), end > start else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    func positiveIntersection(_ lhs: DateInterval, _ rhs: DateInterval) -> DateInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    func intersectingBreakInterval(day: DayKey, break item: BreakSnapshot, configuration: WorkConfigurationSnapshot) -> DateInterval? {
        guard let shift = shiftInterval(day: day, configuration: configuration) else { return nil }
        return breakIntervals(day: day, break: item, configuration: configuration)
            .first(where: { positiveIntersection($0, shift) != nil })
    }

    func breakIntersectsShift(day: DayKey, break item: BreakSnapshot, configuration: WorkConfigurationSnapshot) -> Bool {
        guard let shift = shiftInterval(day: day, configuration: configuration) else { return false }
        return breakIntervals(day: day, break: item, configuration: configuration)
            .contains(where: { positiveIntersection($0, shift) != nil })
    }
}
