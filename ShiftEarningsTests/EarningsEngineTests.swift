import XCTest
@testable import ShiftEarnings

final class EarningsEngineTests: XCTestCase {
    private let engine = EarningsEngine()
    private let zone = TimeZone(secondsFromGMT: 9 * 3600)!
    private let day = DayKey(year: 2026, month: 9, day: 15)

    func testBeforeShiftIsZero() {
        let result = engine.dayResult(day: day, asOf: date(day, 7, 59), context: context())
        XCTAssertEqual(result.totalEarnings.rounded(), Decimal.zero)
    }

    func testOneHourEqualsHourlyRate() {
        let result = engine.dayResult(day: day, asOf: date(day, 9, 0), context: context())
        XCTAssertEqual(result.baseEarnings.rounded(), Decimal(600))
    }

    func testPaidSmokeBreakContinuesAccrual() {
        let atStart = engine.dayResult(day: day, asOf: date(day, 10, 0), context: context())
        let tenMinutesLater = engine.dayResult(day: day, asOf: date(day, 10, 10), context: context())
        XCTAssertEqual((tenMinutesLater.baseEarnings - atStart.baseEarnings).rounded(), Decimal(100))
        XCTAssertEqual(tenMinutesLater.state, .paidBreak("Перекур"))
    }

    func testUnpaidLunchStopsAccrual() {
        let lunchStart = engine.dayResult(day: day, asOf: date(day, 12, 0), context: context())
        let lunchMiddle = engine.dayResult(day: day, asOf: date(day, 12, 30), context: context())
        XCTAssertEqual(lunchStart.baseEarnings.rounded(), lunchMiddle.baseEarnings.rounded())
        XCTAssertEqual(lunchMiddle.baseEarnings.rounded(), Decimal(2400))
        XCTAssertEqual(lunchMiddle.state, .unpaidBreak("Обед"))
    }

    func testAccrualResumesAfterLunch() {
        let result = engine.dayResult(day: day, asOf: date(day, 13, 30), context: context())
        XCTAssertEqual(result.baseEarnings.rounded(), Decimal(2700))
        XCTAssertEqual(result.state, .working)
    }

    func testAfterShiftBaseDoesNotGrow() {
        let atEnd = engine.dayResult(day: day, asOf: date(day, 20, 0), context: context())
        let later = engine.dayResult(day: day, asOf: date(day, 23, 0), context: context())
        XCTAssertEqual(atEnd.baseEarnings.rounded(), Decimal(6600))
        XCTAssertEqual(later.baseEarnings.rounded(), Decimal(6600))
        XCTAssertEqual(later.state, .completed)
    }

    func testDayOffHasNoBaseEarnings() {
        var ctx = context()
        ctx.dayOverrides[day] = DayOverrideSnapshot(day: day, isDayOff: true, overtimeMinutes: 0, overtimeMultiplier: 1)
        let result = engine.dayResult(day: day, asOf: date(day, 23, 0), context: ctx)
        XCTAssertEqual(result.totalEarnings.rounded(), Decimal.zero)
        XCTAssertEqual(result.state, .dayOff)
    }

    func testDayOffWithOvertimeOnlyCountsOvertime() {
        var ctx = context()
        ctx.dayOverrides[day] = DayOverrideSnapshot(day: day, isDayOff: true, overtimeMinutes: 120, overtimeMultiplier: 1)
        let result = engine.dayResult(day: day, asOf: date(day, 23, 0), context: ctx)
        XCTAssertEqual(result.baseEarnings.rounded(), Decimal.zero)
        XCTAssertEqual(result.overtimeEarnings.rounded(), Decimal(1200))
        XCTAssertEqual(result.totalEarnings.rounded(), Decimal(1200))
    }

    func testRegularDayWithOvertimeAddsBoth() {
        var ctx = context()
        ctx.dayOverrides[day] = DayOverrideSnapshot(day: day, isDayOff: false, overtimeMinutes: 120, overtimeMultiplier: 1)
        let result = engine.dayResult(day: day, asOf: date(day, 23, 0), context: ctx)
        XCTAssertEqual(result.baseEarnings.rounded(), Decimal(6600))
        XCTAssertEqual(result.overtimeEarnings.rounded(), Decimal(1200))
        XCTAssertEqual(result.totalEarnings.rounded(), Decimal(7800))
    }

