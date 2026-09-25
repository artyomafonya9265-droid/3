import XCTest
@testable import ShiftEarnings

final class NotificationPlanBuilderTests: XCTestCase {
    private let builder = NotificationPlanBuilder()
    private let zone = TimeZone(secondsFromGMT: 9 * 3600)!
    private let today = DayKey(year: 2026, month: 9, day: 24)

    func testDisabledMasterSwitchProducesNoNotifications() {
        var ctx = context()
        ctx.preferences.notificationsEnabled = false
        XCTAssertTrue(builder.buildPlan(context: ctx, now: date(today, 8, 0)).isEmpty)
    }

    func testReenablePreservesSelectedOffsets() {
        var ctx = context()
        ctx.preferences.notificationsEnabled = false
        let off = builder.buildPlan(context: ctx, now: date(today, 8, 0))
        ctx.preferences.notificationsEnabled = true
        let on = builder.buildPlan(context: ctx, now: date(today, 8, 0), horizonDays: 1, maxCount: 56)
        XCTAssertTrue(off.isEmpty)
        XCTAssertEqual(on.count, 4)
        XCTAssertEqual(ctx.notificationRules["smoke-1"]?.beforeStartOffsets, Set([15, 5]))
    }

    func testMultipleStartAndEndIntervalsAreAllPlanned() {
        let plan = builder.buildPlan(context: context(), now: date(today, 8, 0), horizonDays: 1, maxCount: 56)
        XCTAssertEqual(plan.count, 4)
        let bodies = plan.map(\.body)
        XCTAssertTrue(bodies.contains(where: { $0.contains("15 минут") }))
        XCTAssertTrue(bodies.contains(where: { $0.contains("5 минут") }))
        XCTAssertTrue(bodies.contains(where: { $0.contains("1 минуту") }))
    }

    func testCustomIntervalIsPlanned() {
        var ctx = context()
        ctx.notificationRules["smoke-1"]?.customStartOffsets.insert(7)
        let plan = builder.buildPlan(context: ctx, now: date(today, 8, 0), horizonDays: 1, maxCount: 56)
        XCTAssertTrue(plan.contains(where: { $0.body.contains("7 минут") }))
    }

    func testResetRulesProducesNoPlan() {
        var ctx = context()
        ctx.notificationRules["smoke-1"] = .empty(for: "smoke-1")
        let plan = builder.buildPlan(context: ctx, now: date(today, 8, 0), horizonDays: 1, maxCount: 56)
        XCTAssertTrue(plan.isEmpty)
    }

    func testDayOffHasNoBreakNotificationsForThatDate() {
        var ctx = context()
        ctx.dayOverrides[today] = DayOverrideSnapshot(day: today, isDayOff: true, overtimeMinutes: 120, overtimeMultiplier: 1)
        let plan = builder.buildPlan(context: ctx, now: date(today, 8, 0), horizonDays: 2, maxCount: 56)
        XCTAssertFalse(plan.contains(where: { $0.id.contains(".\(today.rawValue).") }))
        XCTAssertTrue(plan.contains(where: { $0.id.contains(".\(today.addingDays(1).rawValue).") }))
    }

    func testNoDuplicateIdentifiers() {
        let plan = builder.buildPlan(context: context(), now: date(today, 8, 0), horizonDays: 10, maxCount: 56)
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
    }

    func testChangedBreakTimeRecreatesDifferentFireDates() {
        let original = builder.buildPlan(context: context(), now: date(today, 8, 0), horizonDays: 1, maxCount: 56)
        var changed = context()
        changed.configurations[0].breaks[0].startMinute = 11 * 60
        changed.configurations[0].breaks[0].endMinute = 11 * 60 + 20
        let updated = builder.buildPlan(context: changed, now: date(today, 8, 0), horizonDays: 1, maxCount: 56)
        XCTAssertNotEqual(original.map(\.fireDate), updated.map(\.fireDate))
    }

    func testLunchStartAndEndCanBePlannedIndependently() {
        var ctx = baseContext()
        ctx.notificationRules["lunch"] = NotificationRuleSnapshot(
            breakKey: "lunch",
            beforeStartOffsets: [15, 5],
            beforeEndOffsets: [10, 5, 1],
            customStartOffsets: [],
            customEndOffsets: []
        )
        let plan = builder.buildPlan(context: ctx, now: date(today, 8, 0), horizonDays: 1, maxCount: 56)
        XCTAssertEqual(plan.count, 5)
        XCTAssertTrue(plan.contains(where: { $0.body == "До обеда 15 минут" }))
        XCTAssertTrue(plan.contains(where: { $0.body == "Обед закончится через 1 минуту" }))
    }

    func testNoNotificationsBeforeConfiguredWorkStartDate() {
        var ctx = context()
        ctx.preferences.workStartDay = today.addingDays(1)
        let plan = builder.buildPlan(context: ctx, now: date(today, 8, 0), horizonDays: 2, maxCount: 56)
        XCTAssertFalse(plan.contains(where: { $0.id.contains(".\(today.rawValue).") }))
        XCTAssertTrue(plan.contains(where: { $0.id.contains(".\(today.addingDays(1).rawValue).") }))
    }

    func testPlanRespectsMaximumPendingWindow() {
        var ctx = baseContext()
        for key in ["smoke-1", "lunch", "smoke-2"] {
            ctx.notificationRules[key] = NotificationRuleSnapshot(
                breakKey: key,
                beforeStartOffsets: [30, 20, 15, 10, 5, 1, 0],
                beforeEndOffsets: [30, 20, 15, 10, 5, 1, 0],
                customStartOffsets: [7],
                customEndOffsets: [7]
            )
        }
        let plan = builder.buildPlan(context: ctx, now: date(today, 8, 0), horizonDays: 21, maxCount: 56)
        XCTAssertEqual(plan.count, 56)
        XCTAssertEqual(plan, plan.sorted(by: { $0.fireDate < $1.fireDate }))
    }

