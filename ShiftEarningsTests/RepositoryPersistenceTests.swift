import XCTest
import SwiftData
@testable import ShiftEarnings

final class RepositoryPersistenceTests: XCTestCase {
    @MainActor
    private func makeRepository() throws -> (ModelContainer, AppRepository) {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let repository = AppRepository(context: container.mainContext)
        try repository.completeOnboarding(
            hourlyRate: 600,
            shiftStartMinute: 8 * 60,
            shiftDurationMinutes: 12 * 60,
            workStartDay: DayKey(year: 2026, month: 9, day: 1),
            timeZoneOffsetSeconds: 9 * 3600
        )
        return (container, repository)
    }

    @MainActor
    func testMasterToggleOffAndOnPreservesIntervals() throws {
        let (container, repository) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        let original = NotificationRuleSnapshot(
            breakKey: "smoke-1",
            beforeStartOffsets: [15, 5],
            beforeEndOffsets: [5, 1],
            customStartOffsets: [7],
            customEndOffsets: [3]
        )
        try repository.saveNotificationRule(original)
        try repository.setNotificationsEnabled(true)
        XCTAssertTrue(repository.preferences.notificationsEnabled)

        try repository.setNotificationsEnabled(false)
        XCTAssertFalse(repository.preferences.notificationsEnabled)
        XCTAssertEqual(repository.notificationRule(for: "smoke-1"), original)

        try repository.setNotificationsEnabled(true)
        XCTAssertTrue(repository.preferences.notificationsEnabled)
        XCTAssertEqual(repository.notificationRule(for: "smoke-1"), original)
    }

    @MainActor
    func testRulesSurviveRepositoryRecreation() throws {
        let (container, repository) = try makeRepository()
        let original = NotificationRuleSnapshot(
            breakKey: "lunch",
            beforeStartOffsets: [15, 5],
            beforeEndOffsets: [10, 5, 1],
            customStartOffsets: [7],
            customEndOffsets: [2]
        )
        try repository.saveNotificationRule(original)
        try repository.setNotificationsEnabled(true)

        let reopened = AppRepository(context: container.mainContext)
        XCTAssertTrue(reopened.preferences.notificationsEnabled)
        XCTAssertEqual(reopened.notificationRule(for: "lunch"), original)
    }

    @MainActor
    func testResetClearsAllIntervalsButKeepsWorkConfiguration() throws {
        let (container, repository) = try makeRepository()
        defer { withExtendedLifetime(container) {} }
        for key in ["smoke-1", "lunch", "smoke-2"] {
            try repository.saveNotificationRule(NotificationRuleSnapshot(
                breakKey: key,
                beforeStartOffsets: [15, 5],
                beforeEndOffsets: [5, 1],
                customStartOffsets: [7],
                customEndOffsets: [3]
            ))
        }
        let before = repository.currentConfiguration()
        try repository.resetNotificationRules()

        for key in ["smoke-1", "lunch", "smoke-2"] {
            let rule = repository.notificationRule(for: key)
            XCTAssertTrue(rule.beforeStartOffsets.isEmpty)
            XCTAssertTrue(rule.beforeEndOffsets.isEmpty)
            XCTAssertTrue(rule.customStartOffsets.isEmpty)
            XCTAssertTrue(rule.customEndOffsets.isEmpty)
        }

        let after = repository.currentConfiguration()
        XCTAssertEqual(before?.hourlyRate, after?.hourlyRate)
        XCTAssertEqual(before?.shiftStartMinute, after?.shiftStartMinute)
        XCTAssertEqual(before?.shiftDurationMinutes, after?.shiftDurationMinutes)
        XCTAssertEqual(before?.breaks.map(\.stableKey), after?.breaks.map(\.stableKey))
        XCTAssertEqual(before?.breaks.map(\.startMinute), after?.breaks.map(\.startMinute))
        XCTAssertEqual(before?.breaks.map(\.endMinute), after?.breaks.map(\.endMinute))
    }

