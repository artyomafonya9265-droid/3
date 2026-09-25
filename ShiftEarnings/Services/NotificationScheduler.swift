import Foundation
import UserNotifications
import Combine

@MainActor
protocol UserNotificationCenterClient: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func removeAllPendingNotificationRequests()
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: UserNotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

@MainActor
final class NotificationScheduler: ObservableObject {
    enum AuthorizationState: Equatable {
        case notDetermined
        case authorized
        case denied
        case provisional
        case ephemeral
        case unknown
    }

    private struct SchedulingRequest {
        var generation: UInt64
        var context: EarningsContext
        var now: Date
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var scheduledCount: Int = 0

    private let center: UserNotificationCenterClient
    private let builder = NotificationPlanBuilder()
    private let maxPendingRequests = 56

    private var generation: UInt64 = 0
    private var latestRequest: SchedulingRequest?
    private var workerTask: Task<Void, Never>?

    init(center: UserNotificationCenterClient = UNUserNotificationCenter.current()) {
        self.center = center
    }

    deinit {
        workerTask?.cancel()
    }

    func refreshAuthorization() async {
        authorizationState = map(await center.authorizationStatus())
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorization()
        if authorizationState == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                await refreshAuthorization()
                return false
            }
            await refreshAuthorization()
        }
        return isAuthorized
    }

    func reschedule(context: EarningsContext, now: Date = Date()) async {
        generation &+= 1
        latestRequest = SchedulingRequest(generation: generation, context: context, now: now)

        if workerTask == nil {
            workerTask = Task { [weak self] in
                await self?.runSchedulingLoop()
            }
        }

        let task = workerTask
        await task?.value
    }

    func disableImmediately() {
        generation &+= 1
        latestRequest = nil
        center.removeAllPendingNotificationRequests()
        scheduledCount = 0
    }

    private var isAuthorized: Bool {
        authorizationState == .authorized || authorizationState == .provisional || authorizationState == .ephemeral
    }

    private func runSchedulingLoop() async {
        while !Task.isCancelled, let request = latestRequest {
            latestRequest = nil
            await apply(request)
        }
        workerTask = nil
    }

    private func apply(_ schedulingRequest: SchedulingRequest) async {
        authorizationState = map(await center.authorizationStatus())
        guard isCurrent(schedulingRequest) else { return }

        guard schedulingRequest.context.preferences.notificationsEnabled, isAuthorized else {
            center.removeAllPendingNotificationRequests()
            if isCurrent(schedulingRequest) {
                scheduledCount = 0
            }
            return
        }

        let plan = builder.buildPlan(
            context: schedulingRequest.context,
            now: schedulingRequest.now,
            horizonDays: 21,
            maxCount: maxPendingRequests
        )
        guard isCurrent(schedulingRequest) else { return }

        center.removeAllPendingNotificationRequests()
        var added = 0

        for item in plan {
            guard isCurrent(schedulingRequest), !Task.isCancelled else { return }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = item.timeZone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            components.timeZone = item.timeZone

            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                if !isCurrent(schedulingRequest) {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    return
                }
                continue
            }

            guard isCurrent(schedulingRequest), !Task.isCancelled else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                return
            }
            added += 1
        }

        if isCurrent(schedulingRequest) {
            scheduledCount = added
        }
    }

    private func isCurrent(_ request: SchedulingRequest) -> Bool {
        request.generation == generation
    }

    private func map(_ status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }
}
