import SwiftUI
import UIKit

struct DashboardView: View {
    let container: AppContainer
    @ObservedObject private var repository: AppRepository
    @StateObject private var viewModel: DashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 46

    init(container: AppContainer) {
        self.container = container
        self.repository = container.repository
        _viewModel = StateObject(wrappedValue: DashboardViewModel(repository: container.repository, engine: container.earningsEngine))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: viewModel.context.preferences.counterMode.refreshInterval)) { timeline in
                dashboard(at: timeline.date)
            }
            .navigationTitle("Заработок")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .onAppear { viewModel.reload() }
        .onChange(of: repository.revision) { _, _ in viewModel.reload() }
        .onChange(of: container.refreshToken) { _, _ in viewModel.reload() }
    }

    @ViewBuilder
    private func dashboard(at now: Date) -> some View {
        if let snapshot = viewModel.snapshot(at: now) {
            ScrollView {
                VStack(spacing: 16) {
                    primaryAmount(snapshot.day.totalEarnings)
                    statusCard(snapshot.day, now: now)
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 12) {
                                MetricCard(title: "Этот месяц", amount: viewModel.isLoadingHistory ? nil : snapshot.monthEarnings, systemImage: "calendar")
                                MetricCard(title: "За всё время", amount: viewModel.isLoadingHistory ? nil : snapshot.allTimeEarnings, systemImage: "chart.line.uptrend.xyaxis")
                            }
                        } else {
                            HStack(spacing: 12) {
                                MetricCard(title: "Этот месяц", amount: viewModel.isLoadingHistory ? nil : snapshot.monthEarnings, systemImage: "calendar")
                                MetricCard(title: "За всё время", amount: viewModel.isLoadingHistory ? nil : snapshot.allTimeEarnings, systemImage: "chart.line.uptrend.xyaxis")
                            }
                        }
                    }
                    if snapshot.day.overtimeEarnings > 0 {
                        PremiumCard {
                            Label("Переработка сегодня: \(AppFormatters.rubles(snapshot.day.overtimeEarnings))", systemImage: "clock.badge.plus")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                .padding(16)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86), value: snapshot.day.state.title)
            }
        } else {
            ContentUnavailableView(
                "Нужна первичная настройка",
                systemImage: "slider.horizontal.3",
                description: Text("Укажите ставку, смену и дату начала работы.")
            )
        }
    }

    private func primaryAmount(_ amount: Decimal) -> some View {
        VStack(spacing: 8) {
            Text("Заработано сегодня")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(AppFormatters.rubles(amount))
                .font(.system(size: amountFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .linear(duration: 0.10), value: AppFormatters.rubles(amount))
                .accessibilityLabel("Заработано сегодня \(AppFormatters.rubles(amount))")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func statusCard(_ day: DayEarnings, now: Date) -> some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(day.state.title, systemImage: statusIcon(day.state))
                        .font(.headline)
                    Spacer()
                    if day.state == .working {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 9, height: 9)
                            .accessibilityHidden(true)
                    }
                }

                if let config = viewModel.context.configurations
                    .filter({ $0.effectiveFrom <= day.day })
                    .max(by: { $0.effectiveFrom < $1.effectiveFrom }) {
                    if let activeBreak = day.activeBreak {
                        Text("\(time(activeBreak.start, zone: config.timeZone)) — \(time(activeBreak.end, zone: config.timeZone))")
                            .font(.title3.monospacedDigit().weight(.semibold))
                    } else if let start = day.shiftStart, let end = day.shiftEnd {
                        Text("\(time(start, zone: config.timeZone)) — \(time(end, zone: config.timeZone))")
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }

                ProgressView(value: day.progress)
                    .tint(.accentColor)
                    .animation(reduceMotion ? nil : .linear(duration: 0.15), value: day.progress)
                    .accessibilityLabel("Прогресс смены")
                    .accessibilityValue("\(Int(day.progress * 100)) процентов")

                Text(statusDetail(day, now: now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusDetail(_ day: DayEarnings, now: Date) -> String {
        switch day.state {
        case .working:
            return day.secondsRemaining > 0 ? "До конца смены \(AppFormatters.remaining(seconds: day.secondsRemaining))" : "Смена подходит к концу"
        case .paidBreak:
            if let activeBreak = day.activeBreak {
                return "Начисление продолжается · до окончания \(AppFormatters.remaining(seconds: activeBreak.end.timeIntervalSince(now)))"
            }
            return "Оплачиваемый перерыв · начисление продолжается"
        case .unpaidBreak:
            if let activeBreak = day.activeBreak {
                return "Начисление приостановлено · до окончания \(AppFormatters.remaining(seconds: activeBreak.end.timeIntervalSince(now)))"
            }
            return "Начисление временно приостановлено"
        case .completed:
            return "Обычное начисление за смену зафиксировано"
        case .dayOff:
            return day.overtimeEarnings > 0 ? "Обычная смена не начисляется; учтена только переработка" : "Обычная смена не начисляется"
        case .beforeShift:
            return "Начисление начнётся с началом смены"
        case .beforeWorkStart:
            return "Дата начала работы ещё не наступила"
        case .notConfigured:
            return "Проверьте настройки работы"
        }
    }

    private func statusIcon(_ state: ShiftState) -> String {
        switch state {
        case .working: return "bolt.fill"
        case .paidBreak: return "cup.and.saucer.fill"
        case .unpaidBreak: return "fork.knife"
        case .completed: return "checkmark.circle.fill"
        case .dayOff: return "moon.zzz.fill"
        case .beforeShift, .beforeWorkStart: return "clock.fill"
        case .notConfigured: return "exclamationmark.triangle.fill"
        }
    }

    private func time(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
