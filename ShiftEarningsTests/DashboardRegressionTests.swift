import XCTest
import SwiftData
@testable import ShiftEarnings

final class DashboardRegressionTests: XCTestCase {
    @MainActor
    func testDashboardUsesContinuingPreviousDayNightShiftForLiveSnapshotAndAggregates() async throws {
        let zone = TimeZone(secondsFromGMT: 9 * 3600)!
        let shiftDay = DayKey(year: 2026, month: 9, day: 24)
        let nextDay = shiftDay.addingDays(1)
        let now = nextDay.date(atMinute: 2 * 60, timeZone: zone)!

        let container = try PersistenceController.makeContainer(inMemory: true)
        let repository = AppRepository(context: container.mainContext)
        try repository.completeOnboarding(
            hourlyRate: 600,
            shiftStartMinute: 20 * 60,
            shiftDurationMinutes: 12 * 60,
            workStartDay: shiftDay,
            timeZoneOffsetSeconds: 9 * 3600
        )
        try repository.saveWorkConfiguration(
            effectiveFrom: shiftDay,
            hourlyRate: 600,
            shiftStartMinute: 20 * 60,
            shiftDurationMinutes: 12 * 60,
            timeZoneOffsetSeconds: 9 * 3600,
            breaks: []
        )

        let viewModel = DashboardViewModel(repository: repository, engine: EarningsEngine())
        viewModel.reload(now: now)
        let snapshot = try XCTUnwrap(viewModel.snapshot(at: now))

        XCTAssertEqual(viewModel.today, shiftDay)
        XCTAssertEqual(snapshot.day.day, shiftDay)
        XCTAssertEqual(snapshot.day.state, .working)
        XCTAssertEqual(snapshot.day.baseEarnings.rounded(), Decimal(3600))
        XCTAssertEqual(snapshot.monthEarnings.rounded(), Decimal(3600))
        XCTAssertEqual(snapshot.allTimeEarnings.rounded(), Decimal(3600))
    }
}
