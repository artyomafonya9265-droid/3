import SwiftUI

@main
struct ShiftEarningsApp: App {
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            switch bootstrap.state {
            case .ready(let container):
                RootView(container: container)
                    .modelContainer(container.modelContainer)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
            case .failed(let message):
                StartupErrorView(message: message)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
            }
        }
    }
}
