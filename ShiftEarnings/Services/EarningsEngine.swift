import Foundation

struct EarningsEngine {
    private let schedule = WorkScheduleService()

    func activeConfiguration(at now: Date, configurations: [WorkConfigurationSnapshot]) -> WorkConfigurationSnapshot? {
        let eligible = configurations
            .filter { configuration in
                let localDay = DayKey(date: now, timeZone: configuration.timeZone)
                return configuration.effectiveFrom <= localDay
            }
        return eligible.max(by: { $0.effectiveFrom < $1.effectiveFrom })
            ?? configurations.min(by: { $0.effectiveFrom < $1.effectiveFrom })
    }

    func configuration(for day: DayKey, configurations: [WorkConfigurationSnapshot]) -> WorkConfigurationSnapshot? {
        configurations
            .filter { $0.effectiveFrom <= day }
            .max(by: { $0.effectiveFrom < $1.effectiveFrom })
    }

    func dayResult(day: DayKey, asOf now: Date, context: EarningsContext) -> DayEarnings {
        guard let workStart = context.preferences.workStartDay else {
            return .zero(day: day, state: .notConfigured)
        }
        guard day >= workStart else {
            return .zero(day: day, state: .beforeWorkStart)
        }
        guard let configuration = configuration(for: day, configurations: context.configurations),
              let shift = schedule.shiftInterval(day: day, configuration: configuration) else {
            return .zero(day: day, state: .notConfigured)
        }

        let dayOverride = context.dayOverrides[day]
        let isDayOff = dayOverride?.isDayOff ?? false
        let overtimeMinutes = max(0, dayOverride?.overtimeMinutes ?? 0)
        let overtimeMultiplier = dayOverride?.overtimeMultiplier ?? 1
        let overtime = MoneyMath.earnings(
            hourlyRate: configuration.hourlyRate,
            paidMilliseconds: Int64(overtimeMinutes) * 60_000,
            multiplier: overtimeMultiplier
        )

        let elapsedEnd = min(max(now, shift.start), shift.end)
        var paidMilliseconds: Int64 = 0
        var baseEarnings: Decimal = 0

        if !isDayOff && elapsedEnd > shift.start {
            let elapsed = DateInterval(start: shift.start, end: elapsedEnd)
            var unpaidOverlaps: [DateInterval] = []

            for breakItem in configuration.breaks where !breakItem.isPaid {
                for breakInterval in schedule.breakIntervals(day: day, break: breakItem, configuration: configuration) {
                    if let overlap = schedule.positiveIntersection(elapsed, breakInterval) {
                        unpaidOverlaps.append(overlap)
                    }
                }
            }

            let unpaidMilliseconds = mergedDurationMilliseconds(unpaidOverlaps)
            paidMilliseconds = max(0, milliseconds(elapsed.duration) - unpaidMilliseconds)
            baseEarnings = MoneyMath.earnings(hourlyRate: configuration.hourlyRate, paidMilliseconds: paidMilliseconds)
        }

        let activeBreak = activeBreak(
            day: day,
            now: now,
            shift: shift,
            configuration: configuration,
            isDayOff: isDayOff
        )
        let state = shiftState(
            now: now,
            shift: shift,
            isDayOff: isDayOff,
            activeBreak: activeBreak
        )
        let progress: Double
        if now <= shift.start {
            progress = 0
        } else if now >= shift.end {
            progress = 1
        } else {
            progress = min(1, max(0, now.timeIntervalSince(shift.start) / shift.duration))
        }

        return DayEarnings(
            day: day,
            baseEarnings: baseEarnings,
            overtimeEarnings: overtime,
            paidMilliseconds: paidMilliseconds,
            state: state,
            shiftStart: shift.start,
            shiftEnd: shift.end,
            activeBreak: activeBreak,
            progress: progress,
            secondsRemaining: max(0, shift.end.timeIntervalSince(now))
        )
    }

    func aggregate(from start: DayKey, through end: DayKey, asOf now: Date, context: EarningsContext) -> Decimal {
        guard start <= end else { return 0 }
        var total: Decimal = 0
        var day = start
        while day <= end {
            total += dayResult(day: day, asOf: now, context: context).totalEarnings
            day = day.addingDays(1)
        }
        return total
    }

    func currentDay(at now: Date, context: EarningsContext) -> DayKey? {
        guard let configuration = activeConfiguration(at: now, configurations: context.configurations) else { return nil }
        return DayKey(date: now, timeZone: configuration.timeZone)
    }

    func activeShiftDay(at now: Date, context: EarningsContext) -> DayKey? {
        var candidates = Set<DayKey>()
        for configuration in context.configurations {
            let localDay = DayKey(date: now, timeZone: configuration.timeZone)
            candidates.insert(localDay)
            candidates.insert(localDay.addingDays(-1))
        }

        let workStart = context.preferences.workStartDay
        return candidates.compactMap { day -> (day: DayKey, start: Date)? in
            if let workStart, day < workStart { return nil }
            if context.dayOverrides[day]?.isDayOff == true { return nil }
            guard let configuration = configuration(for: day, configurations: context.configurations),
                  let shift = schedule.shiftInterval(day: day, configuration: configuration),
                  now >= shift.start, now < shift.end else { return nil }
            return (day, shift.start)
        }
        .max(by: { $0.start < $1.start })?
        .day
    }

    func liveDay(at now: Date, context: EarningsContext) -> DayKey? {
        activeShiftDay(at: now, context: context) ?? currentDay(at: now, context: context)
    }

    private func activeBreak(
        day: DayKey,
        now: Date,
        shift: DateInterval,
        configuration: WorkConfigurationSnapshot,
        isDayOff: Bool
    ) -> ActiveBreak? {
        guard !isDayOff, now >= shift.start, now < shift.end else { return nil }
        let orderedBreaks = configuration.breaks.sorted(by: { $0.sortOrder < $1.sortOrder })

        for breakItem in orderedBreaks where !breakItem.isPaid {
            for interval in schedule.breakIntervals(day: day, break: breakItem, configuration: configuration) {
                if now >= interval.start, now < interval.end, schedule.positiveIntersection(interval, shift) != nil {
                    return ActiveBreak(name: breakItem.name, isPaid: false, start: interval.start, end: interval.end)
                }
            }
        }
        for breakItem in orderedBreaks where breakItem.isPaid {
            for interval in schedule.breakIntervals(day: day, break: breakItem, configuration: configuration) {
                if now >= interval.start, now < interval.end, schedule.positiveIntersection(interval, shift) != nil {
                    return ActiveBreak(name: breakItem.name, isPaid: true, start: interval.start, end: interval.end)
                }
            }
        }
        return nil
    }

    private func shiftState(
        now: Date,
        shift: DateInterval,
        isDayOff: Bool,
        activeBreak: ActiveBreak?
    ) -> ShiftState {
        if isDayOff { return .dayOff }
        if now < shift.start { return .beforeShift }
        if now >= shift.end { return .completed }
        if let activeBreak {
            return activeBreak.isPaid ? .paidBreak(activeBreak.name) : .unpaidBreak(activeBreak.name)
        }
        return .working
    }

    private func mergedDurationMilliseconds(_ intervals: [DateInterval]) -> Int64 {
        let sorted = intervals.sorted(by: { $0.start < $1.start })
        guard var current = sorted.first else { return 0 }
        var total: Int64 = 0

        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += milliseconds(current.duration)
                current = interval
            }
        }
        total += milliseconds(current.duration)
        return total
    }

    private func milliseconds(_ interval: TimeInterval) -> Int64 {
        Int64((max(0, interval) * 1_000).rounded(.down))
    }
}
