import SwiftUI

struct SettingsView: View {
    let container: AppContainer
    @ObservedObject private var repository: AppRepository
    @State private var errorMessage: String?

    init(container: AppContainer) {
        self.container = container
        self.repository = container.repository
    }

    var body: some View {
        NavigationStack {
            Form {
                if let warning = container.persistenceWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Работа") {
                    NavigationLink {
                        WorkSettingsView(container: container)
                    } label: {
                        SettingRow(icon: "briefcase.fill", title: "Условия работы", value: currentWorkSummary)
                    }

                    NavigationLink {
                        ConfigurationHistoryView(repository: repository)
                    } label: {
                        SettingRow(icon: "clock.arrow.circlepath", title: "История условий", value: "\(repository.earningsContext().configurations.count)")
                    }
                }

                Section("Уведомления") {
                    NavigationLink {
                        NotificationSettingsView(container: container)
                    } label: {
                        SettingRow(
                            icon: "bell.badge.fill",
                            title: "Уведомления",
                            value: repository.preferences.notificationsEnabled ? "Вкл." : "Выкл."
                        )
                    }
                }

                Section("Время") {
                    NavigationLink {
                        TimeVerificationView(container: container)
                    } label: {
                        SettingRow(icon: "network", title: "Сверить время")
                    }
                }

                Section {
                    Picker("Режим счётчика", selection: counterBinding) {
                        ForEach(CounterMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } header: {
                    Text("Интерфейс")
                } footer: {
                    Text("Плавный режим чаще обновляет интерфейс, но фактический заработок в обоих режимах рассчитывается по системному времени, а не по количеству UI-обновлений.")
                }

                Section("Хранение данных") {
                    Label("Ставки, история, календарь и настройки хранятся локально на этом iPhone.", systemImage: "lock.fill")
                    Label("Обычный запуск не выполняет сетевых запросов.", systemImage: "wifi.slash")
                }
            }
            .navigationTitle("Настройки")
        }
        .appErrorAlert($errorMessage)
    }

    private var counterBinding: Binding<CounterMode> {
        Binding(
            get: { repository.preferences.counterMode },
            set: { mode in
                do {
                    try repository.setCounterMode(mode)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        )
    }

    private var currentWorkSummary: String? {
        guard let config = repository.currentConfiguration() else { return nil }
        return "\(AppFormatters.rubles(config.hourlyRate))/ч"
    }
}
