import SwiftUI
import UIKit

struct WorkCalendarView: View {
    let container: AppContainer
    @ObservedObject private var repository: AppRepository
    @State private var displayedMonth: DayKey
    @State private var selectedDay: DayKey?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    init(container: AppContainer) {
        self.container = container
        self.repository = container.repository
        let context = container.repository.earningsContext()
        let today = container.earningsEngine.currentDay(at: Date(), context: context)
            ?? DayKey(date: Date(), timeZone: TimeZone(secondsFromGMT: 9 * 3600) ?? .current)
        _displayedMonth = State(initialValue: today.startOfMonth)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    monthHeader
                    weekdayHeader
                    calendarGrid
                    legend
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Календарь")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedDay) { day in
            DayDetailView(container: container, day: day)
                .presentationDetents([.medium, .large])
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { displayedMonth = displayedMonth.previousMonthStart } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(monthTitle)
                .font(.title3.bold())
            Spacer()
            Button { displayedMonth = displayedMonth.nextMonthStart } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdayNames, id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let context = repository.earningsContext()
        let today = container.earningsEngine.currentDay(at: Date(), context: context)
        let workStart = context.preferences.workStartDay

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<leadingEmptyCells, id: \.self) { _ in
                Color.clear.frame(height: 46)
            }
            ForEach(1...displayedMonth.daysInMonth(), id: \.self) { dayNumber in
                let day = DayKey(year: displayedMonth.year, month: displayedMonth.month, day: dayNumber)
                let dayOverride = context.dayOverrides[day] ?? DayOverrideSnapshot(day: day, isDayOff: false, overtimeMinutes: 0, overtimeMultiplier: 1)
                CalendarDayCell(
                    number: dayNumber,
                    isToday: day == today,
                    isDayOff: dayOverride.isDayOff,
                    hasOvertime: dayOverride.overtimeMinutes > 0,
                    isBeforeWorkStart: workStart.map { day < $0 } ?? true
                )
                .onTapGesture { selectedDay = day }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(accessibilityLabel(for: day, dayOverride: dayOverride, today: today))
            }
        }
    }

    private var legend: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 10) {
                legendRow(color: .accentColor, text: "Сегодня", outlined: true)
                legendRow(color: .secondary, text: "Выходной")
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.plus")
                        .foregroundStyle(.orange)
                    Text("Есть переработка").font(.footnote)
                }
            }
        }
    }

    private func legendRow(color: Color, text: String, outlined: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(outlined ? Color.clear : color.opacity(0.2))
                .overlay { Circle().stroke(color, lineWidth: outlined ? 2 : 0) }
                .frame(width: 18, height: 18)
            Text(text).font(.footnote)
        }
    }

    private var leadingEmptyCells: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = repository.currentConfiguration()?.timeZone ?? .current
        guard let date = displayedMonth.date(atMinute: 12 * 60, timeZone: calendar.timeZone) else { return 0 }
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private var monthTitle: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: DateComponents(year: displayedMonth.year, month: displayedMonth.month, day: 1)) else {
            return displayedMonth.description
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func accessibilityLabel(for day: DayKey, dayOverride: DayOverrideSnapshot, today: DayKey?) -> String {
        var parts = [AppFormatters.date(day)]
        if day == today { parts.append("сегодня") }
        if dayOverride.isDayOff { parts.append("выходной") }
        if dayOverride.overtimeMinutes > 0 { parts.append("переработка \(AppFormatters.duration(minutes: dayOverride.overtimeMinutes))") }
        return parts.joined(separator: ", ")
    }
}

private struct CalendarDayCell: View {
    let number: Int
    let isToday: Bool
    let isDayOff: Bool
    let hasOvertime: Bool
    let isBeforeWorkStart: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text("\(number)")
                .font(.body.monospacedDigit().weight(isToday ? .bold : .regular))
                .foregroundStyle(isBeforeWorkStart ? .tertiary : .primary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isDayOff ? Color.secondary.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
                }

            if hasOvertime {
                Image(systemName: "clock.badge.plus")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct DayDetailView: View {
    let container: AppContainer
    let day: DayKey
    @ObservedObject private var repository: AppRepository
    @Environment(\.dismiss) private var dismiss
    @State private var editingOvertime = false
    @State private var overtimeHours: Int
    @State private var overtimeMinutes: Int
    @State private var errorMessage: String?

    init(container: AppContainer, day: DayKey) {
        self.container = container
        self.day = day
        self.repository = container.repository
        let overtime = container.repository.dayOverride(for: day).overtimeMinutes
        _overtimeHours = State(initialValue: overtime / 60)
        _overtimeMinutes = State(initialValue: overtime % 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Дата", value: AppFormatters.date(day))
                    LabeledContent("Режим", value: currentOverride.isDayOff ? "Выходной" : "Рабочий день")
                    if currentOverride.overtimeMinutes > 0 {
                        LabeledContent("Переработка", value: AppFormatters.duration(minutes: currentOverride.overtimeMinutes))
                    }
                }

                Section {
                    Button(currentOverride.isDayOff ? "Убрать выходной" : "Назначить выходной") {
                        setDayOff(!currentOverride.isDayOff)
                    }
                }

                Section {
                    if editingOvertime {
                        Stepper("Часы: \(overtimeHours)", value: $overtimeHours, in: 0...24)
                        Stepper("Минуты: \(overtimeMinutes)", value: $overtimeMinutes, in: 0...59)
                        Button("Сохранить переработку") { saveOvertime() }
                            .disabled(overtimeHours * 60 + overtimeMinutes == 0)
                        Button("Отмена", role: .cancel) { editingOvertime = false }
                    } else if currentOverride.overtimeMinutes == 0 {
                        Button("Добавить переработку") {
                            overtimeHours = 0
                            overtimeMinutes = 0
                            editingOvertime = true
                        }
                    } else {
                        Button("Изменить переработку") {
                            overtimeHours = currentOverride.overtimeMinutes / 60
                            overtimeMinutes = currentOverride.overtimeMinutes % 60
                            editingOvertime = true
                        }
                        Button("Удалить переработку", role: .destructive) { removeOvertime() }
                    }
                } header: {
                    Text("Переработка")
                } footer: {
                    Text("Переработка оплачивается по обычной почасовой ставке и может существовать даже в выходной день.")
                }
            }
            .navigationTitle("День")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .appErrorAlert($errorMessage)
    }

    private var currentOverride: DayOverrideSnapshot {
        repository.dayOverride(for: day)
    }

    private func setDayOff(_ value: Bool) {
        do {
            try repository.setDayOff(value, for: day)
            container.rescheduleNotifications()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveOvertime() {
        let total = overtimeHours * 60 + overtimeMinutes
        guard total > 0 && total <= 24 * 60 else {
            errorMessage = ValidationError.invalidOvertime.localizedDescription
            return
        }
        do {
            try repository.setOvertime(minutes: total, for: day)
            editingOvertime = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeOvertime() {
        do {
            try repository.setOvertime(minutes: 0, for: day)
            overtimeHours = 0
            overtimeMinutes = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension DayKey {
    var nextMonthStart: DayKey {
        if month == 12 { return DayKey(year: year + 1, month: 1, day: 1) }
        return DayKey(year: year, month: month + 1, day: 1)
    }

    var previousMonthStart: DayKey {
        if month == 1 { return DayKey(year: year - 1, month: 12, day: 1) }
        return DayKey(year: year, month: month - 1, day: 1)
    }
}
