import SwiftUI

struct MainTabView: View {
    let container: AppContainer

    var body: some View {
        TabView {
            DashboardView(container: container)
                .tabItem { Label("Главная", systemImage: "rublesign.circle.fill") }

            WorkCalendarView(container: container)
                .tabItem { Label("Календарь", systemImage: "calendar") }

            SettingsView(container: container)
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
        .tint(.accentColor)
    }
}