    @MainActor
    func testDayOverridePersistsWithoutAffectingOtherDays() throws {
        let (container, repository) = try makeRepository()
        let day = DayKey(year: 2026, month: 9, day: 12)
        let other = day.addingDays(1)
        try repository.setDayOff(true, for: day)
        try repository.setOvertime(minutes: 150, for: day)

        let reopened = AppRepository(context: container.mainContext)
        XCTAssertTrue(reopened.dayOverride(for: day).isDayOff)
        XCTAssertEqual(reopened.dayOverride(for: day).overtimeMinutes, 150)
        XCTAssertFalse(reopened.dayOverride(for: other).isDayOff)
        XCTAssertEqual(reopened.dayOverride(for: other).overtimeMinutes, 0)
    }


    @MainActor
    func testDiskBackedStoreRestoresCompleteRepositoryStateAfterFreshContainer() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ShiftEarningsPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("ShiftEarnings.store")

        let workStart = DayKey(year: 2026, month: 9, day: 1)
        let secondEffectiveDate = DayKey(year: 2026, month: 10, day: 1)
        let overrideDay = DayKey(year: 2026, month: 9, day: 12)
        let expectedRule = NotificationRuleSnapshot(
            breakKey: "lunch",
            beforeStartOffsets: [15, 5],
            beforeEndOffsets: [10, 5, 1],
            customStartOffsets: [7],
            customEndOffsets: [2]
        )

        do {
            let firstContainer = try PersistenceController.makeContainer(storeURL: storeURL)
            let repository = AppRepository(context: firstContainer.mainContext)
            try repository.completeOnboarding(
                hourlyRate: Decimal(string: "725.50")!,
                shiftStartMinute: 8 * 60,
                shiftDurationMinutes: 12 * 60,
                workStartDay: workStart,
                timeZoneOffsetSeconds: 9 * 3600
            )
            try repository.saveWorkConfiguration(
                effectiveFrom: secondEffectiveDate,
                hourlyRate: 800,
                shiftStartMinute: 9 * 60,
                shiftDurationMinutes: 10 * 60,
                timeZoneOffsetSeconds: 9 * 3600,
                breaks: BreakSnapshot.defaults
            )
            try repository.setDayOff(true, for: overrideDay)
            try repository.setOvertime(minutes: 150, for: overrideDay)
            try repository.saveNotificationRule(expectedRule)
            try repository.setNotificationsEnabled(true)
        }

        let reopenedContainer = try PersistenceController.makeContainer(storeURL: storeURL)
        let reopened = AppRepository(context: reopenedContainer.mainContext)
        let restoredContext = reopened.earningsContext()

        XCTAssertEqual(restoredContext.preferences.workStartDay, workStart)
        XCTAssertTrue(restoredContext.preferences.notificationsEnabled)
        XCTAssertEqual(restoredContext.configurations.count, 2)
        XCTAssertEqual(restoredContext.configurations[0].effectiveFrom, workStart)
        XCTAssertEqual(restoredContext.configurations[0].hourlyRate, Decimal(string: "725.50")!)
        XCTAssertEqual(restoredContext.configurations[1].effectiveFrom, secondEffectiveDate)
        XCTAssertEqual(restoredContext.configurations[1].hourlyRate, Decimal(800))
        XCTAssertEqual(restoredContext.configurations[1].shiftStartMinute, 9 * 60)
        XCTAssertEqual(restoredContext.configurations[1].shiftDurationMinutes, 10 * 60)

        let restoredOverride = try XCTUnwrap(restoredContext.dayOverrides[overrideDay])
        XCTAssertTrue(restoredOverride.isDayOff)
        XCTAssertEqual(restoredOverride.overtimeMinutes, 150)
        XCTAssertEqual(restoredContext.notificationRules["lunch"], expectedRule)
        XCTAssertEqual(reopened.notificationRule(for: "lunch"), expectedRule)
    }
}