    func testRateChangeDoesNotRecalculatePreviousMonth() {
        var ctx = context()
        ctx.configurations.append(configuration(effective: DayKey(year: 2026, month: 10, day: 1), rate: 1200))
        let september = engine.dayResult(day: DayKey(year: 2026, month: 9, day: 30), asOf: date(DayKey(year: 2026, month: 10, day: 2), 12, 0), context: ctx)
        let october = engine.dayResult(day: DayKey(year: 2026, month: 10, day: 1), asOf: date(DayKey(year: 2026, month: 10, day: 2), 12, 0), context: ctx)
        XCTAssertEqual(september.baseEarnings.rounded(), Decimal(6600))
        XCTAssertEqual(october.baseEarnings.rounded(), Decimal(13200))
    }

    func testMonthSumEqualsSumOfDays() {
        let ctx = context(workStart: DayKey(year: 2026, month: 9, day: 1))
        let through = DayKey(year: 2026, month: 9, day: 15)
        let asOf = date(through, 23, 0)
        let aggregate = engine.aggregate(from: DayKey(year: 2026, month: 9, day: 1), through: through, asOf: asOf, context: ctx)
        var manual: Decimal = 0
        for i in 1...15 {
            manual += engine.dayResult(day: DayKey(year: 2026, month: 9, day: i), asOf: asOf, context: ctx).totalEarnings
        }
        XCTAssertEqual(aggregate.rounded(), manual.rounded())
        XCTAssertEqual(aggregate.rounded(), Decimal(99_000))
    }

    func testAllTimeStartsExactlyOnConfiguredDate() {
        let ctx = context(workStart: day)
        let previous = engine.dayResult(day: day.addingDays(-1), asOf: date(day, 23, 0), context: ctx)
        let first = engine.dayResult(day: day, asOf: date(day, 23, 0), context: ctx)
        XCTAssertEqual(previous.totalEarnings.rounded(), Decimal.zero)
        XCTAssertEqual(first.totalEarnings.rounded(), Decimal(6600))
    }

    func testNightShiftCrossesMidnightAndClipsLunch() {
        let nightBreak = BreakSnapshot(
            id: UUID(), stableKey: "night-lunch", name: "Обед", startMinute: 0, endMinute: 60,
            isPaid: false, type: .lunch, sortOrder: 0
        )
        let config = WorkConfigurationSnapshot(
            id: UUID(), effectiveFrom: day, hourlyRate: 600, shiftStartMinute: 20 * 60,
            shiftDurationMinutes: 12 * 60, timeZoneOffsetSeconds: 9 * 3600, breaks: [nightBreak]
        )
        let ctx = EarningsContext(
            configurations: [config], dayOverrides: [:], notificationRules: [:],
            preferences: AppPreferencesSnapshot(onboardingCompleted: true, workStartDay: day, notificationsEnabled: false, counterMode: .regular)
        )
        let nextDay = day.addingDays(1)
        let result = engine.dayResult(day: day, asOf: date(nextDay, 2, 0), context: ctx)
        XCTAssertEqual(result.baseEarnings.rounded(), Decimal(3000))
        XCTAssertEqual(result.state, .working)
    }

    func testWorkingTimeZoneIsIndependentOfPhoneTimeZone() {
        let ctx = context()
        let absolute = date(day, 12, 30)
        XCTAssertEqual(engine.currentDay(at: absolute, context: ctx), day)
        let result = engine.dayResult(day: day, asOf: absolute, context: ctx)
        XCTAssertEqual(result.state, .unpaidBreak("Обед"))
    }

    func testOverlappingUnpaidBreaksAreNotDoubleSubtracted() {
        let first = BreakSnapshot(id: UUID(), stableKey: "u1", name: "Пауза 1", startMinute: 12 * 60, endMinute: 13 * 60, isPaid: false, type: .custom, sortOrder: 0)
        let second = BreakSnapshot(id: UUID(), stableKey: "u2", name: "Пауза 2", startMinute: 12 * 60 + 30, endMinute: 13 * 60 + 30, isPaid: false, type: .custom, sortOrder: 1)
        let config = WorkConfigurationSnapshot(id: UUID(), effectiveFrom: day, hourlyRate: 600, shiftStartMinute: 8 * 60, shiftDurationMinutes: 12 * 60, timeZoneOffsetSeconds: 9 * 3600, breaks: [first, second])
        let ctx = EarningsContext(configurations: [config], dayOverrides: [:], notificationRules: [:], preferences: AppPreferencesSnapshot(onboardingCompleted: true, workStartDay: day, notificationsEnabled: false, counterMode: .regular))
        let result = engine.dayResult(day: day, asOf: date(day, 14, 0), context: ctx)
        XCTAssertEqual(result.baseEarnings.rounded(), Decimal(2700))
    }

