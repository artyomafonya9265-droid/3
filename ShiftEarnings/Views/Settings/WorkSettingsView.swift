import SwiftUI
import UIKit

struct WorkSettingsView: View {
    let container: AppContainer
    @ObservedObject private var repository: AppRepository

    @State private var rateText: String
    @State private var shiftStartMinute: Int
    @State private var durationHours: Int
    @State private var durationMinutes: Int
    @State private var timeZoneOffsetSeconds: Int
    @State private var breaks: [BreakSnapshot]
    @State private var effectiveDate: Date
    @State private var workStartDate: Date
    @State private var errorMessage: String?
    @State private var saved = false

    init(container: AppContainer) {
        self.container = container
        self.repository = container.repository
        let config = container.repository.currentConfiguration() ?? WorkConfigurationSnapshot(
            id: UUID(),
            effectiveFrom: DayKey(date: Date(), timeZone: TimeZone(secondsFromGMT: 9 * 3600) ?? .current),
            hourlyRate: 0,
            shiftStartMinute: 8 * 60,
            shiftDurationMinutes: 8 * 60,
            timeZoneOffsetSeconds: 9 * 3600,
            breaks: BreakSnapshot.defaults
        )
        let zone = config.timeZone
        let today = DayKey(date: Date(), timeZone: zone)
        let startDay = container.repository.preferences.workStartDay ?? config.effectiveFrom

        _rateText = State(initialValue: MoneyMath.canonicalString(config.hourlyRate))
        _shiftStartMinute = State(initialValue: config.shiftStartMinute)
        _durationHours = State(initialValue: config.shiftDurationMinutes / 60)
        _durationMinutes = State(initialValue: config.shiftDurationMinutes % 60)
        _timeZoneOffsetSeconds = State(initialValue: config.timeZoneOffsetSeconds)
        _breaks = State(initialValue: config.breaks)
        _effectiveDate = State(initialValue: today.date(timeZone: zone))
        _workStartDate = State(initialValue: startDay.date(timeZone: zone))
    }

    var body: some View {
        Form {
            Section("Условия") {
                HStack {
                    Text("Ставка")
                    Spacer()
                    TextField("0", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                    Text("₽/ч").foregroundStyle(.secondary)
                }
                MinuteOfDayPicker(title: "Начало смены", minute: $shiftStartMinute)
                Stepper("Часы смены: \(durationHours)", value: $durationHours, in: 0...24)
                Stepper("Минуты: \(durationMinutes)", value: $durationMinutes, in: 0...59)
                Text("Итого: \(AppFormatters.duration(minutes: durationHours * 60 + durationMinutes))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TimeZoneOffsetPicker(offsetSeconds: $timeZoneOffsetSeconds)
            }

            Section {
                DatePicker("Считать заработок с", selection: $workStartDate, displayedComponents: .date)
                    .environment(\.timeZone, selectedTimeZone)
                DatePicker("Применить изменения с", selection: $effectiveDate, displayedComponents: .date)
                    .environment(\.timeZone, selectedTimeZone)
            } header: {
                Text("История")
            } footer: {
                Text("Изменения ставки, смены, часового пояса и перерывов сохраняются новой версией с выбранной даты. Более ранние дни остаются рассчитаны по прежним условиям.")
            }

            Section("Перерывы") {
                ForEach($breaks) { $item in
                    NavigationLink {
                        BreakEditorView(breakItem: $item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                Text("\(AppFormatters.time(minuteOfDay: item.startMinute))–\(AppFormatters.time(minuteOfDay: item.endMinute))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.isPaid ? "Оплачивается" : "Не оплачивается")
                                .font(.caption)
                                .foregroundStyle(item.isPaid ? Color.secondary : Color.orange)
                        }
                    }
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Label(saved ? "Сохранено" : "Сохранить условия", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Условия работы")
        .navigationBarTitleDisplayMode(.inline)
        .appErrorAlert($errorMessage)
    }

    private var selectedTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timeZoneOffsetSeconds) ?? .current
    }

    private func save() {
        saved = false
        guard let rate = MoneyMath.parseDecimal(rateText), rate > 0 else {
            errorMessage = "Введите корректную ставку больше нуля."
            return
        }
        let duration = durationHours * 60 + durationMinutes
        guard (1...24 * 60).contains(duration) else {
            errorMessage = "Длительность смены должна быть от 1 минуты до 24 часов."
            return
        }
        let workStart = DayKey(date: workStartDate, timeZone: selectedTimeZone)
        let effective = DayKey(date: effectiveDate, timeZone: selectedTimeZone)

        do {
            try repository.saveWorkSettings(
                workStartDay: workStart,
                effectiveFrom: effective,
                hourlyRate: rate,
                shiftStartMinute: shiftStartMinute,
                shiftDurationMinutes: duration,
                timeZoneOffsetSeconds: timeZoneOffsetSeconds,
                breaks: breaks
            )
            saved = true
            container.rescheduleNotifications()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension DayKey {
    func date(timeZone: TimeZone) -> Date {
        date(atMinute: 12 * 60, timeZone: timeZone) ?? Date()
    }
}
