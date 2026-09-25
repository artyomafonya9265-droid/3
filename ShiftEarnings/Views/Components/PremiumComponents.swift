import SwiftUI

struct PremiumCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct MetricCard: View {
    let title: String
    let amount: Decimal?
    let systemImage: String

    var body: some View {
        PremiumCard {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let amount {
                        Text(AppFormatters.rubles(amount))
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                    } else {
                        Text("Расчёт…")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Статистика рассчитывается")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    let value: String?

    init(icon: String, title: String, value: String? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(title)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct MinuteOfDayPicker: View {
    let title: String
    @Binding var minute: Int

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                return calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: minute / 60, minute: minute % 60)) ?? Date()
            },
            set: { newValue in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute)
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
            .environment(\.locale, Locale(identifier: "ru_RU"))
    }
}

struct TimeZoneOffsetPicker: View {
    @Binding var offsetSeconds: Int

    var body: some View {
        Picker("Рабочий часовой пояс", selection: $offsetSeconds) {
            ForEach(-12...14, id: \.self) { hour in
                Text(label(for: hour)).tag(hour * 3600)
            }
        }
    }

    private func label(for hour: Int) -> String {
        let sign = hour >= 0 ? "+" : "−"
        let base = "UTC\(sign)\(abs(hour))"
        if hour == 9 { return "Икабья · \(base) · +6 к Москве" }
        return base
    }
}

extension View {
    func appErrorAlert(_ error: Binding<String?>) -> some View {
        alert("Не удалось выполнить действие", isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: {
            Text(error.wrappedValue ?? "Неизвестная ошибка")
        }
    }
}
