import XCTest
import UserNotifications
@testable import ShiftEarnings

@MainActor
final class NotificationSchedulerTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: 9 * 3600)!
    private let day = DayKey(year: 2026, month: 9, day: 24)

    func testRescheduleAfterMidnightKeepsRemainingEventsFromPreviousDayActiveShift() async {
        let center = FakeUserNotificationCenter()
        let scheduler = NotificationScheduler(center: center)
        let nextDay = day.addingDays(1)
        let now = date(nextDay, 1, 50)

        await scheduler.reschedule(context: nightContext(), now: now)

        let previousShiftIDs = center.pendingIdentifiers.filter { $0.contains(".\(day.rawValue).") }
        XCTAssertEqual(previousShiftIDs.count, 3)
        XCTAssertTrue(previousShiftIDs.contains(where: { $0.contains(".night-break.start.5") }))
        XCTAssertTrue(previousShiftIDs.contains(where: { $0.contains(".night-break.end.5") }))
        XCTAssertTrue(previousShiftIDs.contains(where: { $0.contains(".night-break.end.1") }))
    }

    func testLatestRequestWinsWhenEarlierAddIsStillInFlight() async {
        let center = FakeUserNotificationCenter(blockFirstAdd: true)
        let scheduler = NotificationScheduler(center: center)
        let now = date(day, 8, 0)

        let firstTask = Task { @MainActor in
            await scheduler.reschedule(context: daytimeContext(withRule: true), now: now)
        }
        await center.waitUntilFirstAddStarts()

        let secondTask = Task { @MainActor in
            await scheduler.reschedule(context: daytimeContext(withRule: false), now: now)
        }
        await Task.yield()

        center.releaseFirstAdd()
        await firstTask.value
        await secondTask.value

        XCTAssertTrue(center.pendingIdentifiers.isEmpty)
        XCTAssertEqual(scheduler.scheduledCount, 0)
        XCTAssertGreaterThanOrEqual(center.removeAllCallCount, 2)
        XCTAssertGreaterThanOrEqual(center.removeSpecificCallCount, 1)
    }

    private func nightContext() -> EarningsContext {
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
            effectiveFrom: day,
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
        return EarningsContext(
            configurations: [config],
            dayOverrides: [:],
            notificationRules: [nightBreak.stableKey: rule],
            preferences: AppPreferencesSnapshot(
                onboardingCompleted: true,
                workStartDay: day,
                notificationsEnabled: true,
                counterMode: .regular
            )
        )
    }

    private func daytimeContext(withRule: Bool) -> EarningsContext {
        let breakItem = BreakSnapshot(
            id: UUID(),
            stableKey: "race-break",
            name: "Перерыв",
            startMinute: 10 * 60,
            endMinute: 10 * 60 + 20,
            isPaid: true,
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
            breaks: [breakItem]
        )
        let rules: [String: NotificationRuleSnapshot]
        if withRule {
            rules = [
                breakItem.stableKey: NotificationRuleSnapshot(
                    breakKey: breakItem.stableKey,
                    beforeStartOffsets: [5],
                    beforeEndOffsets: [],
                    customStartOffsets: [],
                    customEndOffsets: []
                )
            ]
        } else {
            rules = [:]
        }
        return EarningsContext(
            configurations: [config],
            dayOverrides: [:],
            notificationRules: rules,
            preferences: AppPreferencesSnapshot(
                onboardingCompleted: true,
                workStartDay: day,
                notificationsEnabled: true,
                counterMode: .regular
            )
        )
    }

    private func date(_ day: DayKey, _ hour: Int, _ minute: Int) -> Date {
        day.date(atMinute: hour * 60 + minute, timeZone: zone)!
    }
}

@MainActor
private final class FakeUserNotificationCenter: UserNotificationCenterClient {
    private(set) var pending: [String: UNNotificationRequest] = [:]
    private(set) var removeAllCallCount = 0
    private(set) var removeSpecificCallCount = 0
    private var addCallCount = 0
    private let blockFirstAdd: Bool
    private var firstAddWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockedAddContinuation: CheckedContinuation<Void, Never>?

    init(blockFirstAdd: Bool = false) {
        self.blockFirstAdd = blockFirstAdd
    }

    var pendingIdentifiers: Set<String> {
        Set(pending.keys)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func removeAllPendingNotificationRequests() {
        removeAllCallCount += 1
        pending.removeAll()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removeSpecificCallCount += 1
        for identifier in identifiers {
            pending.removeValue(forKey: identifier)
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        addCallCount += 1
        if addCallCount == 1 {
            let waiters = firstAddWaiters
            firstAddWaiters.removeAll()
            for waiter in waiters { waiter.resume() }

            if blockFirstAdd {
                await withCheckedContinuation { continuation in
                    blockedAddContinuation = continuation
                }
            }
        }
        pending[request.identifier] = request
    }

    func waitUntilFirstAddStarts() async {
        if addCallCount > 0 { return }
        await withCheckedContinuation { continuation in
            firstAddWaiters.append(continuation)
        }
    }

    func releaseFirstAdd() {
        blockedAddContinuation?.resume()
        blockedAddContinuation = nil
    }
}
