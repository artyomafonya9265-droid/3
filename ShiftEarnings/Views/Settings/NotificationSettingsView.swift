import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    let container: AppContainer
    @ObservedObject private var repository: AppRepository
    @ObservedObject private var scheduler: NotificationScheduler
    @State private var errorMessage: String?
    @State private var showResetConfirmation = false

    init(container: AppContainer) {
        self.container = container
        self.repository = container.repository
        self.scheduler = container.notificationScheduler
    }

    var body: some View {
        Form {
            Section {
                Toggle("Уведомления", isOn: masterToggle)
            } footer: {
                Text("Выключение удаляет все ожидающие уведомления приложения, но выбранные интервалы остаются сохранёнными.")
            }

            if scheduler.authorizationState == .denied {
                Section {
                    Label("Уведомления запрещены в настройках iPhone.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Открыть настройки iPhone") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section {
                if let config = repository.currentConfiguration() {
                    ForEach(config.breaks.sorted(by: { $0.sortOrder < $1.sortOrder })) { item in
                        NavigationLink {
                            NotificationRuleEditorView(container: container, breakItem: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                Text("\(AppFormatters.time(minuteOfDay: item.startMinute))–\(AppFormatters.time(minuteOfDay: item.endMinute))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Сначала завершите настройку условий работы.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Перерывы")
            } footer: {
                if scheduler.scheduledCount > 0 {
                    Text("Сейчас запланировано ближайших уведомлений: \(scheduler.scheduledCount).")
                }
            }

            Section {
                Button("Сбросить настройки уведомлений", role: .destructive) {
                    showResetConfirmation = true
                }
            } footer: {
                Text("Сброс очищает все выбранные и пользовательские интервалы, но не меняет расписание самих перерывов и остальные данные приложения.")
            }
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await scheduler.refreshAuthorization()
            await scheduler.reschedule(context: repository.earningsContext())
        }
        .confirmationDialog("Сбросить все интервалы уведомлений?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { resetRules() }
            Button("Отмена", role: .cancel) { }
        }
        .appErrorAlert($errorMessage)
    }

    private var masterToggle: Binding<Bool> {
        Binding(
            get: { repository.preferences.notificationsEnabled },
            set: { enabled in
                do {
                    try repository.setNotificationsEnabled(enabled)
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }

                if enabled {
                    Task {
                        _ = await scheduler.requestAuthorizationIfNeeded()
                        await scheduler.reschedule(context: repository.earningsContext())
                    }
                } else {
                    scheduler.disableImmediately()
                }
            }
        )
    }

    private func resetRules() {
        do {
            try repository.resetNotificationRules()
            container.rescheduleNotifications()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
