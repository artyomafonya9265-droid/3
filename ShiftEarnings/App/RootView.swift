import SwiftUI
import UIKit

struct RootView: View {
    let container: AppContainer
    @ObservedObject private var repository: AppRepository
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(container: AppContainer) {
        self.container = container
        self.repository = container.repository
    }

    var body: some View {
        Group {
            if repository.preferences.onboardingCompleted {
                MainTabView(container: container)
                    .transition(.opacity)
            } else {
                OnboardingView(container: container)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: repository.preferences.onboardingCompleted)
        .safeAreaInset(edge: .top) {
            if container.persistenceWarning != nil {
                Label("Временный режим хранения — данные этой сессии не сохранятся", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .accessibilityLabel("Внимание. Временный режим хранения. Данные этой сессии не сохранятся после закрытия приложения.")
            }
        }
        .onAppear { container.refreshEnvironment() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { container.refreshEnvironment() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            container.refreshEnvironment()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            container.refreshEnvironment()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            container.refreshEnvironment()
        }
    }
}

struct StartupErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Хранилище недоступно",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(message)
        )
        .padding()
    }
}