    func testBeforeFutureWorkStartStillHasCurrentDayAndZeroEarnings() {
        let future = day.addingDays(2)
        let config = configuration(effective: future, rate: 600)
        let ctx = EarningsContext(configurations: [config], dayOverrides: [:], notificationRules: [:], preferences: AppPreferencesSnapshot(onboardingCompleted: true, workStartDay: future, notificationsEnabled: false, counterMode: .regular))
        XCTAssertEqual(engine.currentDay(at: date(day, 12, 0), context: ctx), day)
        XCTAssertEqual(engine.dayResult(day: day, asOf: date(day, 12, 0), context: ctx).state, .beforeWorkStart)
    }

    func testKopeckRoundingIsCorrect() {
        let exact = MoneyMath.earnings(hourlyRate: 500, paidMilliseconds: 1000)
        XCTAssertEqual(exact.rounded(scale: 2), Decimal(string: "0.14")!)
    }

    func testLiveDayUsesPreviousCalendarDayWhileNightShiftIsStillActive() {
        let nightConfig = WorkConfigurationSnapshot(
            id: UUID(),
            effectiveFrom: day,
            hourlyRate: 600,
            shiftStartMinute: 20 * 60,
            shiftDurationMinutes: 12 * 60,
            timeZoneOffsetSeconds: 9 * 3600,
            breaks: []
        )
        let ctx = EarningsContext(
            configurations: [nightConfig],
            dayOverrides: [:],
            notificationRules: [:],
            preferences: AppPreferencesSnapshot(
                onboardingCompleted: true,
                workStartDay: day,
                notificationsEnabled: false,
                counterMode: .regular
            )
        )
        let nextDay = day.addingDays(1)
        let now = date(nextDay, 2, 0)

        XCTAssertEqual(engine.currentDay(at: now, context: ctx), nextDay)
        XCTAssertEqual(engine.activeShiftDay(at: now, context: ctx), day)
        XCTAssertEqual(engine.liveDay(at: now, context: ctx), day)

        let liveResult = engine.dayResult(day: engine.liveDay(at: now, context: ctx)!, asOf: now, context: ctx)
        XCTAssertEqual(liveResult.state, .working)
        XCTAssertEqual(liveResult.baseEarnings.rounded(), Decimal(3600))
    }

    func testBoundaryTouchingBreakHasZeroMathematicalIntersection() {
        let touchingBreak = BreakSnapshot(
            id: UUID(),
            stableKey: "touch-end",
            name: "Граница",
            startMinute: 20 * 60,
            endMinute: 20 * 60 + 20,
            isPaid: false,
            type: .custom,
            sortOrder: 0
        )
        let config = WorkConfigurationSnapshot(
            id: UUID(),
            effectiveFrom: day,
            hourlyRate: 600,
            shiftStartMinute: 8 * 60,
            shiftDurationMinutes: 12 * 60,
            timeZoneOffsetSeconds: 9 * 3600,
            breaks: [touchingBreak]
        )
        let service = WorkScheduleService()

        XCTAssertFalse(service.breakIntersectsShift(day: day, break: touchingBreak, configuration: config))
        XCTAssertNil(service.intersectingBreakInterval(day: day, break: touchingBreak, configuration: config))
    }

    private func context(workStart: DayKey? = nil) -> EarningsContext {
        EarningsContext(
            configurations: [configuration(effective: DayKey(year: 2026, month: 9, day: 1), rate: 600)],
            dayOverrides: [:],
            notificationRules: [:],
            preferences: AppPreferencesSnapshot(
                onboardingCompleted: true,
                workStartDay: workStart ?? DayKey(year: 2026, month: 9, day: 1),
                notificationsEnabled: false,
                counterMode: .regular
            )
        )
    }

    private func configuration(effective: DayKey, rate: Decimal) -> WorkConfigurationSnapshot {
        WorkConfigurationSnapshot(
            id: UUID(), effectiveFrom: effective, hourlyRate: rate, shiftStartMinute: 8 * 60,
            shiftDurationMinutes: 12 * 60, timeZoneOffsetSeconds: 9 * 3600, breaks: BreakSnapshot.defaults
        )
    }

    private func date(_ day: DayKey, _ hour: Int, _ minute: Int) -> Date {
        day.date(atMinute: hour * 60 + minute, timeZone: zone)!
    }
}
