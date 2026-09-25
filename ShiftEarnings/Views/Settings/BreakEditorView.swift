import SwiftUI

struct BreakEditorView: View {
    @Binding var breakItem: BreakSnapshot

    var body: some View {
        Form {
            Section("Перерыв") {
                TextField("Название", text: $breakItem.name)
                Picker("Тип", selection: $breakItem.type) {
                    ForEach(BreakType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                MinuteOfDayPicker(title: "Начало", minute: $breakItem.startMinute)
                MinuteOfDayPicker(title: "Окончание", minute: $breakItem.endMinute)
                Toggle("Оплачиваемый", isOn: $breakItem.isPaid)
            }

            Section {
                Text(breakItem.isPaid
                     ? "Оплачиваемый перерыв не останавливает начисление."
                     : "Неоплачиваемая часть, которая пересекается со сменой, вычитается из оплачиваемого времени.")
            }
        }
        .navigationTitle(breakItem.name.isEmpty ? "Перерыв" : breakItem.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
