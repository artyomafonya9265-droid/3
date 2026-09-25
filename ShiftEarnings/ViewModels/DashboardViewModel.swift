import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var context: EarningsContext
    @Published private(set) var monthBeforeToday: Decimal = 0
    @Published private(set) var allTimeBeforeToday: Decimal = 0
    @Published private(set) var today: DayKey?
    @Published private(set) var isLoadingHistory = true

    private let repository: AppRepository
    private let engine: EarningsEngine
    private var reloadTask: Task<Void, Never>?

    init(repository: AppRepository, engine: EarningsEngine) {
        self.repository = repository
        self.engine = engine
        self.context = repository.earningsContext()
        self.today = engine.liveDay(at: Date(), context: context)
    }

    deinit {
        reloadTask?.cancel()
    }

    func reload(now: Date = Date()) {
        reloadTask?.cancel()
        let newContext = repository.earningsContext()
        context = newContext
        guard let today = engine.liveDay(at: now, context: newContext),
              let workStart = newContext.preferences.workStartDay else {
            self.today = nil
            monthBeforeToday = 0
            allTimeBeforeToday = 0
            isLoadingHistory = false
            return
        }
        self.today = today
        let yesterday = today.addingDays(-1)
        let monthStart = today.startOfMonth
        isLoadingHistory = true

        reloadTask = Task { [engine] in
            let totals = await Task.detached(priority: .userInitiated) {
                let monthStartEffective = max(monthStart, workStart)
                let month = monthStartEffective <= yesterday
                    ? engine.aggregate(from: monthStartEffective, through: yesterday, asOf: now, context: newContext)
                    : Decimal.zero
                let all = workStart <= yesterday
                    ? engine.aggregate(from: workStart, through: yesterday, asOf: now, context: newContext)
                    : Decimal.zero
                return (month, all)
            }.value
            guard !Task.isCancelled else { return }
            self.monthBeforeToday = totals.0
            self.allTimeBeforeToday = totals.1
            self.isLoadingHistory = false
        }
    }

    func snapshot(at now: Date) -> DashboardSnapshot? {
        guard let currentDay = today else { return nil }
        let dayResult = engine.dayResult(day: currentDay, asOf: now, context: context)
        return DashboardSnapshot(
            day: dayResult,
            monthEarnings: monthBeforeToday + dayResult.totalEarnings,
            allTimeEarnings: allTimeBeforeToday + dayResult.totalEarnings
        )
    }
}
