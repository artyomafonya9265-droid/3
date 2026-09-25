import SwiftUI
import UIKit

struct OnboardingView: View {
    let container: AppContainer
    @State private var page = 0
    @State private var rateText = ""
    @State private var shiftStartMinute: Int?
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var workStartDate: Date?
    @State private var timeZoneOffsetSeconds = 9 * 3600
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case rate }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                TabView(selection: $page) {
                    ratePage.tag(0)
                    shiftPage.tag(1)
                    calendarPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86), value: page)

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Назад") { page -= 1 }
                            .buttonStyle(.bordered)
                    }
                    Button(page == 2 ? "Готово" : "Продолжить") {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationTitle("Настройка")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .appErrorAlert($errorMessage)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var ratePage: some View {
        onboardingPage(icon: "rublesign.circle.fill", title: "Ваша ставка", subtitle: "Ставка нигде не отправляется и хранится только на iPhone.") {
            TextField("Например, 500", text: $rateText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .rate)
                .font(.title2.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Почасовая ставка в рублях")
            Text("₽ в час")
                .foregroundStyle(.secondary)
        }
    }

    private var shiftPage: some View {
        onboardingPage(icon: "clock.badge.checkmark.fill", title: "Ваша смена", subtitle: "Введите время начала в формате 24 часа и длительность смены.") {
            if shiftStartMinute == nil {
                Button("Выбрать время начала") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
                    shiftStartMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                }
                .buttonStyle(.bordered)
            } else {
                MinuteOfDayPicker(
                    title: "Начало смены",
                    minute: Binding(
                        get: { shiftStartMinute ?? 0 },
                        set: { shiftStartMinute = $0 }
                    )
                )
            }
            HStack {
                Stepper("Часы: \(durationHours)", value: $durationHours, in: 0...24)
                Stepper("Минуты: \(durationMinutes)", value: $durationMinutes, in: 0...59)
            }
            Text("Длительность: \(AppFormatters.duration(minutes: durationHours * 60 + durationMinutes))")
                .foregroundStyle(.secondary)
        }
    }

    private var calendarPage: some View {
        onboardingPage(icon: "calendar.badge.clock", title: "Начало и часовой пояс", subtitle: "Рабочие даты, смены и перерывы считаются в этом часовом поясе, независимо от геолокации iPhone.") {
            if workStartDate == nil {
                Button("Выбрать дату начала работы") {
                    workStartDate = Date()
                }
                .buttonStyle(.bordered)
            } else {
                DatePicker(
                    "Считать заработок с",
                    selection: Binding(get: { workStartDate ?? Date() }, set: { workStartDate = $0 }),
                    displayedComponents: .date
                )
                .environment(\.timeZone, TimeZone(secondsFromGMT: timeZoneOffsetSeconds) ?? .current)
            }
            TimeZoneOffsetPicker(offsetSeconds: $timeZoneOffsetSeconds)
                .pickerStyle(.menu)
        }
    }

    private func onboardingPage<Content: View>(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                PremiumCard {
                    VStack(alignment: .leading, spacing: 16) { content() }
                }
            }
            .padding(24)
        }
    }

    private func advance() {
        focusedField = nil
        switch page {
        case 0:
            guard let rate = MoneyMath.parseDecimal(rateText), rate > 0 else {
                errorMessage = "Введите корректную почасовую ставку больше нуля."
                return
            }
            page = 1
        case 1:
            guard shiftStartMinute != nil else {
                errorMessage = "Выберите время начала смены."
                return
            }
            let duration = durationHours * 60 + durationMinutes
            guard (1...24 * 60).contains(duration) else {
                errorMessage = "Укажите длительность смены от 1 минуты до 24 часов."
                return
            }
            page = 2
        default:
            finish()
        }
    }

    private func finish() {
        guard let rate = MoneyMath.parseDecimal(rateText), rate > 0,
              let shiftStart = shiftStartMinute,
              let date = workStartDate else {
            errorMessage = "Заполните все обязательные параметры."
            return
        }
        let duration = durationHours * 60 + durationMinutes
        let zone = TimeZone(secondsFromGMT: timeZoneOffsetSeconds) ?? .current
        let day = DayKey(date: date, timeZone: zone)
        do {
            try container.repository.completeOnboarding(
                hourlyRate: rate,
                shiftStartMinute: shiftStart,
                shiftDurationMinutes: duration,
                workStartDay: day,
                timeZoneOffsetSeconds: timeZoneOffsetSeconds
            )
            container.rescheduleNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }


}
