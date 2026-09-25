import Foundation
import SwiftData
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let modelContainer: ModelContainer
    let repository: AppRepository
    let earningsEngine: EarningsEngine
    let notificationScheduler: NotificationScheduler
    let timeVerificationService: TimeVerificationService
    let persistenceWarning: String?

    @Published private(set) var refreshToken: Int = 0

    init(modelContainer: ModelContainer, persistenceWarning: String? = nil) {
        self.modelContainer = modelContainer
        self.repository = AppRepository(context: modelContainer.mainContext)
        self.earningsEngine = EarningsEngine()
        self.notificationScheduler = NotificationScheduler()
        self.timeVerificationService = TimeVerificationService()
        self.persistenceWarning = persistenceWarning
    }

    func refreshEnvironment() {
        refreshToken &+= 1
        let context = repository.earningsContext()
        Task { await notificationScheduler.reschedule(context: context) }
    }

    func rescheduleNotifications() {
        let context = repository.earningsContext()
        Task { await notificationScheduler.reschedule(context: context) }
    }
}

@MainActor
final class AppBootstrap: ObservableObject {
    enum State {
        case ready(AppContainer)
        case failed(String)
    }

    let state: State

    init() {
        do {
            let container = try PersistenceController.makeContainer()
            state = .ready(AppContainer(modelContainer: container))
        } catch {
            do {
                let memoryContainer = try PersistenceController.makeContainer(inMemory: true)
                state = .ready(AppContainer(
                    modelContainer: memoryContainer,
                    persistenceWarning: "Постоянное хранилище недоступно: \(error.localizedDescription). Приложение работает во временном режиме; изменения этой сессии не сохранятся после закрытия."
                ))
            } catch {
                state = .failed("Не удалось открыть локальное хранилище данных: \(error.localizedDescription)")
            }
        }
    }
}