    func testAfterMidnightKeepsFutureNotificationsFromPreviousDayActiveShift() {
        let previousDay = today
        let nextDay = previousDay.addingDays(1)
        let nightBreak = BreakSnapshot(
            id: UUID(),
            stableKey: "night-break",
            name: "Ночной перерыв",
            startMinute: 2 * 60,
            endMinute: 2 * 60 + 20,
            isPaid: true,
            type: .custom,
            sortOrder: 0
        )
        let config = WorkConfigurationSnapshot(
            id: UUID(),
            effectiveFrom: previousDay,
            hourlyRate: 600,
            shiftStartMinute: 20 * 60,
            shiftDurationMinutes: 12 * 60,
            timeZoneOffsetSeconds: 9 * 3600,
            breaks: [nightBreak]
        )
        let rule = NotificationRuleSnapshot(
            breakKey: nightBreak.stableKey,
            beforeStartOffsets: [15, 5],
            beforeEndOffsets: [5, 1],
            customStartOffsets: [],
            customEndOffsets: []
        )
        let ctx = EarningsContext(
            configurations: [config],
            dayOverrides: [:],
            notificationRules: [nightBreak.stableKey: rule],
            preferences: AppPreferencesSnapshot(
                onboardingCompleted: true,
                workStartDay: previousDay,
                notificationsEnabled: true,
                counterMode: .regular
            )
        )

        let now = date(nextDay, 1, 50)
        let plan = builder.buildPlan(context: ctx, now: now, horizonDays: 1, maxCount: 56)
        let previousShiftItems = plan.filter { $0.id.contains(".\(previousDay.rawValue).") }

        XCTAssertEqual(previousShiftItems.count, 3)
        XCTAssertTrue(previousShiftItems.contains(where: { $0.fireDate == date(nextDay, 1, 55) }))
        XCTAssertTrue(previousShiftItems.contains(where: { $0.fireDate == date(nextDay, 2, 15) }))
        XCTAssertTrue(previousShiftItems.contains(where: { $0.fireDate == date(nextDay, 2, 19) }))
    }

    func testBreakThatOnlyTouchesShiftBoundaryCreatesNoNotifications() {
        let touchingStart = BreakSnapshot(
            id: UUID(),
            stableKey: "touching-start",
            name: "Граница начала",
            startMinute: 7 * 60 + 40,
            endMinute: 8 * 60,
            isPaid: true,
            type: .custom,
            sortOrder: 0
        )
        let touchingEnd = BreakSnapshot(
            id: UUID(),
            stableKey: "touching-end",
            name: "Граница конца",
            startMinute: 20 * 60,
            endMinute: 20 * 60 + 20,
            isPaid: true,
            type: .custom,
            sortOrder: 1
        )
        let config = WorkConfigurationSnapshot(
            id: UUID(),
            effectiveFrom: today,
            hourlyRate: 600,
            shiftStartMinute: 8 * 60,
            shiftDurationMinutes: 12 * 60,
            timeZoneOffsetSeconds: 9 * 3600,
            breaks: [touchingStart, touchingEnd]
        )
        let ctx = EarningsContext(
            configurations: [config],
            dayOverrides: [:],
            notificationRules: [
                touchingStart.stableKey: NotificationRuleSnapshot(
                    breakKey: touchingStart.stableKey,
                    beforeStartOffsets: [15, 5],
                    beforeEndOffsets: [5, 1],
                    customStartOffsets: [],
                    customEndOffsets: []
                ),
                touchingEnd.stableKey: NotificationRuleSnapshot(
                    breakKey: touchingEnd.stableKey,
                    beforeStartOffsets: [15, 5],
                    beforeEndOffsets: [5, 1],
                    customStartOffsets: [],
                    customEndOffsets: []
                )
            ],
            preferences: AppPreferencesSnapshot(
                onboardingCompleted: true,
                workStartDay: today,
                notificationsEnabled: true,
                counterMode: .regular
            )
        )

        let plan = builder.buildPlan(context: ctx, now: date(today, 7, 0), horizonDays: 1, maxCount: 56)
        XCTAssertTrue(plan.isEmpty)
    }

    private func context() -> EarningsContext {
        var ctx = baseContext()
        ctx.notificationRules["smoke-1"] = NotificationRuleSnapshot(
            breakKey: "smoke-1",
            beforeStartOffsets: [15, 5],
            beforeEndOffsets: [5, 1],
            customStartOffsets: [],
            customEndOffsets: []
        )
        return ctx
    }

    private func baseContext() -> EarningsContext {
        let config = WorkConfigurationSnapshot(
            id: UUID(), effectiveFrom: DayKey(year: 2026, month: 9, day: 1), hourlyRate: 600,
            shiftStartMinute: 8 * 60, shiftDurationMinutes: 12 * 60,
            timeZoneOffsetSeconds: 9 * 3600, breaks: BreakSnapshot.defaults
        )
        return EarningsContext(
            configurations: [config], dayOverrides: [:], notificationRules: [:],
            preferences: AppPreferencesSnapshot(
                onboardingCompleted: true,
                workStartDay: DayKey(year: 2026, month: 9, day: 1),
                notificationsEnabled: true,
                counterMode: .regular
            )
        )
    }

    private func date(_ day: DayKey, _ hour: Int, _ minute: Int) -> Date {
        day.date(atMinute: hour * 60 + minute, timeZone: zone)!
    }
}
