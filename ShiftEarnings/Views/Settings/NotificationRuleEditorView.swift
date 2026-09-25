import SwiftUI

struct NotificationRuleEditorView: View {
    let container: AppContainer
    let breakItem: BreakSnapshot
    @ObservedObject private var repository: AppRepository

    @State private var rule: NotificationRuleSnapshot
    @State private var customStartText = ""
    @State private var customEndText = ""
    @State private var errorMessage: String?
    @State private var applyToAllConfirmation = false

    private let presets = [30, 20, 15, 10, 5, 1, 0]

    init(container: AppContainer, breakItem: BreakSnapshot) {
        self.container = container
        self.breakItem = breakItem
        self.repository = container.repository
        _rule = State(initialValue: container.repository.notificationRule(for: breakItem.stableKey))
    }

    var body: some View {
        Form {
            Section("До начала") {
                ForEach(presets, id: \.self) { value in
                    Toggle(offsetTitle(value), isOn: presetBinding(value, phase: .start))
                }
                customInput(phase: .start)
                customOffsets(rule.customStartOffsets, phase: .start)
            }

            Section("До окончания") {
                ForEach(presets, id: \.self) { value in
                    Toggle(offsetTitle(value), isOn: presetBinding(value, phase: .end))
                }
                customInput(phase: .end)
                customOffsets(rule.customEndOffsets, phase: .end)
            }

            Section {
                Button("Применить настройки ко всем перерывам") {
                    applyToAllConfirmation = true
                }
            }
        }
        .navigationTitle(breakItem.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Применить эти интервалы ко всем перерывам?", isPresented: $applyToAllConfirmation, titleVisibility: .visible) {
            Button("Применить") { applyToAll() }
            Button("Отмена", role: .cancel) { }
        }
        .appErrorAlert($errorMessage)
    }

    private func presetBinding(_ value: Int, phase: BreakPhase) -> Binding<Bool> {
        Binding(
            get: {
                phase == .start ? rule.beforeStartOffsets.contains(value) : rule.beforeEndOffsets.contains(value)
            },
            set: { isOn in
                if phase == .start {
                    if isOn { rule.beforeStartOffsets.insert(value) } else { rule.beforeStartOffsets.remove(value) }
                } else {
                    if isOn { rule.beforeEndOffsets.insert(value) } else { rule.beforeEndOffsets.remove(value) }
                }
                saveRule()
            }
        )
    }

    private func customInput(phase: BreakPhase) -> some View {
        HStack {
            TextField("Свой интервал, минут", text: phase == .start ? $customStartText : $customEndText)
                .keyboardType(.numberPad)
            Button("Добавить") { addCustom(phase) }
        }
    }

    @ViewBuilder
    private func customOffsets(_ values: Set<Int>, phase: BreakPhase) -> some View {
        ForEach(values.sorted(), id: \.self) { value in
            HStack {
                Text("За \(RussianPlural.minutes(value))")
                Spacer()
                Button(role: .destructive) {
                    if phase == .start { rule.customStartOffsets.remove(value) }
                    else { rule.customEndOffsets.remove(value) }
                    saveRule()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Удалить интервал \(value) минут")
            }
        }
    }

    private func offsetTitle(_ value: Int) -> String {
        value == 0 ? "В момент события" : "За \(RussianPlural.minutes(value))"
    }

    private func addCustom(_ phase: BreakPhase) {
        let text = phase == .start ? customStartText : customEndText
        guard let value = Int(text), (1...720).contains(value) else {
            errorMessage = ValidationError.invalidNotificationOffset.localizedDescription
            return
        }
        if phase == .start {
            rule.customStartOffsets.insert(value)
            customStartText = ""
        } else {
            rule.customEndOffsets.insert(value)
            customEndText = ""
        }
        saveRule()
    }

    private func saveRule() {
        do {
            try repository.saveNotificationRule(rule)
            container.rescheduleNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyToAll() {
        do {
            try repository.applyNotificationRuleToAll(rule)
            container.rescheduleNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
