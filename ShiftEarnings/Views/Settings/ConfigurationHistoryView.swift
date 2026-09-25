import SwiftUI

struct ConfigurationHistoryView: View {
    @ObservedObject var repository: AppRepository

    var body: some View {
        List {
            ForEach(repository.earningsContext().configurations.sorted(by: { $0.effectiveFrom > $1.effectiveFrom })) { config in
                VStack(alignment: .leading, spacing: 7) {
                    Text("С \(AppFormatters.date(config.effectiveFrom))")
                        .font(.headline)
                    Text("\(AppFormatters.rubles(config.hourlyRate)) в час")
                    Text("Смена: \(AppFormatters.time(minuteOfDay: config.shiftStartMinute)) · \(AppFormatters.duration(minutes: config.shiftDurationMinutes))")
                        .foregroundStyle(.secondary)
                    Text(timeZoneLabel(config.timeZoneOffsetSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("История условий")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeZoneLabel(_ offset: Int) -> String {
        let hours = offset / 3600
        let sign = hours >= 0 ? "+" : "−"
        return hours == 9 ? "Икабья · UTC+9" : "UTC\(sign)\(abs(hours))"
    }
}
